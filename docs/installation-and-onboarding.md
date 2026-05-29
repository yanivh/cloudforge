# Cloudforge Installation and Onboarding Guide

This guide is split into two tracks:

- **Track A: Platform/DevOps owner setup** (provision and bootstrap a new environment)
- **Track B: Developer connect-only setup** (join an existing environment and start coding)

Use Track A once per environment. Use Track B for each developer.

---

## Track A - Platform/DevOps Owner Setup

### 1) Prerequisites on your laptop

Install and verify:

- AWS CLI (configured for the target AWS account)
- Terraform `>= 1.0`
- SSH client

Quick checks:

```bash
aws sts get-caller-identity
terraform -version
```

### 2) Create AWS prerequisites (one-time)

Create EC2 SSH key pair:

```bash
aws ec2 create-key-pair --key-name cloudforge --region us-east-1 --query 'KeyMaterial' --output text > ~/.ssh/cloudforge.pem
chmod 400 ~/.ssh/cloudforge.pem
```

Create Terraform remote state backend:

```bash
BUCKET="cloudforge-tfstate-$(whoami)"
REGION="us-east-1"

aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name cloudforge-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"
```

### 3) Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
cp backend.tfvars.example backend.tfvars
```

Set your public IPv4 for SSH allowlist:

```bash
curl -4 -s ifconfig.me
```

Update `terraform.tfvars`:

- `key_name = "cloudforge"`
- `ssh_allowed_cidrs = ["<YOUR_IPV4>/32"]`
- `web_allowed_cidrs = ["0.0.0.0/0"]`
- `instance_type = "t3.large"` (CPU mode default)
- `use_spot = false`

Update `backend.tfvars`:

- `bucket = "<your bucket name>"`
- `key = "cloudforge/default/terraform.tfstate"`
- `region = "us-east-1"`
- `dynamodb_table = "cloudforge-tf-locks"`
- `encrypt = true`

### 4) Provision infrastructure

```bash
terraform init -backend-config=backend.tfvars
terraform apply
```

Save outputs:

```bash
terraform output public_ip
terraform output instance_id
```

### 5) Bootstrap the EC2 host

SSH into host:

```bash
ssh -i ~/.ssh/cloudforge.pem ubuntu@<public_ip>
```

On the host:

```bash
git clone https://github.com/<your-org-or-user>/cloudforge.git
cd cloudforge
bash setup.sh
```

Edit runtime config:

```bash
sudo -e /etc/cloudforge/devenv.env
```

Set:

- `GIT_NAME=...`
- `GIT_EMAIL=...`
- `USE_GPU=false` (CPU mode)
- optional `ANTHROPIC_API_KEY=...`

Re-login (required for docker group):

```bash
exit
ssh -i ~/.ssh/cloudforge.pem ubuntu@<public_ip>
cd ~/cloudforge
bash start-dev.sh
```

Expected success message includes:

- `Dev environment is running.`
- `GPU status: skipped (USE_GPU=false)`
- Detectron2 installed in the default venv (CPU wheels when `USE_GPU=false`)

Verify inside the container:

```bash
python -c "import torch, detectron2, cv2, rasterio; print(torch.__version__, detectron2.__version__)"
```

### Parent vs project venv (ML vs web stack)

- **Parent venv** (`/data/home/.venv`): torch 2.5.1, torchvision 0.20.1, detectron2 0.6, opencv, rasterio, etc. (installed by `init-venv.sh`)
- **Project venv** (e.g. `/data/projects/CityBlues-BGI/.venv`): FastAPI, uvicorn, SQLAlchemy, rio-tiler, etc.
- **Do not** `pip install detectron2==0.6` in the project venv — it is not on PyPI; use the parent venv via `_shared_ml.pth`

Install a project venv (one command — skips ML lines in `requirements.txt` automatically):

```bash
bash /opt/cloudforge/scripts/install-project-venv.sh /data/projects/CityBlues-BGI
```

Custom venv path (e.g. `00_GUI/.venv`):

```bash
VENV_PATH=/data/projects/<repo>/00_GUI/.venv \
  bash /opt/cloudforge/scripts/install-project-venv.sh /data/projects/<repo>
```

Optional: split requirements in git using `requirements-web.example.txt` as a template.

If upgrading from an older parent venv (torch 2.1), reset once:

```bash
rm -rf /data/home/.venv
bash start-dev.sh
```

### 6) Daily lifecycle commands

Start:

```bash
bash start.sh   # starts EC2 and updates ~/.ssh/config with the public IP
```

Stop:

```bash
bash stop.sh
```

Long break (minimum cost — snapshot + delete data volume):

```bash
bash stop.sh --suspend
```

---

## Track B - Developer Connect-Only Setup

Use this if the environment is already provisioned and running.

### 1) SSH host config on your laptop

`bash start.sh` writes a managed block to `~/.ssh/config` (Host `cloudforge` by default). To set it manually instead:

```sshconfig
Host cloudforge
    HostName <public_ip>
    User ubuntu
    IdentityFile ~/.ssh/cloudforge.pem
```

Test:

```bash
ssh cloudforge
exit
```

### 2) Connect with VS Code/Cursor

1. Open command palette: `Cmd+Shift+P` (macOS)
2. Run: `Remote-SSH: Connect to Host`
3. Select: `cloudforge`
4. In the remote window, ensure extension `Dev Containers` (Microsoft) is installed for that remote host
5. Run: `Dev Containers: Attach to Running Container...`
6. Select container: `default`

### 3) Verify environment inside container

Open terminal in attached container:

```bash
python --version
pwd
git config --global user.name
git config --global user.email
```

### 4) Start working with project repos

Inside container:

```bash
cd /data/projects
git clone git@github.com:<owner>/<repo>.git
cd <repo>
bash /opt/cloudforge/scripts/install-project-venv.sh "$(pwd)"
source .venv/bin/activate
```

Then open that folder in the remote+container window:

1. **File → Open Folder** → `/data/projects/<repo>` (not `~/cloudforge` on the host)
2. Install extension **Python** in the Dev Container window if prompted
3. **Cmd+Shift+P** → **Python: Select Interpreter** → choose `<repo>/.venv`
4. Open a **new** terminal — you should see `(.venv)` and cwd `/data/projects/<repo>`

If the terminal shows `root@...` without `(.venv)`, run:

```bash
source .venv/bin/activate
```

Note: `(.venv)` on login to the container without opening a project folder is the **parent** ML venv at `/root/.venv`, not the project venv.

---

## Troubleshooting

- **`permission denied: ~/.ssh/cloudforge.pem` while creating key**
  - Ensure `~/.ssh` exists and is writable, then recreate the key file.
- **`MaxSpotInstanceCountExceeded`**
  - Set `use_spot = false` and apply again.
- **`VcpuLimitExceeded` for GPU instance**
  - This is AWS quota-related. Use CPU mode (`t3.large`) or request quota increase.
- **`python` not found on EC2 host**
  - Expected. Run Python checks inside container: `docker exec -it default bash`.
- **Dev Containers command missing**
  - Install `Dev Containers` extension (`ms-vscode-remote.remote-containers`) in the remote SSH window.
