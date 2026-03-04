# Deployment Plan: Shared City Permit Infrastructure

## 1. CI/CD Architecture
We will use **GitHub Actions** as the primary orchestration engine for both applications. 

- **Frontends:** Managed by **AWS Amplify** (Auto-deployment on `git push` to `main`).
- **Backends:** Built as **Docker Container Images**, pushed to **Amazon ECR**, and deployed to **AWS Lambda**.

## 2. Environment Management
- All sensitive keys (Gemini, Stripe, DB Password) are stored in **AWS SSM Parameter Store** (Standard Tier - $0/mo).
- Build-time environment variables (e.g., `NEXT_PUBLIC_API_URL`) are managed via Amplify App settings.

## 3. Application 1: `city-permit-reviewer`

### Backend (Lambda)
- **Workflow:** `.github/workflows/deploy-reviewer-backend.yml`
- **Steps:**
  1. Run Python tests (pytest).
  2. Build Docker image (`linux/arm64` for cost/performance).
  3. Push to ECR repository: `permitpulse-prod-backend`.
  4. Update Lambda function code.
  5. Run database migrations via temporary Lambda invocation or `alembic upgrade head`.

### Frontend (Amplify)
- **Trigger:** Automatic webhook on merge to `main`.
- **Build Spec:** Defined in `amplify.yml`.
- **Domain:** `reviewer.permitpulse.ca`.

## 4. Application 2: `city-permit-check`

### Backend (Lambda)
- **Workflow:** `.github/workflows/deploy-check-backend.yml`
- **Steps:**
  1. Run Python tests and RAG pipeline validations.
  2. Build Docker image (`linux/arm64`).
  3. Push to ECR repository: `permit-pulse-check-backend`.
  4. Update API and Worker Lambda functions.
  5. Apply Alembic migrations.

### Frontend (Amplify)
- **Trigger:** Automatic webhook on merge to `main`.
- **Build Spec:** Custom Next.js build command in Amplify console.
- **Domain:** `check.permitpulse.ca` or `permit-pulse.ca`.

## 5. Deployment Safeguards
1. **Manual Approval:** Optional GitHub Environment protection for `prod` deployments.
2. **Smoke Tests:** Post-deployment script (`scripts/smoke_test.py`) to verify `/health` endpoints.
3. **Rollback Strategy:** 
   - **Backend:** Re-tag previous ECR image as `latest` and update Lambda.
   - **Frontend:** Use Amplify's "Restore previous version" feature.

## 6. Implementation Steps
1. Create ECR repositories for both apps.
2. Set up GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
3. Create the GitHub Action YAML files.
4. Verify IAM permissions for the GitHub Action user (least privilege).
