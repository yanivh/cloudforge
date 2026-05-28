#!/bin/bash
# One-time EC2 host bootstrap. Run once after provisioning the instance.
# Target OS: Ubuntu 22.04
set -euo pipefail

echo "==> Updating system packages"
sudo apt-get update && sudo apt-get upgrade -y

# ── Docker ───────────────────────────────────────────────────────────────────

echo "==> Installing Docker"
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker "$USER"

echo "==> Installing Docker Compose plugin"
sudo apt-get install -y docker-compose-plugin

# ── NVIDIA Container Toolkit ─────────────────────────────────────────────────

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

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Setup complete!"
echo ""
echo "IMPORTANT: Log out and back in so your user is in the 'docker' group."
echo ""
echo "Then copy your .env file and start the dev environment:"
echo "  cp .env.example .env && vi .env   # add your ANTHROPIC_API_KEY"
echo "  bash start-dev.sh"
