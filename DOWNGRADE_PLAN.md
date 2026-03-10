# Infrastructure Downgrade Plan (Fallback Strategy)

This document outlines the steps to aggressively reduce AWS infrastructure costs if the startup fails to secure AWS Activate credits or if the runway becomes critically short. The goal is to preserve core functionality while minimizing the monthly burn rate.

## 1. Trigger Conditions
- AWS Activate Credit application denied or delayed significantly.
- Monthly AWS burn rate exceeds available operational cash flow without credit coverage.

## 2. Immediate Cost-Cutting Actions (Phase 1)
These actions have minimal impact on the user experience but significantly reduce backend costs.

- [ ] **Database (RDS)**: Revert any Multi-AZ or Aurora upgrades back to a Single-AZ `db.t4g.micro` instance. If necessary, consider stopping the RDS instance during non-business hours (requires automated start/stop scripts).
- [ ] **ETL Pipeline**: Reduce the frequency of the `city-zoning-etl` data syncs (e.g., from daily/weekly to monthly) to save on Lambda compute and NAT Gateway data transfer costs.
- [ ] **Networking**: If VPC Endpoints are too expensive (~$7/month per endpoint), remove them and rely entirely on the low-cost `t4g.nano` NAT instance.

## 3. Structural Downgrade Actions (Phase 2)
If Phase 1 is insufficient, more aggressive architectural changes will be required.

- [ ] **Consolidate Compute**: Combine the separate `city-permit-check` and `city-permit-reviewer` Lambda functions into a single monolithic deployment, if feasible, to reduce idle compute waste and simplify ECR storage.
- [ ] **Networking**: Remove NAT Gateways/Instances entirely. If Lambda functions require internet access, evaluate moving them to public subnets (accepting the security trade-off) or routing all external requests through an API Gateway proxy.
- [ ] **Caching**: Eliminate any Redis/Upstash caching layers and rely solely on cheaper database-level caching or aggressive frontend caching.
- [ ] **AI/ML**: Disable or throttle advanced Gemini/Bedrock integrations. Fall back to simplified heuristics or cached responses where possible.

## 4. Drastic Measures (Phase 3)
If the project must be placed into "hibernation mode":

- [ ] **Database Export**: Export PostGIS data to static GeoJSON files and host them on S3 for the frontend to query directly (drastically limits functionality but eliminates database costs).
- [ ] **Static Fallback**: Convert dynamic features to static placeholders and host purely on Vercel/Cloudflare Pages.
