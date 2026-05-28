#!/bin/bash
# Resumes the cloudforge environment from a snapshot:
#   1. Starts the EC2 instance
#   2. Creates a new EBS volume from the latest snapshot
#   3. Attaches the volume to the instance
#   4. Mounts it at /data
#
# Run suspend.sh first to create the snapshot and state file.
set -euo pipefail

cd "$(dirname "$0")"

# ── Load state ─────────────────────────────────────────────────────────────────

if [ ! -f .cloudforge-state ]; then
    echo "ERROR: .cloudforge-state not found."
    echo "       Has suspend.sh been run?"
    exit 1
fi

source .cloudforge-state
echo "==> Resuming cloudforge (suspended at $SUSPENDED_AT)"

# ── Start instance ─────────────────────────────────────────────────────────────

echo "==> Starting EC2 instance $INSTANCE_ID"
aws ec2 start-instances --region "$REGION" --instance-ids "$INSTANCE_ID" > /dev/null
echo "    Waiting for instance to be running..."
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

AZ=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].Placement.AvailabilityZone" \
    --output text)

PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "    Running. IP: $PUBLIC_IP  AZ: $AZ"

# ── Find latest snapshot ───────────────────────────────────────────────────────

echo "==> Finding latest cloudforge-data snapshot"
LATEST_SNAPSHOT=$(aws ec2 describe-snapshots \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=cloudforge-data" \
              "Name=status,Values=completed" \
    --query "sort_by(Snapshots, &StartTime)[-1].SnapshotId" \
    --output text)

[ "$LATEST_SNAPSHOT" = "None" ] || [ -z "$LATEST_SNAPSHOT" ] && {
    echo "ERROR: No completed cloudforge-data snapshot found."
    exit 1
}
echo "    Snapshot: $LATEST_SNAPSHOT"

# ── Create EBS volume from snapshot ───────────────────────────────────────────

echo "==> Creating EBS volume from snapshot (AZ: $AZ)"
VOLUME_ID=$(aws ec2 create-volume \
    --region "$REGION" \
    --availability-zone "$AZ" \
    --snapshot-id "$LATEST_SNAPSHOT" \
    --volume-type gp3 \
    --tag-specifications \
        'ResourceType=volume,Tags=[{Key=Name,Value=cloudforge-data},{Key=Project,Value=cloudforge}]' \
    --query "VolumeId" \
    --output text)
echo "    Volume: $VOLUME_ID"
aws ec2 wait volume-available --region "$REGION" --volume-ids "$VOLUME_ID"

# ── Attach volume ──────────────────────────────────────────────────────────────

echo "==> Attaching volume to instance"
aws ec2 attach-volume \
    --region "$REGION" \
    --volume-id "$VOLUME_ID" \
    --instance-id "$INSTANCE_ID" \
    --device "/dev/xvdf" > /dev/null
aws ec2 wait volume-in-use --region "$REGION" --volume-ids "$VOLUME_ID"
echo "    Attached."

# ── Mount on instance ──────────────────────────────────────────────────────────

echo "==> Mounting /data on instance"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 ubuntu@"$PUBLIC_IP" \
    "sudo mount -a" 2>/dev/null \
    && echo "    Mounted." \
    || echo "    (mount -a failed — will auto-mount on next SSH login via /etc/fstab)"

# ── Clean up state file ────────────────────────────────────────────────────────

rm .cloudforge-state

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo "Resumed successfully."
echo ""
echo "Public IP: $PUBLIC_IP"
echo ""
echo "If the IP changed, update ~/.ssh/config on your laptop:"
echo "  Host cloudforge"
echo "      HostName $PUBLIC_IP"
echo ""
echo "Then connect and start:"
echo "  ssh cloudforge"
echo "  bash ~/cloudforge/start-dev.sh"
