# Shared Infrastructure Design for City Permit Apps

## 1. Overview
This design provides a unified, budget-conscious AWS infrastructure for two related web applications: `city-permit-reviewer` and `city-permit-check`. The goal is to minimize costs by leveraging the AWS Free Tier and shared resources while maintaining security and ease of maintenance for a single-person startup.

## 2. Architecture Diagram (Conceptual)
```text
[ Users ]
    |
    v
[ AWS Amplify (Frontends) ] ----> [ API Gateway (+ Stage) ] ----> [ AWS Lambda (Backends) ]
                                                                         |
                                           +-----------------------------+
                                           |                             |
                                           v                             v
                                  [ Shared RDS PostgreSQL ]       [ S3 Assets ]
                                  (PostGIS + pgvector)
                                  (accessed via app users,
                                   not superuser)

[ GitHub Actions (OIDC) ] ----> [ ECR ] ----> [ Lambda update-function-code ]

[ SSM Parameter Store ] <---- [ Lambda (fetches secrets at startup) ]

[ CloudWatch (ca-central-1) ] ---- Lambda Errors, Duration, Throttles
                                   API Gateway 4XX/5XX
                                   RDS CPU, Connections, FreeStorage

[ CloudWatch Billing Alarm (us-east-1) ] ----> [ SNS Topic ] ----> [ Email ]
```

## 3. Networking (VPC)
- **Region:** `ca-central-1` (Toronto) for low latency.
- **VPC:** Single VPC (`10.0.0.0/16`) with 2 public and 2 private subnets across two AZs.
- **NAT Gateway Mitigation:**
    - Use a single **NAT Instance (t4g.nano, Amazon Linux 2 ARM64)** in a public subnet to provide internet access to private Lambdas.
    - Cost Saving: ~$28/month vs. a managed NAT Gateway.
    - **ip_forward and iptables rules must be written to persist across reboots** (via `/etc/sysctl.d/` and `iptables-services`). A reboot of the NAT instance without persistence silently kills all Lambda outbound traffic.
    - The NAT instance is a **SPOF** — acceptable for a startup, but documented.
- **Security Groups:**
    - `nat_sg`: Allows ingress from VPC CIDR (`10.0.0.0/16`) on all ports; egress to `0.0.0.0/0`.
    - `lambda_sg`: Egress only — to RDS on port 5432 and to `0.0.0.0/0` via NAT.
    - `db_sg`: Allows inbound 5432 **only from `lambda_sg` security group ID** (not VPC CIDR).

## 4. Database (RDS)
- **Instance Type:** `db.t4g.micro` (PostgreSQL 16, ARM64). Free-tier eligible.
- **Free Tier:** 750 hours/month (free for 1st year).
- **Configuration:**
    - Single instance, no Multi-AZ (cost saving; acceptable for startup).
    - **Databases:** Separate databases (`reviewer_prod`, `check_prod`) on the same instance.
    - **Extensions:** `postgis` and `vector` enabled via bootstrap script (one-time manual step post-provision).
    - **Application Users:** Apps connect as least-privilege users (`reviewer_user`, `check_user`), not the `postgres` superuser. Created during bootstrap.
- **Storage:** 20GB GP3, **encrypted at rest** (`storage_encrypted = true`).
- **Backups:** `backup_retention_period = 7` days. `skip_final_snapshot = false` for prod.
- **Connection note:** Lambda + RDS can exhaust `max_connections` under concurrent load. Monitor `DatabaseConnections` metric; add RDS Proxy if connections become a bottleneck.

## 5. Compute (Serverless Backends)
- **Service:** AWS Lambda (Container Images via ECR, `arm64` architecture).
- **Rationale:** Pay-per-use; zero cost when idle.
- **Separation:**
    - `city-permit-reviewer-api-prod`
    - `city-permit-check-api-prod`
- **Timeout:** 28 seconds (API Gateway REST has a hard 29s integration timeout; Lambda must be lower to avoid orphaned invocations).
- **Memory:** 512MB (tune based on profiling).
- **Secrets:** Lambda fetches DB credentials and API keys from SSM Parameter Store at startup. The `DATABASE_URL` is **not** stored in Lambda environment variables.
- **ECR:** Immutable image tags (git SHA) preferred for auditability; `latest` used as a pointer by CI/CD. Lifecycle policy retains last 10 tagged images and auto-expires untagged images after 1 day.
- **API Gateway:** Two REST APIs, one per app. Each requires a `deployment` and `stage` resource to be invokable. Custom domain mapping: `api.reviewer.permitpulse.ca`, `api.check.permitpulse.ca`.
- **CloudWatch Logs:** Log group per Lambda with 30-day retention (prevents unbounded storage cost).

