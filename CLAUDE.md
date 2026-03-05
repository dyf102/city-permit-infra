# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shared AWS infrastructure (Terraform) for two city permit web applications:
- **city-permit-reviewer** — permit risk assessment tool (Next.js + FastAPI)
- **city-permit-check** — permit compliance checker (Next.js + FastAPI)

Both apps are git submodules with their own repos and CLAUDE.md files. This repo manages the shared infra they run on.

## Terraform Commands

All Terraform operations run from `terraform/environments/prod/`:

```bash
cd terraform/environments/prod

# Initialize (required after cloning or adding providers)
terraform init

# Preview changes
terraform plan -var-file=terraform.tfvars

# Apply changes
terraform apply -var-file=terraform.tfvars

# Check current state
terraform state list
terraform state show <resource>

# Format all .tf files
terraform fmt -recursive ../../
```

The bootstrap stack (`terraform/bootstrap/main.tf`) is a one-time setup for the S3 state bucket and DynamoDB lock table — do not re-apply it.

## Architecture

### Infrastructure Layout

```
terraform/
├── bootstrap/          # One-time: S3 state bucket + DynamoDB locks
├── environments/prod/  # Root module — wires everything together
│   ├── main.tf         # Module instantiation (networking, database, 2x webapp, bootstrap_lambda, monitoring)
│   ├── iam_github.tf   # GitHub OIDC provider + deploy role
│   ├── acm.tf          # ACM cert (us-east-1, for CloudFront)
│   ├── cloudfront.tf   # Path-based routing: /review* → reviewer, /check* → check
│   └── dns.tf          # Cloudflare DNS records
├── modules/
│   ├── networking/     # VPC, subnets, NAT instance, SSM endpoint
│   ├── database/       # Shared RDS PostgreSQL 16 (PostGIS + pgvector)
│   ├── webapp/         # Reusable: ECR + Lambda + API Gateway + Amplify + S3
│   ├── bootstrap_lambda/  # One-time DB init (creates databases + extensions)
│   └── monitoring/     # CloudWatch dashboard + SNS billing alarm
└── scripts/
    └── bootstrap_db.py # DB initialization script
```

### Key Design Decisions

- **Single RDS instance** (`db.t4g.micro`) with two databases (`reviewer_prod`, `check_prod`) — cost optimization
- **NAT instance** (`t4g.nano`, ~$5/mo) instead of NAT Gateway (~$28/mo)
- **SSM Parameter Store** (free) for secrets, not Secrets Manager ($0.40/secret/mo)
- **Lambda on arm64** with container images from ECR, 512MB memory, 28s timeout
- **Amplify** hosts frontends (static Next.js export), auto-deploys on push to `main`
- **CloudFront** does path-based routing (`/review*` → reviewer app, `/check*` → check app)
- **GitHub OIDC** — no long-lived AWS credentials; CI uses `github-actions-deploy-role`

### AWS Region & Account

- Region: `ca-central-1` (Toronto), except ACM certs and billing alarms in `us-east-1`
- Account: `110428898775`
- State backend: S3 bucket `city-permit-tfstate-110428898775` with DynamoDB lock table `city-permit-tf-locks`

### Providers

- `hashicorp/aws` ~> 5.0 (default: ca-central-1, alias: us-east-1)
- `cloudflare/cloudflare` ~> 4.0
- `hashicorp/archive`

### Domain & Routing

- Domain: `permitpulse.ca` (DNS on Cloudflare)
- CloudFront alias: `toronto.permitpulse.ca`
- Amplify origins route through CloudFront with path-based cache behaviors

### CI/CD

Backend deploys live in each submodule's `.github/workflows/`:
- Build Docker image (arm64) → push to ECR → update Lambda function code
- Auth via GitHub OIDC assuming `github-actions-deploy-role`
- Frontend auto-deploys via Amplify on push to `main`

## Sensitive Variables

Required in `terraform.tfvars` (never committed):
- `db_password`, `github_access_token`, `gemini_api_key`, `stripe_secret_key`, `secret_key` (JWT), `cloudflare_api_token`, `cloudflare_zone_id`

## Webapp Module Reuse

The `webapp` module is instantiated twice (reviewer + check). When modifying it, changes affect both apps. Each instance gets its own ECR repo, Lambda, API Gateway, Amplify app, and S3 bucket, parameterized by `app_name`.
