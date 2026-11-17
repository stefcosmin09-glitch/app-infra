# app-infra — TradeScheduler on AWS

Infrastructure as Code for deploying [TradeScheduler](https://github.com/stefcosmin09-glitch/scheduler-app) (a real Flask/Python job-management app) on AWS with Terraform.

This is a **learning project**, but built like a production skeleton: commented Terraform files, remote state, private networking, secrets management, and a repeatable release flow.

> 📘 **Document de învățare (în română):** [INVATARI.md](INVATARI.md) — explicații pe concepte, greșelile făcute și lecțiile lor, ordinea de deploy, depanare și întrebări de verificare pentru interviu.

> **Demo result (verified 2026-11-17):** `GET http://app-infra-staging-alb-2008841282.eu-central-1.elb.amazonaws.com/health` → `HTTP 200` `{"status":"ok"}`.
> The DNS name is temporary — query it again with `terraform output -raw alb_dns_name` after any redeploy.

---

## Architecture

```
Internet
   │
   ▼
┌─────────────────────────────────────────────────────────────┐
│ VPC 10.0.0.0/20 — 2 AZs (eu-central-1a, -1b)               │
│                                                             │
│  PUBLIC SUBNETS                    PRIVATE SUBNETS          │
│  ┌──────────────┐                  ┌──────────────────┐     │
│  │ ALB (:80)    │─────────────────►│ ECS Fargate task │     │
│  │ health:      │    target_type   │  app :8080       │     │
│  │ /health      │    = "ip"        │  no public IP    │     │
│  └──────────────┘                  └────────┬─────────┘     │
│  ┌──────────────┐                           │              │
│  │ NAT Gateway  │◄──────────────────────────┘              │
│  │ (1x, cost    │   outbound: ECR pull, Secrets Manager,   │
│  │  decision)   │   CloudWatch logs, pip, apt              │
│  └──────┬───────┘                                          │
└─────────┼───────────────────────────────┬───────────────────┘
          ▼                               ▼
    Internet / AWS APIs          ┌──────────────────────┐
                                 │ RDS PostgreSQL       │
                                 │ db.t3.micro, 20 GB   │
                                 │ Single-AZ, private   │
                                 └──────────────────────┘

Outside the VPC:
  ECR (image)  ·  Secrets Manager (DATABASE_URL, SECRET_KEY)  ·  CloudWatch (logs + metrics)
  S3 (Terraform state, native lockfile)  ·  AWS Budget ($5/month, deliberately low)
```

**Request flow:** `Internet → ALB → ECS task (private) → RDS (private)`.
**Egress flow:** `ECS task → NAT Gateway → ECR / Secrets Manager / CloudWatch`.

---

## Key design decisions

| Decision | Why |
|---|---|
| **Fargate, not EC2** | No servers to patch; each task gets its own ENI (`awsvpc`) and security group. |
| **Tasks in private subnets** | Only the ALB is reachable from the internet. `assign_public_ip = false`. |
| **`target_type = "ip"`** | Fargate has no EC2 host to register — ALB targets the task's IP directly. |
| **Single NAT Gateway** | ~$32/month instead of ~$64. Non-HA, explicitly accepted for a demo; documented as the first thing to change in production. |
| **RDS Single-AZ `db.t3.micro`** | Cheapest PostgreSQL that matches the app's production stack. `backup_retention_period = 1` because free-tier accounts reject longer retention. |
| **Secrets in Secrets Manager** | ECS agent injects them as env vars at startup via `valueFrom`; no password in code, GitHub, or Terraform state. |
| **`data "aws_secretsmanager_secret"`** | AWS appends a random 6-char suffix to secret ARNs. Looking up by name returns the real ARN; a hardcoded ARN silently fails at task startup. |
| **S3 backend with `use_lockfile = true`** | Native S3 locking — no separate DynamoDB table to maintain. |
| **`MUTABLE` ECR tags** | Simpler for a demo (`latest`). In production, prefer immutable tags plus a digest pinned in the task definition. |

---

## Repository layout

```
app-infra/
├── bootstrap/          # one-time S3 state bucket (local state, run once)
├── modules/vpc/        # VPC, subnets, IGW, NAT, route tables
├── main.tf             # provider + security groups (ALB / ECS / RDS)
├── backend.tf          # S3 remote state + native locking
├── variables.tf        # all inputs with defaults and descriptions
├── outputs.tf          # ALB DNS, ECR URI, cluster/service, DB endpoint
├── rds.tf              # PostgreSQL instance + subnet group
├── ecr.tf              # Docker image registry
├── iam.tf              # ECS execution role + task role + policies
├── alb.tf              # ALB, target group, HTTP listener
├── ecs.tf              # cluster, task definition, service, secret lookups
├── scripts/
│   ├── create-secrets.sh    # bootstrap Secrets Manager from gitignored tfvars
│   └── build-and-push.sh    # build image → login → tag → push to ECR
├── terraform.tfvars.example # safe example values
└── README.md
```

---

## ⚠️ Adapting this stack for a different application

This is a **complete application deploy**, not just empty infrastructure. Everything specific to TradeScheduler is marked with `REPLACE` in the code and centralized in `variables.tf` + `terraform.tfvars.example`. Change these values (in `terraform.tfvars`, not by editing `.tf` files):

| What to change | Terraform variable | TradeScheduler default | Script env var |
|---|---|---|---|
| ECR repo + container name | `app_name` | `tradescheduler` | `REPO` |
| Container port | `app_port` | `8080` | — (Dockerfile `EXPOSE`) |
| Health endpoint | `health_check_path` | `/health` | — |
| Expected health status | `health_check_matcher` | `200` | — |
| DB name / user / password / port | `db_name`, `db_username`, `db_password`, `db_port` | `tradescheduler`, `tsadmin`, …, `5432` | `DB_NAME`, `DB_USER`, `DB_PORT` |
| DB engine in connection string | — | `postgresql` | `DB_ENGINE` |
| Secret names | `secret_db_url_name`, `secret_key_name` | `db-url`, `secret-key` | `SECRET_DB_URL_NAME`, `SECRET_KEY_NAME` |
| Env var names the app reads | `env_database_url`, `env_secret_key` | `DATABASE_URL`, `SECRET_KEY` | — |
| Non-secret env vars | `app_environment` | `{ FLASK_ENV = "production" }` | — |
| App source directory | — | `../scheduler-app` | `APP_DIR` |
| Image tag | `container_image` | `latest` | `IMAGE_TAG` |

**Three contracts your new app must satisfy**, or ECS will never become healthy:

1. The Dockerfile must `EXPOSE` the same port as `app_port`.
2. It must answer `200` on `health_check_path` (or whatever you set as matcher).
3. It must read the DB URL / signing key from the env var names you configured.

**If your app has no signing key** (most non-Flask apps): remove `secret_key_name` / `env_secret_key` from `variables.tf`, delete the second `data "aws_secretsmanager_secret"` and its `secrets` entry in `ecs.tf`, and delete the second `create-secret` block in `scripts/create-secrets.sh`.

---

## Prerequisites

- AWS CLI configured with an IAM user (never root)
- Terraform >= 1.5
- Docker (for local image builds)
- WSL Ubuntu on Windows; run all Terraform/AWS/Docker commands there

---

## Deploy from scratch

```bash
# 0. One-time: create the remote state bucket
cd bootstrap
terraform init && terraform apply
cd ..

# 1. Local config (gitignored — never commit terraform.tfvars)
cp terraform.tfvars.example terraform.tfvars
# edit: real db_password

terraform init

# 2. Create the DB first (Secrets Manager needs its endpoint)
terraform apply -target=aws_db_instance.main -auto-approve

# 3. Create secrets BEFORE plan — ecs.tf reads them at plan time
bash scripts/create-secrets.sh

# 4. Create ECR, then build/push the image (avoids ECS restart loops)
terraform apply -target=aws_ecr_repository.tradescheduler -auto-approve
bash scripts/build-and-push.sh

# 5. Apply the rest
terraform plan
terraform apply
```

> **Ordering matters:** data sources in `ecs.tf` are resolved during `plan`. If the secrets do not exist yet, `terraform plan` fails with
> `reading Secrets Manager Secret (...): couldn't find resource`. That is intentional fail-fast behaviour, not a bug.

---

## Verify

```bash
ALB="$(terraform output -raw alb_dns_name)"
curl -i "http://${ALB}/health"
# HTTP/1.1 200 OK
# {"status":"ok"}

aws ecs describe-services \
  --cluster app-infra-staging-cluster \
  --services app-infra-staging-service \
  --query 'services[0].{running:runningCount,desired:desiredCount}'

aws logs tail /ecs/app-infra-staging --follow
```

---

## Cost estimate (staging, 24/7, ~monthly, eu-central-1)

| Resource | Est. cost |
|---|---|
| NAT Gateway (1×, ~$0.045/h + data) | ~$32 |
| RDS `db.t3.micro` Single-AZ, 20 GB gp3 | ~$15 |
| ALB (0.02 €/h + LCU) | ~$16–20 |
| ECS Fargate (0.25 vCPU / 0.5 GB, 1 task) | ~$9–10 |
| ECR, Secrets Manager, CloudWatch, S3 | ~$2–5 |
| **Total** | **~$75–85** |

An AWS Budget named **`Project`** is configured at **$5/month** — deliberately far below the real run rate so that *any* spend triggers an alert early. Raise it before running this as a real environment.

> ⚠️ **This stack costs money while it exists. Always run `terraform destroy` after the demo.**

---

## What I learned

- **IAM has two different consumers.** *Execution role* = what the ECS agent may do (pull image, read secrets, write logs). *Task role* = what the application code may do. Mixing them is a common mistake.
- **Trust policies use `sts:AssumeRole`.** A role without a trust policy exists but nobody can use it.
- **Managed vs inline policies.** AWS-managed (`AmazonECSTaskExecutionRolePolicy`) auto-updates; inline policies are for project-specific permissions such as `secretsmanager:GetSecretValue`.
- **AWS appends a 6-character suffix to secret ARNs.** Hardcoded ARNs break at runtime; `data "aws_secretsmanager_secret"` with `name` is the correct pattern.
- **Data sources are read at plan time**, so `validate` can pass while `plan` fails on missing external resources.
- **Fargate needs `awsvpc`** because there is no EC2 host — each task gets its own ENI.
- **Health checks are the contract between ALB and ECS.** `target_type = "ip"`, `/health` returning 200, and the ECS service registering targets are all part of the same chain.
- **Free-tier RDS has quirks:** backup retention > 1 day is rejected. AWS also *retires* minor engine versions over time — pin only the major version (`engine_version = "16"`) and let `auto_minor_version_upgrade` resolve the newest available minor. Hardcoding `16.9` worked during the first deploy and failed a few hours later.
- **`terraform destroy` can fail on ECR:** AWS refuses to delete a repository that still contains images (`RepositoryNotEmptyException`). For demos use `force_delete = true`; in production prune images with a lifecycle policy instead.
- **Debugging order matters:** ECS events → task `stoppedReason` → CloudWatch logs → target health → `curl` the ALB.

---

## What I'd do differently

1. **Two NAT Gateways** (one per AZ) for high availability — accept ~$32/month extra in a real environment.
2. **HTTPS with ACM + Route53**, HTTP→HTTPS redirect, and HSTS at the ALB.
3. **CI/CD with GitHub Actions or CodeBuild** (build → scan → push → `terraform apply`) instead of a manual `build-and-push.sh`.
4. **Immutable image tags** (commit SHA) and pin the digest in the task definition instead of using `latest`.
5. **Restrict the secrets IAM policy** to the two specific secret ARNs instead of `Resource = "*"`.
6. **Separate state per environment** and a reusable module for the whole stack, so `staging`/`prod` are just variable sets.
7. **RDS Multi-AZ + automated backups + deletion protection** for anything beyond a demo.
8. **ECS autoscaling** on CPU/memory, and `wait_for_steady_state = true` so deploys fail loudly.
9. **WAF, access logs to S3, and alarms** on 5xx rate / unhealthy targets.

---

## Cleanup

```bash
terraform destroy
```

This removes ECS, ALB, ECR, IAM roles, RDS, and the VPC. The state bucket in `bootstrap/` is intentionally kept (small and needed if you redeploy); delete it manually only when you are done with the project. Secrets Manager secrets also need manual deletion if you want zero leftovers:

```bash
aws secretsmanager delete-secret --secret-id app-infra/staging/db-url --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id app-infra/staging/secret-key --force-delete-without-recovery
```

---

## License

Private. All rights reserved.
