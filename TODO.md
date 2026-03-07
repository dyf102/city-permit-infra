# City Permit Infra TODO

## Tasks
- [x] Create Shared Infrastructure Design [Small/Low] (Completed: 2026-03-04)
- [x] Create Migration Plan [Small/Low] (Completed: 2026-03-04)
- [x] Create Deployment Plan [Small/Low] (Completed: 2026-03-04)
- [x] Scaffolding Shared Terraform Project [Small/Low] (Completed: 2026-03-04)
- [x] Phase 0: Environment Cleanup [Medium/Medium] (Completed: 2026-03-04)
- [x] Implement Shared Infrastructure Terraform Project [Small/Low] (Completed: 2026-03-04)
- [x] Renamed root branch from master to main for consistency [Small/Low] (Completed: 2026-03-05)
- [x] Execute Migration Plan [Medium/Medium] (Completed: 2026-03-05)
    - [x] Phase 1: Infrastructure Preparation (Completed: 2026-03-04)
    - [x] Phase 1.5: Pre-Migration DNS & Compatibility Verification (Completed: 2026-03-05)
    - [x] Phase 2: Reviewer Migration (Completed: 2026-03-05 — Schema applied, 12,626 rows migrated from Supabase, spatial queries verified)
    - [x] Phase 3: Check Migration (Completed: 2026-03-05 — Alembic schema applied, missing columns fixed, SQS+worker deployed, GOOGLE_API_KEY configured)
    - [x] Phase 4: Final Validation (Completed: 2026-03-05 — Both APIs healthy, RDS snapshots verified, session creation works)
- [x] Stabilize Application Deployments [Medium/Medium] (Completed: 2026-03-05)
    - [x] CloudFront Path-Based Routing Configured
    - [x] Amplify Check App Build SUCCEEDED
    - [x] Backend Check Deploy SUCCEEDED
    - [x] Amplify Reviewer App Build SUCCEEDED
    - [x] Backend Reviewer Deploy (Completed: 2026-03-05 — SSM migration done, Lambda active, API Gateway verified)
    - [x] OIDC Trust Policy Fixed for toronto-permit-pulse repo
    - [x] CI Pipeline Fixed (Completed: 2026-03-05 — .eslintrc.json committed, stale deploy job removed)
    - [x] CORS Fix for toronto subdomain (Completed: 2026-03-05)
- [x] Production E2E Smoke Tests for /check and /review (Completed: 2026-03-06)

## Completed
- [x] Shared Infrastructure Design
- [x] Migration & Deployment Plans
- [x] Environment Cleanup (Phase 0)
- [x] Shared Terraform Project Implementation
- [x] Infrastructure Preparation (Phase 1)
- [x] Pre-Migration DNS & Compatibility Verification (Phase 1.5)
- [x] Application Deployment Stabilization (CORS fixes, CI/CD, OIDC)
- [x] Reviewer Migration (Phase 2) — Supabase → Shared RDS
- [x] Check Migration (Phase 3) — Schema, SQS, worker, Gemini API key
- [x] Production E2E Smoke Tests (verified both subdomains/paths)

## Technical Debt / Backlog
- [x] Investigate 400 Bad Request on /api/v1/pipeline/stream (Completed: 2026-03-07 — Feature removed entirely to resolve infrastructure lockout)
- [ ] Test Stripe Payment integration in AWS production [Medium/Medium]
- [x] Migrate `city-permit-check` from GCP to AWS [Medium/Medium] (Completed: 2026-03-05)
- [ ] Consolidation of shared Python libraries between backends [Medium/Low]
