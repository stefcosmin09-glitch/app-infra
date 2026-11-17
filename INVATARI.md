# Ce am învățat construind `app-infra`

> Document de învățare, scris după ce am terminat deploy-ul complet al aplicației TradeScheduler pe AWS cu Terraform.
> Codul și comentariile sunt în repo; aici explic **de ce** am făcut fiecare lucru, ce a greșit și ce trebuie să știu din memorie.

---

## 1. Ce am construit, pe scurt

Un **deploy complet de aplicație**, nu doar infrastructură goală:

```
Internet → ALB (subnete publice) → ECS Fargate task (subnete private) → RDS PostgreSQL (subnete private)
                                          ↓
                    ECR (imagine) · Secrets Manager (secreturi) · CloudWatch (loguri)
                                          ↓
                          ieșire la internet prin NAT Gateway (1 singur)
```

Stare: S3 (`app-infra-tfstate-...`), cu locking nativ prin `use_lockfile = true`.
Regiune: `eu-central-1`. Buget AWS: 5 USD/lună (deliberat mic, ca să mă avertizeze imediat).

Rezultat verificat înainte de `destroy`: `GET /health` → **HTTP 200** `{"status":"ok"}`, target `healthy`, ECS `1/1 running`.

---

## 2. AWS — ce am învățat

### 2.1 VPC, subnete, IGW, NAT Gateway

- **VPC** = rețeaua privată din AWS. Am ales `10.0.0.0/20`, împărțit în 4 subnete: câte unul public și unul privat în fiecare din 2 zone de disponibilitate (`eu-central-1a`, `-1b`).
- **Internet Gateway (IGW)** = poarta de intrare/ieșire la internet pentru subnetele **publice**.
- **NAT Gateway** = permite resurselor din subnetele **private** să iasă la internet (ca să tragă imaginea din ECR, să citească Secrets Manager, să scrie loguri), **fără să fie accesibile din exterior**.
- Am folosit **un singur NAT Gateway** (~32 USD/lună) în loc de câte unul per zonă (~64 USD). E o decizie **conștientă de cost**, nu de disponibilitate: dacă zona aia cade, ieșirea la internet dispare. În producție aș pune câte unul în fiecare zonă.

**Ideea cheie:** subnet public ≠ subnet privat prin iptables, ci prin tabela de rutare: publicul are rută directă către IGW, privatul are rută către NAT.

### 2.2 Security Groups

Am învățat să le văd ca pe un **lanț de firewall-uri care se referă unul la altul**, nu la adrese IP:

```
SG-ALB   → ingress 80/443 de pe 0.0.0.0/0
SG-ECS   → ingress doar pe portul app-ului (8080), SURSA = SG-ALB
SG-RDS   → ingress doar pe 5432, SURSA = SG-ECS
```

Avantajul: când ECS-ul își schimbă IP-ul (la fiecare task nou), regula rămâne validă pentru că sursa e *security group-ul*, nu un IP. Toate au egress liber ca să poată ajunge la Nat/serviciile AWS.

### 2.3 ECS Fargate

- **Fargate** = serverless pentru containere. Nu am servere EC2 de administrat.
- **`network_mode = "awsvpc"`** e obligatoriu: fiecare task primește propriul **ENI** (Elastic Network Interface) și propriul IP în VPC — ca o mini-instanță. De aceea putem pune security group per task. Pe ECS cu EC2, mai multe taskuri împărtășesc același host.
- **`assign_public_ip = false`** — taskurile stau în subnete private; singura intrare e prin ALB. Asta e diferența dintre „expus la internet" și „accesibil doar prin load balancer".
- **Task definition** = rețeta containerului (imagine, porturi, CPU 0.25 vCPU, memorie 0.5 GB, roluri, loguri).
- **ECS service** = menține `desired_count = 1`; dacă taskul moare, pornește altul.
- **`target_type = "ip"`** la ALB: Fargate nu are o instanță EC2 de înregistrat, deci ALB-ul trimite trafic direct către IP-ul taskului.

**Cea mai importantă distincție — execution role vs task role:**

| Rol | Cine îl folosește | Pentru ce |
|---|---|---|
| **Execution role** | ECS **agent** (infrastructura) | trage imaginea din ECR, citește secrete, scrie loguri în CloudWatch |
| **Task role** | **codul aplicației** (Pythonul din container) | dacă aplicația ar accesa S3/DynamoDB din cod |

