# app-infra — TradeScheduler on AWS

Infrastructure as Code for deploying [TradeScheduler](https://github.com/stefcosmin09-glitch/scheduler-app) (Flask/Python job-management app) on AWS using Terraform.

## Architecture

```
Internet
   │
   ▼
[ALB] (public subnets, 2 AZs)
   │
   ▼
[ECS Fargate] (private subnets) ──► [RDS PostgreSQL] (private subnet)
   │
   ├──► [ECR] (Docker images)
   ├──► [Secrets Manager] (DB creds, API keys)
   └──► [CloudWatch] (logs, metrics, alarms)
```

## What's here

- `bootstrap/` — creates S3 bucket + DynamoDB table for Terraform remote state (run once, local state).
- `modules/vpc/` — VPC, subnets (public/private, 2 AZs), IGW, NAT Gateway, route tables.
- Root module — security groups (ALB, ECS, RDS), and (coming) ECS/RDS/ALB/ECR resources.
- `.github/workflows/` — (coming) CI/CD: build image → push ECR → deploy.

## Cost estimate (staging, ~monthly)

| Resource | Est. cost |
|---|---|
| NAT Gateway (1x) | ~$32 |
| RDS db.t3.micro (Single-AZ) | ~$15 |
| ECS Fargate (0.25 vCPU / 0.5 GB) | ~$10 |
| ALB | ~$16 |
| ECR / Secrets / CloudWatch | ~$2 |
| **Total** | **~$75** |

> ⚠️ Always run `terraform destroy` after a demo. Set an AWS Budget alert at $10.

## Prerequisites

- AWS CLI configured (`aws configure`) with an IAM user (not root).
- Terraform >= 1.5
- Docker (for building images)

## Usage

```bash
# 1. Bootstrap remote state (once)
cd bootstrap
terraform init
terraform apply
cd ..

# 2. Deploy infrastructure
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with real values
terraform init
terraform plan
terraform apply

# 3. Tear down
terraform destroy
```

## What I learned

- _To be filled as I build this._

## What I'd do differently

- _To be filled._

## License

Private. All rights reserved.