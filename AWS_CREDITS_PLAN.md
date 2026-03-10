# AWS Credits Application Plan

This document outlines the requirements and strategy for applying for AWS Credits for the City Permit Infrastructure projects (`city-permit-check` and `city-permit-reviewer`).

## 1. Project Overview
Unified infrastructure for Toronto construction permit analysis, regulatory compliance, and consumer protection.
- **city-permit-check**: AI-driven regulatory validator (RAG-based) for B2B permit analysis.
- **city-permit-reviewer**: Geospatial analysis and math engine for zoning compliance.
- **GTAConstructGuard (Planned Expansion)**: Consumer protection platform for GTA homeowners, providing milestone documentation and contract auditing (currently in staging/development).

## 2. Infrastructure Footprint (Justification for Credits)
- **Compute**: Multiple Lambda functions (API, Workers, ETL) with ECR-based deployments across the unified platform.
- **Dedicated ETL Pipeline**: A standalone `city-zoning-etl` service for ingesting high-volume municipal data (Toronto Open Data, CoA decisions, CBO bulletins).
- **Database (The Municipal Moat)**: Shared RDS (PostgreSQL with PostGIS and pgvector). The transition from "hardcoded 350sqm stubs" to real-time analysis of **500k+ parcels** (parcel fabric) requires high-performance spatial indexing and significant IOPS.
- **Storage & Evidence Locker**: S3 for document persistence, drawing markups, and geotagged milestone evidence.
- **AI/ML & Document Intelligence**: 
    - **Amazon Textract**: For "Messy-Input Ingestion" (OCR of handwritten tradesman quotes and legacy CoA decisions).
    - **High-Compute RAG Pipeline**: Orchestrating complex regulatory reasoning using Lambda, SQS, and semantic search (pgvector).
- **Security & PII Protection**: **Amazon Macie** and KMS encryption to identify and protect sensitive homeowner data (geotags, PII in contracts).
- **Frontend**: AWS Amplify hosting two production-ready React/Next.js applications, with capacity for a third (GTAConstructGuard) as the platform scales.
- **Networking**: Unified VPC with NAT optimization and CloudFront for global delivery and security.

## 3. High-Priority "Credit-Ready" Tasks
To qualify for significant credits (e.g., AWS Activate), we must demonstrate architectural best practices and production-ready workloads.

### A. Architectural Optimization (Cost & Scalability)
- [ ] Implement multi-AZ RDS for high availability and evaluate **Amazon Aurora** for complex geospatial scaling (500k+ parcel joins).
- [ ] Optimize Lambda concurrency and memory settings for heavy ETL and Textract-driven ingestion jobs.
- [ ] Transition NAT Gateway to VPC Endpoints (S3, ECR, RDS, Textract) to **reduce** high data transfer costs for frequent municipal syncs and internal OCR processing, while maintaining NAT egress for external data sources (CKAN/Open Data).

### B. Security & Compliance
- [ ] Enable AWS GuardDuty, Security Hub, and **Amazon Macie** for PII detection.
- [ ] Implement KMS encryption for all S3 buckets and RDS instances.
- [ ] Set up AWS WAF for CloudFront and API Gateway to mitigate DDoS on public endpoints.

### C. Observability & Cost Management
- [ ] Configure AWS Budgets to track "Geospatial Data Expansion" and "Document Intelligence (Textract)" costs.
- [ ] Enhance CloudWatch Dashboards for unified monitoring across both apps, the new ETL pipeline, and OCR workers.
- [ ] Implement Tagging Strategy (Cost Center, Project, Environment, Data-Source) across all Terraform modules.

## 4. Application Strategy
1. **Case Study**: Document how the platform uses AWS (specifically PostGIS and serverless) to solve municipal complexity at scale (e.g., replacing hardcoded defaults with real-time parcel fabric analysis).
2. **Architecture Diagram**: Generate a professional diagram showing the unified VPC, shared RDS, and the dedicated `city-zoning-etl` ECR repository.
3. **Cost Projection**: Use AWS Pricing Calculator to project 12-month burn, factoring in the growth from 9+ new data sources.
