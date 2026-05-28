# Cloudforge Company Rollout Plan (Future State)

## Goal

Enable company-wide, self-service Cloudforge environments where engineers can request an environment via a web portal, while the platform team owns infrastructure lifecycle and governance.

## Confirmed Decisions

- Tenancy: one AWS account + shared VPC
- Ownership model: central platform team controls lifecycle
- Request channel: internal web portal
- Approval flow: no manual approval
- Quota policy: one active environment per engineer
- Access model: web-first (browser access), SSH disabled in MVP

## Recommended Architecture

### 1) Portal UI

- Authenticated internal web app for engineers
- Actions: request/create, suspend, resume, delete
- Views: environment state, endpoint URL, last activity, basic usage/cost

### 2) Platform API

- Validates identity and enforces one-active-env-per-user policy
- Receives lifecycle commands from portal
- Stores desired and current state in a metadata database
- Emits jobs to async provisioner worker

### 3) Provisioner Worker (Async)

- Executes infrastructure lifecycle operations
- Reuses Terraform modules from this repo under controlled automation
- Handles retries, idempotency, and failure recovery
- Reports progress/events back to API

### 4) State and Metadata Store

- User -> environment mapping
- Lifecycle status (pending/running/suspended/error/deleted)
- Resource identifiers (instance ID, volume ID, DNS URL)
- Audit trail of who requested what and when

### 5) AWS Environment Layer

- Per-user EC2 instance (Spot optional by policy)
- Persistent EBS data volume retained across suspend/resume
- Security groups locked to required ports only
- Strong resource tagging for ownership/cost tracking

### 6) Access Layer

- Web endpoint exposed through managed entry point (ALB and DNS)
- Portal deep-link to environment when ready
- SSH off by default in MVP

## How Current Repo Evolves

Current repo already includes:
- Terraform for EC2 + EBS + security groups
- Bootstrap scripts for Docker + NVIDIA runtime + data mount
- Container runtime with persistent data paths

Required evolution:
- Convert Terraform into reusable module(s) with user/env inputs
- Add automation wrapper so Terraform is never run by engineers
- Add platform API and worker orchestration service
- Add environment metadata database
- Add portal UI and identity integration

## Environment Lifecycle (Target)

1. Engineer submits request in portal.
2. API validates user quota and creates a provisioning job.
3. Worker runs Terraform apply for that user environment.
4. Worker runs host bootstrap and service startup steps.
5. API marks environment ready and returns endpoint URL.
6. Engineer can suspend/resume from portal at any time.
7. Data persists on EBS across stop/start and replacement.

## Security and Governance Guardrails

- Restrict ingress by default (avoid open 0.0.0.0/0 where possible)
- Enforce least-privilege IAM for provisioner components
- Centralize secrets management (no hardcoded keys in repo)
- Add mandatory resource tags (owner, cost-center, ttl, environment)
- Add audit logs for all lifecycle actions

## Cost Control Guardrails

- Enforce one active environment per user
- Default to suspend on inactivity timeout
- Optional Spot default with clear interruption behavior
- Budget alerts by team/cost-center
- Scheduled stop windows outside business hours (optional policy)

## Delivery Phases

### Phase 1: Platform MVP

- Internal portal with create/suspend/resume/delete
- API + worker + metadata DB
- Automated Terraform execution backend
- Web-first access only
- Basic quotas and status visibility

### Phase 2: Hardening

- Better observability (metrics, traces, alerting)
- Stronger policy engine for quotas/limits
- Enhanced failure recovery and runbooks
- Improved cost dashboards

### Phase 3: Enterprise Scale

- Multi-team policy segmentation
- Advanced lifecycle policy packs
- Optional SSH/JIT access flow if justified
- Regional expansion and DR strategy

## Open Questions for Next Iteration

- Identity provider and SSO integration details
- Portal tech stack and hosting location
- Metadata DB choice and backup requirements
- Inactivity timeout policy by team type
- Naming conventions for environment URLs and resources

## Success Criteria

- Engineers do not run Terraform directly
- New environment request is fully self-service through portal
- Suspend/resume works reliably with persistent user data
- Quota and governance policies are enforced automatically
- Platform team retains operational control and auditability

