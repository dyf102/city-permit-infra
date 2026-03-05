# SQS Async Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Resolve API Gateway 29-second timeout for long-running permit analysis by offloading processing to SQS and a background Lambda worker.

**Architecture:** 
1. The frontend-facing API enqueues a task to SQS and returns a session ID immediately.
2. A new "Worker" Lambda is triggered by SQS to perform the heavy lifting (parsing, LLM calls).
3. The frontend polls a status endpoint (or uses the existing polling logic) to get results from the RDS database once complete.

**Tech Stack:** AWS SQS, AWS Lambda, Terraform, Python (FastAPI).

---

### Task 1: Update Terraform Webapp Module to include SQS

**Files:**
- Modify: `terraform/modules/webapp/main.tf`
- Modify: `terraform/modules/webapp/variables.tf`

**Step 1: Define SQS Queue and IAM permissions**
Add `aws_sqs_queue` and update `aws_iam_role_policy` to allow `sqs:SendMessage` for the API Lambda.

**Step 2: Pass SQS_QUEUE_URL to API Lambda**
Update `aws_lambda_function.app` environment variables.

**Step 3: Commit**
```bash
git add terraform/modules/webapp/
git commit -m "infra: add SQS queue and permissions to webapp module"
```

### Task 2: Implement Background Worker Lambda in Terraform

**Files:**
- Modify: `terraform/modules/webapp/main.tf`

**Step 1: Add Worker Lambda Resource**
Create `aws_lambda_function.worker` using the same ECR image but a different handler/entrypoint if needed (or same image, different command).
Set `timeout` to 300s (5 minutes) for the worker.

**Step 2: Add SQS Trigger**
Create `aws_lambda_event_source_mapping` to connect SQS to the Worker Lambda.

**Step 3: Commit**
```bash
git add terraform/modules/webapp/main.tf
git commit -m "infra: add background worker lambda and SQS trigger"
```

### Task 3: Update city-permit-check Backend to use SQS

**Files:**
- Modify: `city-permit-check/backend/app/services/sqs_service.py`
- Modify: `city-permit-check/backend/app/api/pipeline.py`

**Step 1: Implement SQS Enqueue Logic**
Ensure `sqs_service.py` correctly uses `boto3` to send messages.

**Step 2: Enable Async Path in Pipeline**
Verify `pipeline.py` correctly detects `SQS_QUEUE_URL` and routes to the async path.

**Step 3: Commit**
```bash
git add city-permit-check/backend/app/
git commit -m "feat: enable async SQS path in check backend"
```

### Task 4: Implement Worker Handler

**Files:**
- Create: `city-permit-check/backend/worker_handler.py`
- Modify: `city-permit-check/backend/Dockerfile`

**Step 1: Create Worker Entrypoint**
Write a handler that processes SQS events, calls the `OrchestratorService`, and updates the RDS database.

**Step 2: Update Dockerfile (if needed)**
Ensure the image can be started as a worker.

**Step 3: Commit**
```bash
git add city-permit-check/backend/
git commit -m "feat: implement background worker handler"
```

### Task 5: Deploy and Verify

**Step 1: Run Terraform Apply**
`cd terraform/environments/prod && terraform apply -auto-approve`

**Step 2: Manual Smoke Test**
Upload a document at `https://toronto.permit-pulse.ca/check` and verify it no longer times out, instead moving to "Analysis enqueued" state.

**Step 3: Commit**
```bash
git add TODO.md
git commit -m "docs: mark SQS migration complete"
```