Dacă execution role-ul nu are `secretsmanager:GetSecretValue`, taskul **nu pornește** — ECS agentul nu poate injecta secretul și apare `ResourceInitializationError`.

### 2.4 IAM

- **Trust policy** cu `sts:AssumeRole` = „serviciul ECS are voie să împrumute acest rol și să acționeze în numele lui". Fără ea, rolul există dar nu îl poate folosi nimeni.
- **Managed policy** (`AmazonECSTaskExecutionRolePolicy`) = predefinită de AWS, se actualizează automat când AWS adaugă permisiuni.
- **Inline policy** = scrisă de mine, pentru ce e specific proiectului (ex. cititul secretelor). Am învățat să le folosesc pe ambele: managed pentru general, inline pentru specific.
- `ecr:GetAuthorizationToken` e permisiunea care trebuie pusă pe `Resource = "*"` (AWS nu o acceptă restricționată).

### 2.5 ECR

- Repository-ul stochează imaginea Docker. `scan_on_push = true` scanază vulnerabilitățile la fiecare push.
- Am folosit `MUTABLE` și tagul `latest` pentru demo. În producție: tag cu commit SHA + imagine **imutable**, ca să știi exact ce versiune rulează.
- **`force_delete = true`** — lecție din greșeală: AWS refuză să șteargă un repository care conține imagini (`RepositoryNotEmptyException`). Și nu e suficient să scrii în cod: trebuie făcut `terraform apply` ca valoarea să ajungă în **state**, abia apoi `destroy` funcționează.

### 2.6 ALB (Application Load Balancer)

- E în subnete **publice**, `internal = false`, ascultă pe portul 80 și face forward către target group.
- **Target group** = grupul de destinații; `target_type = "ip"`, port `8080`, `protocol = HTTP`.
- **Health check** pe `/health`, cu `matcher = 200`: ALB verifică periodic, iar dacă eșuează de 3 ori, taskul e marcat `unhealthy`, nu mai primește trafic și ECS îl poate reporni.
- `enable_deletion_protection = false` pentru demo — altfel `terraform destroy` eșuează.
- Am renunțat la `access_logs` către S3 în demo (necesită bucket + permisiuni suplimentare).

### 2.7 RDS

- PostgreSQL pe `db.t3.micro`, 20 GB gp3, **Single-AZ**, în subnete private, `publicly_accessible = false`.
- **Free tier are restricții:** backup retention mai mare de 1 zi e respins (`FreeTierRestrictionError`) → `backup_retention_period = 1`.
- **AWS retrage versiuni minore.** `engine_version = "16.9"` a funcționat la primul apply, dar câteva ore mai târziu nu mai era disponibilă. Soluția robustă: `engine_version = "16"` + `auto_minor_version_upgrade = true` — provider-ul alege cel mai nou minor disponibil.
- `skip_final_snapshot = true` și `deletion_protection = false` doar pentru demo.

### 2.8 Secrets Manager

- Parola DB-ului și cheia de semnare a aplicației stau aici, **nu** în cod, GitHub sau fișiere `.tf`.
- **`valueFrom`** în task definition: ECS agentul citește secretul la pornire și îl injectează ca variabilă de mediu; aplicația îl citește cu `os.getenv("DATABASE_URL")`.
- **AWS adaugă un sufix random de 6 caractere la ARN** (`db-url-eyny5u`). ARN-ul construit manual nu găsește secretul → soluția e `data "aws_secretsmanager_secret"` căutare **după nume**, care returnează ARN-ul corect.
- `DATABASE_URL` l-am pus ca `postgresql://user:pass@host:5432/db`, pentru că aplicația îl convertește singură la driverul `psycopg2`. Dacă aș fi adăugat `+psycopg2` eu, s-ar fi dublat.

### 2.9 CloudWatch, S3 state, Budget

- CloudWatch Log Group `/ecs/app-infra-staging`, retenție 14 zile — fără el nu vezi de ce a murit containerul.
- Starea Terraform în S3 cu **`use_lockfile = true`** — locking nativ, fără tabel DynamoDB separat (l-am creat, apoi l-am șters când am trecut la lockfile).
- AWS Budget de 5 USD/lună, intenționat sub costul real (~75–85 USD), ca să primesc alertă la orice cheltuială.

---

## 3. Terraform — ce am învățat

