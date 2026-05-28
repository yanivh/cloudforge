# Cloudforge Context

## Glossary

### SSH Access
- Canonical meaning: operator-only bootstrap access.
- Scope: used by platform operators to provision and initialize environments.
- Non-goal: not an end-user access path for daily development workflows.
- Policy: restricted to known operator IP(s), never world-open.
- Allowed source model: small explicit CIDR allowlist.

### Web Access Path
- Canonical meaning: the primary end-user access path to Cloudforge environments.
- Reachability: internet-reachable (no VPN requirement).
- Authentication: no mandatory gate in MVP (intentional temporary risk acceptance).
- Planned evolution: add simple in-app login after MVP.

### Ingress Policy
- Canonical meaning: SSH and web ingress are governed independently.
- SSH ingress: controlled by `ssh_allowed_cidrs`.
- Web ingress: controlled by `web_allowed_cidrs`.
- Operations rule: real CIDR values are managed outside git in private runtime tfvars; repo keeps examples/placeholders only.

### Data Persistence
- Canonical meaning: `/data` on EBS is durable across instance stop/start and replacement events.
- Invariant: automatic reattachment is required; data loss is not acceptable in MVP.

### Spot Capacity Behavior
- Canonical meaning: Spot interruption may cause temporary environment unavailability.
- MVP policy: prefer auto-recovery on Spot capacity return over immediate on-demand fallback.

### Service Recovery
- Canonical meaning: after host restart/recovery, Cloudforge services return without manual operator intervention.
- Invariant: automatic service recovery is required in MVP.
- Mechanism: a systemd unit starts the Docker Compose workload on boot.
- Boot safety rule: if required runtime config (`.env`) is missing, startup fails fast and service remains down.
- Runtime config ownership: canonical `.env` path is provisioned and managed during bootstrap, not ad-hoc per-operator edits.
- Canonical runtime config path: `/etc/cloudforge/devenv.env`.
- Canonical env template path: `/etc/cloudforge/devenv.env.example`.
- Bootstrap behavior: auto-create `/etc/cloudforge/devenv.env` once from the canonical example when missing.
- Validation rule: startup fails fast if placeholder/default values are still present in canonical runtime config.
- Config validation scope: validate both required key presence and basic value quality before startup.

### Environment Topology
- Canonical meaning: the stack supports multiple concurrent environments, not a single shared fixed-name environment.
- Policy: infrastructure naming and tags must be parameterized by environment identity.
- Environment identity: human-readable slug is canonical in MVP.

### Terraform State Model
- Canonical meaning: each environment has isolated remote Terraform state.
- Backend policy: S3 remote backend with per-environment key pattern (e.g., `cloudforge/<env>/terraform.tfstate`).
- Locking policy: DynamoDB state locking is required in MVP.

### Control Plane Source of Truth
- Canonical meaning: environment ownership and lifecycle status are tracked in a metadata store.
- Policy: metadata store is authoritative; Terraform state is execution state, not product state.

### Python Environment
- Canonical meaning: a default Python virtual environment on the persistent EBS volume is the primary Python runtime.
- Default venv path: `/data/home/.venv` (maps to `/root/.venv` inside the container).
- Persistence invariant: the default venv lives on EBS and survives container rebuilds, instance stop/start, and instance type changes.
- Container image policy: the container image provides only the Python runtime and toolchain (python3.11, pip). No ML packages are installed in the image.
- Base package install: PyTorch + CUDA and common ML tools are installed into the default venv by `init-venv.sh`, called once by `start-dev.sh` on first start (idempotent).
- Activation policy: `/data/home/.bashrc` auto-activates the default venv for all interactive shells. Written by `init-venv.sh`.
- Project venvs: project-specific dependencies go in a per-project venv, typically at `/data/projects/<project>/.venv`. Projects track their requirements in a `requirements.txt` or `pyproject.toml` committed to git.
- Upgrade policy: to update a package, activate the venv and pip install. The venv persists; no rebuild needed.

### Delivery Priority
- Canonical meaning: prioritize minimal infrastructure complexity in MVP.
- Policy: optimize for Docker-based developer workflow first; defer non-essential control-plane components.

### MVP Operating Model
- Canonical meaning: single-operator workflow using Terraform and repository scripts.
- Included components: `terraform` provisioning, host bootstrap scripts, and Docker Compose runtime workflow.
- Deferred components: portal, platform API, async worker orchestration, and metadata store.
- Canonical runtime entrypoint: `bash start-dev.sh` for daily environment startup.
- Runtime validation policy: GPU availability check is hard-fail by default (override may be added explicitly later).
- Startup config source: `start-dev.sh` uses `/etc/cloudforge/devenv.env` as primary source; local `.env` is optional temporary override only.
- Local override policy: local `.env` is accepted only when an explicit override flag is set; default behavior ignores local override.
- Git identity setup policy: apply git setup only when config is missing or differs (idempotent), not on every startup.
- Container reproducibility policy: pin critical base image and tool versions.
- Pinning scope: pin both GPU runtime base image tag and key CLI/tool versions.
- Upgrade cadence: no fixed schedule in MVP; upgrade process is deferred until post-MVP hardening.
- Upgrade trigger policy (MVP): change pinned versions only for (1) runtime breakage blocking workflow, or (2) critical security fixes with clear impact.
