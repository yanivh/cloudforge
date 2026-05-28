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

### 6) Daily lifecycle commands

Start:

```bash
aws ec2 start-instances --instance-ids <instance_id> --region us-east-1
```

Stop:

```bash
aws ec2 stop-instances --instance-ids <instance_id> --region us-east-1
```

---

## Track B - Developer Connect-Only Setup

Use this if the environment is already provisioned and running.

### 1) Add SSH host config on your laptop

Edit `~/.ssh/config`:

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
```

Then open that folder in the remote+container window.

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