### Diferența dintre comenzi

| Comandă | Ce face | Atinge AWS? |
|---|---|---|
| `fmt` | formatează `.tf` | nu |
| `validate` | verifică **sintaxa** și referințele | nu |
| `plan` | calculează ce se va schimba, **citește data sources** | **da** |
| `apply` | creează/modifică resursele | da |
| `refresh` / `apply -refresh-only` | actualizează state-ul cu realitatea | da |
| `destroy` | șterge tot ce e în state | da |
| `output`, `state list` | citesc din state | nu |

**Lecția:** `validate` a trecut, dar `plan` a eșuat cu `reading Secrets Manager Secret: couldn't find resource`. Motivul: data sources se citesc la **plan time**, nu la validate. E un comportament *fail-fast* corect — mai bine eșuează acum decât să aplice o configurație care sigur nu merge.

### Concepte folosite

- **Resource vs data source**: resource = creez; data source = citesc ceva ce există deja.
- **Variabile**: `sensitive = true` ascunde valoarea din output, **dar nu o scoate din state** — de aceea `terraform.tfvars` e în `.gitignore`.
- **`jsonencode([...])`** pentru `container_definitions` — ECS vrea JSON, dar HCL e mai lizibil și se validează la plan.
- **Expresii `for`**: `[for k, v in var.app_environment : { name = k, value = v }]` transformă un map în lista de obiecte pe care o așteaptă ECS.
- **`merge(...)`** ca să adaug `PORT` din `app_port` peste variabilele de mediu.
- **Dependențe**: cele mai multe sunt implicite (referințe între resurse); `depends_on = [aws_lb_listener.http]` e explicit, ca să nu înregistreze taskuri într-un target group înainte să existe listener-ul.
- **`-target`** — l-am folosit ca să creez întâi RDS-ul, apoi ECR-ul, apoi restul. E util pentru ordonare, dar nu e de abuzat în ziua de zi.
- **State-ul e sursa adevărului.** Când am schimbat `force_delete` doar în cod, destroy-ul tot a eșuat: valoarea veche era în state. A trebuit `apply` întâi.

---

## 4. Greșelile mele și ce am învățat din ele

| Greșeala | Eroarea / simptomul | Fix |
|---|---|---|
| Două resurse `aws_ecr_repository "foo"` | `Duplicate resource` | un singur nume per tip resursă |
| `INMUTABLE_WITH_EXCLUSION`, `filler_type` | erori de validare | `IMMUTABLE`, `filter_type` |
| ARN secret hardcodat, fără sufix | taskul nu pornește | `data "aws_secretsmanager_secret"` după nume |
| Etichetă target group `-alb` | confuzie în consolă | `-tg` |
| `access_logs` la bucket inexistent, `deletion_protection = true` | apply/destroy eșuează | am omis logările și am pus `false` |
| Am copiat modul IAM de password policy | făcea altceva decât rolurile ECS | trust policy + execution/task role |
| `backup_retention_period > 1` | `FreeTierRestrictionError` | `1` |
| `engine_version = "16.3"` / `"16.9"` | `Cannot find version` | doar major `"16"` + auto-upgrade |
| Docker dispărut din WSL | `docker: command not found` | `apt install docker.io` + `service docker start` + `usermod -aG docker` |
| Ghilimele PowerShell → WSL | `cd: /mnt/c/Users/Stefanita: No such file` | script `.sh` scris în fișier, rulat cu `wsl -e bash script.sh` |
| ECR cu imagini la destroy | `RepositoryNotEmptyException` | `force_delete = true` + `apply` + `destroy` |

---

## 5. Ordinea corectă a unui deploy (dependențe reale)

Asta e poate cel mai util lucru învățat — infrastructura are o **ordine logică**, nu doar una de cod:

1. `bootstrap` → bucketul de stare
2. `terraform apply -target=aws_db_instance.main` → RDS-ul, ca să avem endpointul
3. `scripts/create-secrets.sh` → secreturile (folosesc endpointul RDS)
4. `terraform apply -target=aws_ecr_repository.app` → repository-ul
5. `scripts/build-and-push.sh` → imaginea în ECR
6. `terraform plan` + `apply` → tot restul (ECS poate acum porni taskuri care chiar funcționează)
7. `curl /health` → verificare
8. `terraform destroy` → oprirea costurilor

