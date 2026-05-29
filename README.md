# cloudforge

A persistent, reproducible remote GPU development environment on AWS EC2.

Your laptop is just a screen and keyboard — all code, compute, and AI run on the server.

---

## Architecture

```
Your Laptop (just a screen)
└── VS Code UI ──SSH──► EC2 Instance (g4dn.xlarge)
                         ├── Docker Engine
                         ├── NVIDIA Container Toolkit (GPU passthrough)
                         ├── EBS Volume /data  ◄── PERSISTENT STORAGE
                         │   ├── /data/projects/     ← your code
                         │   ├── /data/models/       ← model weights
                         │   └── /data/home/         ← configs, dotfiles
                         └── Docker Container
                             ├── Python 3.11 + pip
                             ├── Claude Code CLI
                             ├── Git
                             └── /data/home/.venv  ← PyTorch 2.1 + CUDA (persistent)
```

---

## Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured (`aws configure`)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0 — **one-time only** for initial provisioning
- [VS Code](https://code.visualstudio.com/) with two extensions:
  - [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)
  - [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- An EC2 key pair created in your target AWS region
- An Anthropic API key from [console.anthropic.com](https://console.anthropic.com)

---

## One-Time Setup

### 1. Provision infrastructure with Terraform

**1a. Create the remote state backend (one-time, before `terraform init`)**

Terraform state is stored in S3 with DynamoDB locking. Create these resources once:

```bash
# Create S3 bucket (choose a globally unique name)
aws s3api create-bucket --bucket your-tf-state-bucket --region us-east-1
aws s3api put-bucket-versioning --bucket your-tf-state-bucket \
    --versioning-configuration Status=Enabled

# Create DynamoDB lock table
aws dynamodb create-table \
    --table-name cloudforge-tf-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-1
```

**1b. Configure Terraform variables**

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set at minimum:
#   key_name          — your EC2 key pair name
#   ssh_allowed_cidrs — your operator IP(s), e.g. ["1.2.3.4/32"]
#   web_allowed_cidrs — IPs allowed to reach port 8080, e.g. ["0.0.0.0/0"]
```

Key variables in `terraform.tfvars`:

| Variable | Description | Default |
|----------|-------------|---------|
| `env_name` | Environment slug — used in resource names and tags | `"default"` |
| `key_name` | EC2 key pair name (without `.pem`) | — |
| `ssh_allowed_cidrs` | CIDR list for SSH access (restrict to operator IPs) | — |
| `web_allowed_cidrs` | CIDR list for web app port 8080 | — |
| `instance_type` | EC2 instance type | `"g4dn.xlarge"` |
| `use_spot` | Use spot pricing (~70% cheaper) | `true` |

**1c. Initialize and apply**

```bash
cp backend.tfvars.example backend.tfvars
# Edit backend.tfvars — set bucket name, region, and optionally the state key
terraform init -backend-config=backend.tfvars
terraform apply
```

Terraform creates:
- A `g4dn.xlarge` EC2 instance (NVIDIA T4 GPU)
- A 200 GB `gp3` EBS data volume attached at `/dev/xvdf`
- A security group with separate SSH and web-app ingress rules

Note the outputs — you'll need `public_ip` and `ssh_command`.

**Terraform is only needed this once.** All ongoing operations (start, stop, suspend, resume) use the AWS CLI via the scripts in this repo — no Terraform required after this step.

### 2. SSH into the instance

```bash
# Use the ssh_command from terraform output
ssh -i ~/.ssh/my-ec2-key.pem ubuntu@<public-ip>
```

### 3. Clone this repo and bootstrap the host

```bash
git clone https://github.com/yourname/cloudforge.git
cd cloudforge
bash setup.sh
```

`setup.sh` does the following:
- Installs Docker and the NVIDIA Container Toolkit
- Formats and mounts the EBS volume at `/data`; creates `/data/projects`, `/data/models`, `/data/home`
- Creates `/etc/cloudforge/` and bootstraps `/etc/cloudforge/devenv.env` from the example template
- Installs and enables `cloudforge-devenv.service` — a systemd unit that auto-starts the container on boot

**Log out and back in** after setup so your user is in the `docker` group.

### 4. Configure your environment

`setup.sh` created `/etc/cloudforge/devenv.env` from the example template. Edit it now:

```bash
sudo -e /etc/cloudforge/devenv.env
```

Set the required values:

```bash
ENV_NAME=default              # environment slug — matches your terraform env_name
GIT_NAME=Your Name            # your full name for git commits
GIT_EMAIL=you@example.com     # your email for git commits

# Optional — leave empty to use 'claude login' (Claude.ai subscription)
ANTHROPIC_API_KEY=sk-ant-...
```

`start-dev.sh` reads this file as its primary config source. It validates that `GIT_NAME` and `GIT_EMAIL` are set and not still placeholders — startup will fail fast if they are.

### 5. Start the dev environment

```bash
bash start-dev.sh
```

This builds the Docker image and starts the container. On **first run** it also creates the default Python venv at `/data/home/.venv` and installs PyTorch + CUDA — this takes ~5–10 minutes. On every subsequent start the venv already exists on EBS and is skipped instantly.

### 6. Connect GitHub (automated)

`start-dev.sh` runs `git-setup.sh` only when the git identity inside the container is missing or doesn't match the config. On the **first run** it will:

1. Generate an SSH key (`ed25519`) inside the container using your `GIT_EMAIL`
2. Configure your git identity (`user.name` / `user.email`) globally
3. Print the public key and pause — paste it into GitHub at **Settings → SSH keys → New SSH key**
4. Test the connection once you press Enter

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Add this public key to GitHub:
  https://github.com/settings/ssh/new
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ssh-ed25519 AAAA... you@example.com
```

On every subsequent start it detects the key and identity already match and skips setup entirely — you only paste into GitHub once. The key lives at `/data/home/.ssh/` on the EBS volume, so it survives container rebuilds and instance stop/start cycles.

To run the git setup independently at any time:

```bash
bash git-setup.sh
```

---

## Daily Workflow

Your laptop is just a screen. Everything — Claude Code, Python, Git — runs inside the container on EC2.

### Morning: start up

```bash
# 1. Start the EC2 instance
aws ec2 start-instances --instance-ids <instance-id>

# 2. Open VS Code → Remote-SSH → connect to 'cloudforge'
#    (see VS Code Setup below for one-time SSH config)

# 3. In the VS Code terminal (on the EC2 host):
bash ~/cloudforge/start-dev.sh

# 4. Attach VS Code directly into the container:
#    Cmd+Shift+P → "Dev Containers: Attach to Running Container" → default
#    (container name matches ENV_NAME in /etc/cloudforge/devenv.env)

# 5. Open your project — see "VS Code Setup" → "Open your project folder"
```

You now have a full VS Code window running **inside the container** on EC2. Open your repo under `/data/projects/<repo>` (not `~/cloudforge` on the host).

### During the day (all inside the container via VS Code terminal)

```bash
claude          # Claude Code — edits your files, sees your whole project
python train.py # runs on the GPU
git push        # pushes to GitHub from the server
```

Claude Code edits files on the right, you see the diff live in VS Code on the left. Nothing runs on your laptop.

Web apps are accessible at `http://localhost:8080` — VS Code tunnels the port automatically (check the **Ports** panel).

### Evening: shut down

```bash
bash stop.sh
# All files on /data (EBS) are safe ✓ — updates ~/.ssh/config on next start.sh
```

---

## VS Code Setup (one-time)

### 1. Configure SSH on your laptop

Add this to `~/.ssh/config` on your local machine:

```
Host cloudforge
    HostName <public-ip>      # from terraform output: public_ip
    User ubuntu
    IdentityFile ~/.ssh/my-ec2-key.pem
```

### 2. Connect to the EC2 host

`F1` → `Remote-SSH: Connect to Host` → `cloudforge`

A new VS Code window opens — its terminal is on the EC2 host. Run `start-dev.sh` here.

### 3. Attach into the container

`Cmd+Shift+P` → `Dev Containers: Attach to Running Container` → `default` (or your `ENV_NAME`)

Another VS Code window opens — this one is running **inside the container**. This is where you work. Claude Code, Python, Git — all run here, on the GPU server. Your laptop only renders the UI.

Install the **Python** extension (Microsoft) in this Dev Container window if prompted — it is required for automatic venv activation in the terminal.

### 4. Open your project folder (Dev Container window)

Do **not** open `~/cloudforge` on the host — open your repo under `/data/projects`:

1. **File → Open Folder…**
2. Path: `/data/projects/CityBlues-BGI` (or your repo name)
3. **`Cmd+Shift+P`** (macOS) → **Python: Select Interpreter** → pick **`./.venv/bin/python`**
4. **Terminal → New Terminal** — you should see `(.venv)` and cwd `/data/projects/CityBlues-BGI`

If the terminal has no `(.venv)` prefix:

```bash
cd /data/projects/CityBlues-BGI
source .venv/bin/activate
```

**Note:** `(.venv)` on a bare container shell (without opening the project folder) is the **parent** ML venv at `/root/.venv`, not the project venv.

Set up a project venv once on the server:

```bash
bash /opt/cloudforge/scripts/install-project-venv.sh /data/projects/CityBlues-BGI
```

That script links parent ML packages (torch, detectron2, …), installs web/app deps from `requirements.txt` (skipping ML lines), and writes `.vscode/settings.json` for interpreter auto-selection.

```
Your Laptop                          EC2 Container
────────────                         ─────────────
VS Code UI (just a window) ────────► VS Code Server
                                     Claude Code        ← runs here
                                     Python / PyTorch   ← runs here
                                     Git                ← runs here
                                     /data/projects/    ← files live here
```

### 5. Port forwarding

Open the **Ports** panel in VS Code and forward port `8080`. Your web app is then accessible at `http://localhost:8080` in your laptop browser.

---

## Git Workflow

All git commands run from the **VS Code terminal inside the container**. The SSH key and git identity are already configured by `git-setup.sh`.

### Start a new project

```bash
cd /data/projects
mkdir myapp && cd myapp
git init
git remote add origin git@github.com:yourname/myapp.git

# Let Claude scaffold it
claude
# > "create a FastAPI hello world app with a requirements.txt"

git add .
git commit -m "initial commit"
git push -u origin main
```

### Work on an existing project

```bash
cd /data/projects
git clone git@github.com:yourname/myapp.git
cd myapp
claude
```

### Typical Claude + Git loop

```bash
# 1. Ask Claude to make a change
claude
# > "add user authentication to the API"

# 2. Review the diff in VS Code (Source Control panel or terminal)
git diff

# 3. Test it
python app.py

# 4. Commit and push
git add .
git commit -m "add user authentication"
git push
```

### Pull changes made elsewhere

```bash
git pull origin main
```

### Check status at any time

```bash
git status
git log --oneline -10
```

---

## Using Claude Code

From the **VS Code terminal inside the container** (after attaching via Dev Containers):

```bash
cd /data/projects/myapp
claude
```

Claude edits files on the server; you see the changes live in the VS Code editor on the left. Nothing runs on your laptop.

### Common workflows

**Build a new feature**
```
> "add a /health endpoint that returns GPU memory usage"
```
Claude writes the code, you review the diff in VS Code, run it, done.

**Fix a bug**
```
> "the training loop crashes after epoch 3 — here's the traceback: ..."
```
Paste the error directly. Claude reads your files, finds the cause, patches it.

**Understand existing code**
```
> "explain what model.py does and how data flows through it"
```

**Run a training job then review results**
```bash
# In one terminal: kick off training
python train.py

# In another terminal: ask Claude to interpret the output
claude
> "look at the loss curve in logs/run_001 and tell me if the model is overfitting"
```

**Commit with a good message**
```
> "write a git commit message for these changes and commit them"
```
Claude reads the diff and crafts a descriptive commit message.

### Authentication

Two options — pick one in `/etc/cloudforge/devenv.env`:

**Option A — Claude.ai subscription (Pro/Max)**

Leave `ANTHROPIC_API_KEY` empty. On first start, open a terminal inside the container and run:

```bash
claude
```

Select **Login with Claude.ai**. The CLI prints a URL — the server has no browser, so you open it on your laptop:

```
Please open the following URL in your browser:
https://claude.ai/auth?code=xxxx...
```

```
Container (headless)       Your laptop browser
────────────────────       ───────────────────
prints URL      ─────────► you open it
polls...                   you log in to claude.ai
detects login   ◄─────────  auth completes
saves token
```

Once you log in on your laptop, the server detects the completed auth and saves the session token to `~/.claude/` — which lives on the EBS volume. You only do this once. The token survives container rebuilds, instance restarts, and instance type changes.

**Option B — Anthropic API key (pay-per-token)**

Set `ANTHROPIC_API_KEY=sk-ant-...` in `/etc/cloudforge/devenv.env`. The key is injected into the container automatically via `docker-compose.yml` — no manual steps needed.

---

## Python Environment

PyTorch and ML packages live in a persistent venv on EBS — not in the container image. This means:
- Container rebuilds are fast (no multi-GB PyTorch layer)
- Installed packages survive rebuilds, instance stop/start, and instance type changes
- The venv is created once by `start-dev.sh` on first run

### Default venv — pre-installed packages

| Package | Version |
|---------|---------|
| PyTorch + CUDA 11.8 | 2.1.0 |
| torchvision | 0.16.0 |
| numpy, pandas, matplotlib | latest |
| ipython, jupyter | latest |

The default venv auto-activates in every interactive shell (configured in `/data/home/.bashrc`).

### Per-project venvs

For project-specific dependencies, create a venv inside the project directory:

```bash
cd /data/projects/myapp

# Create a project venv
python -m venv .venv
source .venv/bin/activate

# Install project dependencies
pip install -r requirements.txt
```

The project venv at `/data/projects/myapp/.venv` lives on EBS and persists across container rebuilds.

### Installing packages

```bash
# Into the default venv (active by default in new shells)
pip install transformers

# Verify GPU works
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

Expected output: `True  Tesla T4`

---

## GPU Verification

```bash
# On the EC2 host
nvidia-smi

# Inside the container
docker exec -it devenv nvidia-smi
docker exec -it devenv bash -c "source ~/.venv/bin/activate && python -c \"import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))\""
```

Expected output: `True  Tesla T4`

---

## Data Persistence

| Action | Data on EBS |
|--------|-------------|
| `docker stop devenv` | Safe |
| `docker rm devenv` | Safe |
| EC2 stop | Safe |
| EC2 terminate | **Lost** — detach EBS first |
| Rebuild Docker image | Safe |

The EBS volume is independent of the EC2 instance. If you upgrade instance types, stop the instance, change the type, start it — your data volume re-attaches automatically (Terraform manages the attachment).

---

## Upgrading the Instance

```bash
# Stop the instance
aws ec2 stop-instances --instance-ids <instance-id>

# Change instance type (e.g. to g4dn.2xlarge for more VRAM)
# Edit terraform/terraform.tfvars: instance_type = "g4dn.2xlarge"
terraform apply

aws ec2 start-instances --instance-ids <instance-id>
```

All data on `/data` is preserved.

---

## Suspend & Resume (minimum cost mode)

For longer breaks — weekends, holidays, time away — you can cut costs to ~$3-5/month by snapshotting the EBS volume and deleting it.

### Suspend (end of project / long break)

Run from your **laptop** in the cloudforge repo:

```bash
bash suspend.sh
```

What it does:
1. Stops the Docker container
2. Takes an EBS snapshot (saved to AWS-managed S3)
3. Stops the EC2 instance
4. Waits for snapshot to complete
5. Detaches and deletes the EBS volume
6. Saves a `.cloudforge-state` file locally for resume

```
Before suspend          After suspend
──────────────          ─────────────
EC2  running  $0.16/hr  EC2  stopped  $0/hr
EBS  200 GB   $16/mo    EBS  deleted  $0/mo
                        Snapshot      ~$1-3/mo
                                      ────────
                                      ~$3-5/mo total
```

Takes ~5-10 minutes (mostly waiting for snapshot).

### Resume (coming back)

```bash
bash resume.sh
```

What it does:
1. Starts the EC2 instance
2. Finds the latest snapshot
3. Creates a new EBS volume from it
4. Attaches and mounts the volume at `/data`
5. Prints the new public IP

Then connect and start as normal:
```bash
# Update ~/.ssh/config with new public IP if it changed
ssh cloudforge
bash ~/cloudforge/start-dev.sh
```

Takes ~3-5 minutes.

### Daily use vs long break

| Scenario | Use | Command |
|----------|-----|---------|
| End of day | Stop instance | `bash stop.sh` |
| Coming back same day | Start instance (+ SSH config) | `bash start.sh` |
| Long break (days/weeks) | Suspend | `bash stop.sh --suspend` or `bash suspend.sh` |
| Returning from break | Resume (+ SSH config) | `bash start.sh` or `bash resume.sh` |

---

## Cost Reference (us-east-1)

### EC2 — g4dn.xlarge (NVIDIA T4)

| Pricing | $/hr | 6h/day × 20 days |
|---------|------|-----------------|
| On-demand | ~$0.53 | ~$64/month |
| **Spot (default)** | **~$0.16** | **~$19/month** |

Spot is enabled by default (`use_spot = true` in `terraform.tfvars`). Set `use_spot = false` to switch to on-demand.

### What happens on spot interruption

AWS reclaims spot capacity with a **2-minute warning**. Because the Terraform config sets `instance_interruption_behavior = "stop"` and `spot_instance_type = "persistent"`:

- The instance **stops** (not terminates) — EBS data is completely safe
- The spot request stays open — AWS **automatically restarts** the instance when capacity is available again
- Your running process (training job, web app) is interrupted — push your work to git regularly

### EBS storage — always running

| Volume | Size | $/month |
|--------|------|---------|
| Root (gp3, 30 GB) | | $2.40 |
| Data (gp3, 200 GB) | | $16.00 |
| **Total EBS** | | **~$18/month** |

EBS is charged even when the instance is stopped.

### Monthly total estimate (spot, 6h/day)

| | Cost |
|--|------|
| EC2 spot | ~$19 |
| EBS | ~$18 |
| **Total** | **~$37/month** |

vs ~$82/month on-demand for the same usage.

---

## Service Auto-Recovery

`setup.sh` installs `cloudforge-devenv.service`, a systemd unit that starts the Docker container automatically on every host boot — including after a spot interruption auto-restart.

```bash
# Check service status
systemctl status cloudforge-devenv

# View startup logs
journalctl -u cloudforge-devenv -n 50

# Start / stop manually
sudo systemctl start cloudforge-devenv
sudo systemctl stop cloudforge-devenv
```

The service reads `/etc/cloudforge/devenv.env` as its environment file. If that file is missing or contains placeholder values, the service will fail to start — this is intentional (fail fast rather than start in a broken state).

---

## Troubleshooting

**`docker: Error response from daemon: could not select device driver "nvidia"`**
The NVIDIA Container Toolkit isn't configured. Re-run `setup.sh` or:
```bash
sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
```

**EBS volume not found during setup**
On NVMe instances the volume may appear as `/dev/nvme1n1` rather than `/dev/xvdf`. `setup.sh` auto-detects both.

**Container exits immediately**
The container uses `sleep infinity` as its entrypoint, so it should never exit on its own. Check logs:
```bash
docker compose logs devenv
```

**VS Code can't connect after EC2 start**
The public IP changes on every start/stop cycle. Update your `~/.ssh/config` or use an Elastic IP (add `aws_eip` resource to `terraform/main.tf`).
