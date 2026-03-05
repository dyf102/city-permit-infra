# City Permit Infra TODO

## Tasks
- [x] Create Shared Infrastructure Design [Small/Low] (Completed: 2026-03-04)
- [x] Create Migration Plan [Small/Low] (Completed: 2026-03-04)
- [x] Create Deployment Plan [Small/Low] (Completed: 2026-03-04)
- [x] Scaffolding Shared Terraform Project [Small/Low] (Completed: 2026-03-04)
- [x] Phase 0: Environment Cleanup [Medium/Medium] (Completed: 2026-03-04)
- [x] Implement Shared Infrastructure Terraform Project [Small/Low] (Completed: 2026-03-04)
- [ ] Execute Migration Plan [Medium/Medium] (In-Progress: 2026-03-04)
    - [x] Phase 1: Infrastructure Preparation (Completed: 2026-03-04)
    - [ ] Phase 1.5: Pre-Migration DNS & Compatibility Verification (TTL 60s)
    - [ ] Phase 2: Reviewer Migration (Data Integrity row count checks)
    - [ ] Phase 3: Check Migration (GCP to AWS + DNS Switch)
    - [ ] Phase 4: Final Validation & GCP Decommissioning (Created: 2026-03-04)
- [ ] Stabilize Application Deployments [Medium/Medium] (In-Progress: 2026-03-04)
    - [x] CloudFront Path-Based Routing Configured
    - [x] Amplify Check App Build SUCCEEDED
    - [x] Backend Check Deploy SUCCEEDED
    - [x] Amplify Reviewer App Build SUCCEEDED
    - [x] Backend Reviewer Deploy (Completed: 2026-03-05 — SSM migration done, Lambda active, API Gateway verified)
    - [x] OIDC Trust Policy Fixed for toronto-permit-pulse repo
    - [x] CI Pipeline Fixed (Completed: 2026-03-05 — .eslintrc.json committed, stale deploy job removed)

## Completed
*(None yet)*

## Technical Debt / Backlog
- [ ] Test Stripe Payment integration in AWS production [Medium/Medium]
- [ ] Migrate `city-permit-check` from GCP to AWS [Medium/Medium]
- [ ] Consolidation of shared Python libraries between backends [Medium/Low]