Dacă aplici totul dintr-o dată, ECS-ul încearcă să tragă o imagine inexistentă și intră într-un loop de reporniri.

---

## 6. Cum am depanat (ordinea care funcționează)

```
1. aws ecs describe-services  → evenimentele serviciului
2. aws ecs describe-tasks     → stoppedReason, exitCode
3. aws logs tail /ecs/...     → logurile reale ale containerului
4. aws elbv2 describe-target-health → starea țintelor
5. curl http://ALB/health     → comportamentul final
```

Am pățit să văd `running = 0` imediat după apply, dar taskul era doar în pornire (`pullStartedAt` → `pullStoppedAt`). **Nu trage concluzii prea devreme** — verifică `lastStatus` înainte să presupui că e o eroare.

---

## 7. Ce aș face diferit în producție

1. Două NAT Gateway (HA), nu unul.
2. HTTPS cu ACM + redirect de la HTTP, HSTS.
3. CI/CD real (GitHub Actions / CodeBuild), nu script manual.
4. Taguri imutabile cu commit SHA, nu `latest`.
5. Politica IAM pentru secrete restricționată la ARN-urile exacte, nu `Resource = "*"`.
6. Stare separată per mediu + modul reutilizabil.
7. RDS Multi-AZ, backup, deletion protection.
8. Autoscaling pentru ECS și `wait_for_steady_state = true`.
9. WAF, access logs, alarme pentru 5xx și targeturi unhealthy.

---

## 8. Cheat sheet

```bash
# Terraform
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
terraform output -raw alb_dns_name
terraform state list
terraform destroy

# Verificare
ALB="$(terraform output -raw alb_dns_name)"
curl -i "http://${ALB}/health"
aws ecs describe-services --cluster app-infra-staging-cluster --services app-infra-staging-service
aws logs tail /ecs/app-infra-staging --follow
aws elbv2 describe-target-health --target-group-arn "$(aws elbv2 describe-target-groups --names app-infra-staging-tg --query 'TargetGroups[0].TargetGroupArn' --output text)"

# Curățenie
terraform destroy
aws secretsmanager delete-secret --secret-id app-infra/staging/db-url --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id app-infra/staging/secret-key --force-delete-without-recovery
```

---

## 9. Întrebări la care trebuie să pot răspunde din memorie

1. De ce Fargate-ul are nevoie de `awsvpc`? → pentru că nu are host EC2; fiecare task primește propriul ENI.
2. Care e diferența dintre execution role și task role? → agent vs codul aplicației.
3. De ce `target_type = "ip"`? → nu avem instanțe EC2 de înregistrat.
4. Cum ajunge `DATABASE_URL` în container? → ECS agentul citește secretul cu execution role-ul și îl injectează ca env var.
5. De ce nu hardcodăm ARN-ul secretului? → AWS adaugă sufix de 6 caractere.
6. De ce `validate` trece, dar `plan` eșuează? → data sources se citesc la plan time.
7. Ce face `sts:AssumeRole`? → permite ECS să asume rolul.
8. De ce un singur NAT Gateway? → reducere de cost, cu prețul disponibilității.
9. De ce `backup_retention_period = 1`? → limitare free tier.
10. Ce fac când ALB dă 503? → verific ECS events → task reason → loguri → target health → curl.
11. Ce e `use_lockfile`? → locking nativ în S3, fără DynamoDB.
12. Cum opresc costurile? → `terraform destroy` + ștergerea manuală a secretelor.

---

## 10. Cum folosesc proiectul ca șablon la muncă

Toate valorile specifice TradeScheduler sunt acum în `variables.tf` (blocul `⚠️ APP-SPECIFIC`) și în `terraform.tfvars.example`. Fiecare fișier `.tf` are antet care trimite la variabile, iar scripturile au bloc `⚠️ REPLACE FOR A DIFFERENT APP`.

Pentru o aplicație nouă:
1. copiez `terraform.tfvars.example` → `terraform.tfvars` și înlocuiesc blocul APP-SPECIFIC;
2. setez `APP_DIR` și `REPO` pentru scriptul de build;
3. mă asigur că Dockerfile-ul expune același port și că aplicația răspunde cu 200 pe health path;
4. rulez secrets → ECR → build/push → plan/apply.

Dacă noua aplicație nu are o cheie de semnare, elimin cheia din 3 locuri (variabile, `ecs.tf`, `create-secrets.sh`) — exact cum e explicat în README.
