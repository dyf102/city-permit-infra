# Migration Plan: Shared City Permit Infrastructure

## Phase 0: Environment Cleanup (Pre-requisite)
1. **Teardown Existing AWS Resources:**
   - Manually delete existing `demo` environment resources (RDS, Lambda, S3, ECR, VPC, Amplify).
   - Verify all active costs are stopped.
   - Clean up any orphan IAM roles and CloudWatch Log Groups.

## Phase 1: Infrastructure Preparation (The "Lander")
1. **Terraform Init:** Create the root `terraform/` directory and define the `ca-central-1` provider.
2. **Networking:** Deploy the VPC and the **t4g.nano NAT Instance**. Verify private subnets have outbound internet access.
3. **Database:** 
   - Deploy the Shared RDS instance.
   - Run a "Bootstrap Lambda" or a local script (via VPN/Bastion) to run:
     ```sql
     CREATE DATABASE reviewer_prod;
     CREATE DATABASE check_prod;
     CREATE EXTENSION IF NOT EXISTS postgis;
     CREATE EXTENSION IF NOT EXISTS vector;
     ```
4. **Secrets:** Populate AWS SSM Parameter Store with all required keys for both apps.

## Phase 1.5: Pre-Migration Readiness (✅ Completed: 2026-03-04)
1. **DNS Preparation:**
   - Lower TTL to **60 seconds** for `toronto.permit-pulse.ca`.
   - Verified active grey-cloud routing.
2. **Extension Version Check:**
   - Source Supabase: PostGIS 3.x, Vector 0.x.
   - Destination RDS: PostGIS 3.4.2, Vector 0.7.0.
   - Compatibility verified.

## Phase 2: `city-permit-reviewer` (Surgical Migration)
*Goal: Move from standalone RDS to Shared RDS with zero downtime.*
1. **Maintenance Mode:** Briefly enable a "Maintenance" flag on the frontend.
2. **Data Sync:**
   - `pg_dump` from old RDS.
   - `pg_restore` into `reviewer_prod` on Shared RDS.
3. **Data Integrity Verification (CRITICAL):**
   - **Step A:** Run `SELECT COUNT(*) FROM <table_name>;` on all critical tables (applications, permits, etc.) in both source and destination.
   - **Step B:** Diff row counts. Must match 100%.
   - **Step C:** Spot check 5-10 records: `SELECT * FROM applications ORDER BY created_at DESC LIMIT 5;`
4. **Redeploy Backend:** Update Terraform to point the `reviewer-api` Lambda to the new VPC and the `reviewer_prod` database.
5. **Smoke Test:** Verify API endpoints and PostGIS spatial queries.
6. **Cleanup:** Delete the old standalone RDS instance and its subnet groups.

## Phase 3: `city-permit-check` (GCP to AWS Migration)
*Goal: Transition from Cloud Run/GCS to Lambda/S3.*
1. **Storage Sync:** Use `gsutil` and `aws s3 sync` to move permit uploads from GCP Bucket to AWS S3.
2. **Backend Adaptation:**
   - Update `city-permit-check/backend/Dockerfile` for ECR/Lambda compatibility.
   - Update database connection logic to use the `check_prod` RDS endpoint.
3. **Frontend Deployment:**
   - Connect the `city-permit-check` GitHub repo to AWS Amplify.
   - Configure `NEXT_PUBLIC_API_URL` to point to the new AWS API Gateway.
4. **DNS Cutover:**
   - Update Route53/Cloudflare to point the domain to the new Amplify distribution.
   - Monitor traffic via CloudWatch metrics.
5. **Validation:** Run the RAG pipeline tests to ensure `pgvector` is functioning correctly on the new RDS.
6. **TTL Restoration:** Once stable (approx. 2-4h post-cutover), raise DNS TTL back to original values (e.g., 3600s).

## Phase 4: Final Validation & Decommissioning
1. **Load/Smoke Testing:** 
   - Perform a "Live Fire" smoke test against both apps in the production environment.
   - Verify critical user flows: Login, Address Search, PDF Generation, and RAG processing.
2. **RDS Backup Verification:**
   - **Mandatory:** Log into AWS Console or use CLI to confirm that at least one **automated snapshot** has been successfully created for the shared RDS instance.
   - Do not decommission old data until this is verified.
3. **GCP Decommissioning:**
   - **Decommission Date:** T+7 days after successful AWS migration.
   - **Approval:** Requires formal sign-off from Project Owner (Founder).
   - **Steps:**
     - Stop Cloud Run services.
     - Delete GCS Buckets (ensure AWS sync is verified).
     - Archive GCP project or disable billing.
4. **Billing Check:** Verify no unexpected costs in `us-east-1` (billing) or `ca-central-1` (usage).
5. **Monitoring:** Confirm the Unified CloudWatch Dashboard is receiving metrics from both apps.
