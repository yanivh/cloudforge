#!/bin/bash
# Suspends the cloudforge environment to minimize cost:
#   1. Snapshots the EBS data volume to S3
#   2. Stops the EC2 instance
#   3. Detaches and deletes the EBS volume
#
# Cost while suspended: ~$3-5/month (snapshot + stopped instance root volume)
# Restore with: bash resume.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/cloudforge.sh
source "${SCRIPT_DIR}/scripts/lib/cloudforge.sh"
cloudforge_load_config

# ── Find resources by tag ──────────────────────────────────────────────────────

echo "==> Finding cloudforge-${ENV_NAME} resources in $REGION"

INSTANCE_ID=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=cloudforge-${ENV_NAME}" \
              "Name=instance-state-name,Values=running,stopped" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

[ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ] && {
    echo "ERROR: No cloudforge-${ENV_NAME} instance found."
    exit 1
}
echo "    Instance: $INSTANCE_ID"

VOLUME_ID=$(aws ec2 describe-volumes \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=cloudforge-${ENV_NAME}-data" \
              "Name=status,Values=available,in-use" \
    --query "Volumes[0].VolumeId" \
    --output text)

[ "$VOLUME_ID" = "None" ] || [ -z "$VOLUME_ID" ] && {
    echo "ERROR: No cloudforge-${ENV_NAME}-data volume found."
    exit 1
}
echo "    Volume:   $VOLUME_ID"

# ── Stop Docker container (best-effort) ────────────────────────────────────────

echo "==> Stopping Docker container"
cloudforge_stop_container_best_effort "$INSTANCE_ID"

# ── Snapshot ───────────────────────────────────────────────────────────────────

echo "==> Creating EBS snapshot"
SNAPSHOT_ID=$(aws ec2 create-snapshot \
    --region "$REGION" \
    --volume-id "$VOLUME_ID" \
    --description "cloudforge-${ENV_NAME}-suspend-$(date +%Y%m%d-%H%M%S)" \
    --tag-specifications \
        "ResourceType=snapshot,Tags=[{Key=Name,Value=cloudforge-${ENV_NAME}-data},{Key=Environment,Value=${ENV_NAME}},{Key=Project,Value=cloudforge}]" \
    --query "SnapshotId" \
    --output text)
echo "    Snapshot $SNAPSHOT_ID started."

# ── Stop instance (snapshot continues in background) ───────────────────────────

echo "==> Stopping EC2 instance"
aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID" > /dev/null
echo "    Waiting for instance to stop..."
aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$INSTANCE_ID"
echo "    Instance stopped."

# ── Wait for snapshot ──────────────────────────────────────────────────────────

echo "==> Waiting for snapshot to complete (may take a few minutes)"
aws ec2 wait snapshot-completed --region "$REGION" --snapshot-ids "$SNAPSHOT_ID"
echo "    Snapshot complete."

# ── Detach and delete EBS volume ───────────────────────────────────────────────

echo "==> Detaching EBS volume"
aws ec2 detach-volume --region "$REGION" --volume-id "$VOLUME_ID" > /dev/null
aws ec2 wait volume-available --region "$REGION" --volume-ids "$VOLUME_ID"

echo "==> Deleting EBS volume"
aws ec2 delete-volume --region "$REGION" --volume-id "$VOLUME_ID"
echo "    Volume deleted."

# ── Save state for resume ──────────────────────────────────────────────────────

cat > .cloudforge-state << EOF
ENV_NAME=$ENV_NAME
INSTANCE_ID=$INSTANCE_ID
SNAPSHOT_ID=$SNAPSHOT_ID
REGION=$REGION
SUSPENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo "Suspended successfully."
echo ""
echo "Running costs while suspended:"
echo "  Snapshot (~\$1-3/month depending on data size)"
echo "  Stopped instance root volume, 30 GB (~\$2.40/month)"
echo "  Total: ~\$3-5/month"
echo ""
echo "To restore: bash start.sh   # or: bash resume.sh"
