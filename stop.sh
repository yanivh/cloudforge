#!/bin/bash
# Stop the cloudforge EC2 instance (EBS data volume stays attached — ~\$18/mo while stopped).
#
# For long breaks (snapshot + delete data volume, ~\$3-5/mo), use suspend mode:
#   bash stop.sh --suspend
#   # same as: bash suspend.sh
#
# Usage:
#   bash stop.sh
#   bash stop.sh --suspend
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "--suspend" ] || [ "${1:-}" = "-s" ]; then
    exec bash "${SCRIPT_DIR}/suspend.sh"
fi

if [ -n "${1:-}" ]; then
    echo "Usage: bash stop.sh [--suspend]"
    exit 1
fi

# shellcheck source=scripts/lib/cloudforge.sh
source "${SCRIPT_DIR}/scripts/lib/cloudforge.sh"
cloudforge_load_config

echo "==> Stopping cloudforge-${ENV_NAME} in ${REGION}"
echo "    (EBS data volume is kept — use 'bash stop.sh --suspend' for minimum cost)"

INSTANCE_ID="$(cloudforge_find_instance_id)"
if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo "ERROR: No cloudforge-${ENV_NAME} instance found in ${REGION}."
    exit 1
fi
echo "    Instance: ${INSTANCE_ID}"

STATE="$(cloudforge_instance_state "$INSTANCE_ID")"
case "$STATE" in
    stopped)
        echo "    Already stopped."
        exit 0
        ;;
    running)
        echo "==> Stopping Docker container"
        cloudforge_stop_container_best_effort "$INSTANCE_ID"
        echo "==> Stopping EC2 instance"
        aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID" > /dev/null
        echo "    Waiting for instance to stop..."
        aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$INSTANCE_ID"
        echo "    Instance stopped."
        ;;
    pending|stopping)
        echo "    Instance is ${STATE} — waiting..."
        aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$INSTANCE_ID"
        echo "    Instance stopped."
        ;;
    *)
        echo "ERROR: Instance is in state '${STATE}' — cannot stop."
        exit 1
        ;;
esac

echo ""
echo "Stopped. Data on /data (EBS) is safe."
echo ""
echo "  Start again:  bash start.sh"
echo "  Long break:   bash stop.sh --suspend"
