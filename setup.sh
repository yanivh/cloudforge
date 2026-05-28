#!/bin/bash
# One-time EC2 host bootstrap. Run once after provisioning the instance.
# Target OS: Ubuntu 22.04
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Updating system packages"
sudo apt-get update && sudo apt-get upgrade -y

# ── Docker ───────────────────────────────────────────────────────────────────

echo "==> Installing Docker"
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker "$USER"

echo "==> Installing Docker Compose plugin"
sudo apt-get install -y docker-compose-plugin

# ── NVIDIA Container Toolkit (optional) ──────────────────────────────────────

USE_GPU="${USE_GPU:-false}"
if [ "$USE_GPU" = "true" ]; then
    echo "==> Installing NVIDIA Container Toolkit"
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
else
    echo "==> Skipping NVIDIA Container Toolkit (USE_GPU=false)"
fi

# ── EBS Volume ───────────────────────────────────────────────────────────────

echo "==> Detecting EBS data volume"
# On NVMe instances (e.g. g4dn), the volume attached as /dev/xvdf appears at /dev/nvme1n1.
# The block below checks both paths.
if [ -b /dev/xvdf ]; then
    EBS_DEVICE=/dev/xvdf
elif [ -b /dev/nvme1n1 ]; then
    EBS_DEVICE=/dev/nvme1n1
else
    echo "ERROR: EBS data volume not found at /dev/xvdf or /dev/nvme1n1."
    echo "       Attach the volume to the instance, then re-run this script."
    exit 1
fi
echo "    Using device: $EBS_DEVICE"

# Format only if the device has no filesystem
if ! sudo blkid "$EBS_DEVICE" &>/dev/null; then
    echo "==> Formatting $EBS_DEVICE as ext4"
    sudo mkfs.ext4 "$EBS_DEVICE"
fi

echo "==> Mounting $EBS_DEVICE at /data"
sudo mkdir -p /data
# Add to fstab for auto-mount on reboot (nofail prevents boot hang if volume is absent)
if ! grep -q "$EBS_DEVICE" /etc/fstab; then
    echo "$EBS_DEVICE /data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
fi
sudo mount -a

echo "==> Creating /data directory structure"
sudo mkdir -p /data/projects /data/models /data/home
sudo chown -R "$USER:$USER" /data

# ── /etc/cloudforge ───────────────────────────────────────────────────────────

echo "==> Creating /etc/cloudforge"
sudo mkdir -p /etc/cloudforge

echo "==> Writing /etc/cloudforge/devenv.env.example"
sudo tee /etc/cloudforge/devenv.env.example > /dev/null << 'ENVEOF'
# Cloudforge environment configuration
# This file is the canonical runtime config source for start-dev.sh and the systemd service.

# Environment name — used for Docker container naming
ENV_NAME=default

# Anthropic API key — leave empty to use 'claude login' (Claude.ai subscription)
ANTHROPIC_API_KEY=

# Enable GPU-specific startup checks/tooling
USE_GPU=false

# Git identity (required — must not be placeholders)
GIT_NAME=Your Name
GIT_EMAIL=you@example.com

# AWS region (used by suspend.sh and resume.sh run from your laptop)
AWS_REGION=us-east-1
ENVEOF

if [ ! -f /etc/cloudforge/devenv.env ]; then
    echo "==> Bootstrapping /etc/cloudforge/devenv.env from example"
    sudo cp /etc/cloudforge/devenv.env.example /etc/cloudforge/devenv.env
    sudo chown "$USER:$USER" /etc/cloudforge/devenv.env
    echo ""
    echo "IMPORTANT: Edit /etc/cloudforge/devenv.env and set your real values:"
    echo "  sudo -e /etc/cloudforge/devenv.env"
    echo ""
else
    echo "    /etc/cloudforge/devenv.env already exists — skipping bootstrap"
fi

# ── Systemd service ───────────────────────────────────────────────────────────

echo "==> Installing cloudforge-devenv.service"
sudo tee /etc/systemd/system/cloudforge-devenv.service > /dev/null << UNITEOF
[Unit]
Description=Cloudforge dev environment
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${REPO_DIR}
EnvironmentFile=/etc/cloudforge/devenv.env
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNITEOF

sudo systemctl daemon-reload
sudo systemctl enable cloudforge-devenv
echo "    Service installed and enabled — will auto-start on next boot."

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Log out and back in so your user is in the 'docker' group."
echo "  2. Edit the runtime config:  sudo -e /etc/cloudforge/devenv.env"
echo "  3. Start the dev environment: bash start-dev.sh"