## 6. Frontend (Amplify)
- **Service:** AWS Amplify (Next.js SSR support).
- **Deployment:** Integrated with GitHub for automated CI/CD on push to `main`.
- **Custom Domains:** `reviewer.permitpulse.ca`, `check.permitpulse.ca`.
- **Build-time env vars** (e.g., `NEXT_PUBLIC_API_URL`) managed via Amplify App settings — not SSM.

## 7. Storage (S3)
- **Bucket 1:** `city-permit-reviewer-assets-prod-{account_id}` (PDF reports, document storage).
- **Bucket 2:** `city-permit-check-assets-prod-{account_id}` (Permit uploads, processing results).
- **Hardening (all buckets):**
    - Public access blocked (`aws_s3_bucket_public_access_block`).
    - Server-side encryption enabled (SSE-S3).
    - Versioning enabled (recovery from accidental deletes).
- **Lifecycle Policy:** Auto-delete unversioned temp objects after 30 days.

## 8. Secrets & Config
- **AWS SSM Parameter Store (Standard Tier):** Stores all secrets as `SecureString` (KMS-encrypted with AWS-managed key).
    - `/city-permit/prod/db-password`
    - `/city-permit/prod/gemini-api-key`
    - `/city-permit/prod/stripe-secret-key`
    - `/city-permit/prod/jwt-secret-key`
- **Cost:** $0.00 (vs. Secrets Manager at $0.40/secret/month).
- **Access:** Lambda IAM role grants `ssm:GetParameter` on `/city-permit/${environment}/*` only. Secrets are fetched at Lambda cold start, not injected as env vars.

## 9. CI/CD (GitHub Actions)
- **Authentication:** GitHub Actions uses **OIDC federation** to assume an IAM role — no long-lived `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` stored in GitHub Secrets.
- **Backend workflow:** Run tests → build `linux/arm64` Docker image → push to ECR (tagged with git SHA) → `update-function-code` on Lambda → run smoke tests.
- **Frontend:** AWS Amplify handles frontend deploys automatically on push to `main`.
- **Rollback:** Re-invoke `update-function-code` with the previous git SHA tag from ECR.

## 10. Monitoring & Observability
- **CloudWatch Dashboard (`ca-central-1`):** "CityPermit-Startup-Health" showing:
    - Lambda Errors, Duration (p99), Throttles — per function.
    - API Gateway 4XX/5XX error rates — per API.
    - RDS CPU, `DatabaseConnections`, `FreeStorageSpace`.
- **Billing Alarm:** Deployed in **`us-east-1`** (required — billing metrics are only published there).
    - $10 threshold → SNS alert.
    - SNS topic has an email subscription for immediate notification.
- **Log Retention:** All Lambda CloudWatch Log Groups set to 30 days.

## 11. Terraform State
- **Remote Backend:** S3 bucket + DynamoDB table for state locking.
    - State bucket: `city-permit-tfstate-{account_id}` (versioned, encrypted, private).
    - Lock table: `city-permit-tf-locks`.
- **Rationale:** Sensitive values (db_password, API keys) land in `terraform.tfstate` in plaintext. Remote state with encryption and access control prevents accidental local exposure or git commits.

## 12. Implementation Plan (Terraform)
1. **Bootstrap (one-time, manual):** Create S3 state bucket + DynamoDB lock table.
2. **Module: Networking** — VPC, subnets, NAT instance (with SG + persistent iptables).
3. **Module: Database** — RDS instance, subnet group, security group.
4. **Module: App (REUSABLE)** — ECR, Lambda, API Gateway (with deployment + stage), IAM roles, S3 bucket (with hardening), CloudWatch log group.
5. **Module: Monitoring** — CloudWatch dashboard, SNS topic + email subscription, billing alarm (provider alias `us-east-1`).
6. **Environment: Prod** — Instantiates all modules for both apps. SSM parameters managed here.
7. **Bootstrap Script (post-Terraform):** Connect to RDS via bastion/Lambda to:
    - `CREATE DATABASE reviewer_prod; CREATE DATABASE check_prod;`
    - `CREATE EXTENSION postgis; CREATE EXTENSION vector;`
    - Create least-privilege app users.

---
*Design Proposed: 2026-03-04*
*Revised: 2026-03-04 (post staff SDE review)*
*Estimated Monthly Cost (After Free Tier): ~$25 - $40 (depending on traffic)*
*Estimated Monthly Cost (During Free Tier): ~$5 - $10 (mostly NAT Instance & ECR storage)*
