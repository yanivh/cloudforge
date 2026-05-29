#!/bin/bash
# Start the cloudforge EC2 instance and update ~/.ssh/config with the public IP.
#
# If the environment was suspended (suspend.sh / stop.sh --suspend), runs resume.sh
# instead (recreates EBS from snapshot, then updates SSH).
#
# Usage:
#   bash start.sh
#   AWS_REGION=us-east-1 bash start.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/cloudforge.sh
source "${SCRIPT_DIR}/scripts/lib/cloudforge.sh"
cloudforge_load_config

if [ -f .cloudforge-state ]; then
    echo "==> Suspended state detected — running resume.sh"
    exec bash "${SCRIPT_DIR}/resume.sh"
fi

echo "==> Starting cloudforge-${ENV_NAME} in ${REGION}"

INSTANCE_ID="$(cloudforge_find_instance_id)"
if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo "ERROR: No cloudforge-${ENV_NAME} instance found in ${REGION}."
    echo "       Check AWS_REGION in .env (terraform uses us-east-1 by default)."
    exit 1
fi
echo "    Instance: ${INSTANCE_ID}"

STATE="$(cloudforge_instance_state "$INSTANCE_ID")"
case "$STATE" in
    running)
        echo "    Already running."
        ;;
    stopped)
        echo "==> Starting EC2 instance"
        aws ec2 start-instances --region "$REGION" --instance-ids "$INSTANCE_ID" > /dev/null
        echo "    Waiting for instance to be running..."
        aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
        echo "    Instance running."
        ;;
    pending|stopping)
        echo "    Instance is ${STATE} — waiting..."
        aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
        ;;
    *)
        echo "ERROR: Instance is in state '${STATE}' — cannot start."
        exit 1
        ;;
esac

PUBLIC_IP="$(cloudforge_instance_public_ip "$INSTANCE_ID")"
if [ "$PUBLIC_IP" = "None" ] || [ -z "$PUBLIC_IP" ]; then
    echo "ERROR: Instance has no public IP."
    exit 1
fi
echo "    Public IP: ${PUBLIC_IP}"

echo "==> Updating SSH config"
cloudforge_update_ssh_config "$PUBLIC_IP"

echo "==> Ensuring /data is mounted on the instance"
cloudforge_mount_data_best_effort "$PUBLIC_IP"

echo ""
echo "Ready."
echo ""
echo "  ssh ${SSH_HOST}"
echo "  bash ~/cloudforge/start-dev.sh"
echo ""
echo "VS Code: Remote-SSH → Connect to Host → ${SSH_HOST}"
