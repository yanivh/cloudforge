# Shared helpers for cloudforge laptop-side scripts (start, stop, suspend, resume).
# Source from repo scripts: source "$(dirname "$0")/scripts/lib/cloudforge.sh"

cloudforge_repo_root() {
    # Caller is start.sh / stop.sh / resume.sh / suspend.sh at repo root.
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

cloudforge_load_config() {
    local root
    root="$(cloudforge_repo_root)"
    cd "$root"

    if [ -f /etc/cloudforge/devenv.env ]; then
        set -a
        # shellcheck source=/dev/null
        source /etc/cloudforge/devenv.env
        set +a
    elif [ -f .env ]; then
        set -a
        # shellcheck source=/dev/null
        source .env
        set +a
    fi

    ENV_NAME="${ENV_NAME:-default}"
    REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "us-east-1")}"
    SSH_HOST="${SSH_HOST:-cloudforge}"
}

cloudforge_ssh_identity_file() {
    if [ -n "${SSH_IDENTITY_FILE:-}" ]; then
        echo "${SSH_IDENTITY_FILE/#\~/$HOME}"
        return
    fi
    local key_name="cloudforge"
    if [ -f terraform/terraform.tfvars ]; then
        key_name="$(grep -E '^[[:space:]]*key_name' terraform/terraform.tfvars \
            | sed -n 's/.*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
        key_name="${key_name:-cloudforge}"
    fi
    echo "$HOME/.ssh/${key_name}.pem"
}

cloudforge_find_instance_id() {
    local state_filter="${1:-running,stopped,stopping,pending}"
    aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Name,Values=cloudforge-${ENV_NAME}" \
                  "Name=instance-state-name,Values=${state_filter}" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text
}

cloudforge_instance_state() {
    local instance_id="$1"
    aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$instance_id" \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text
}

cloudforge_instance_public_ip() {
    local instance_id="$1"
    aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$instance_id" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text
}

cloudforge_stop_container_best_effort() {
    local instance_id="$1"
    local public_ip
    public_ip="$(cloudforge_instance_public_ip "$instance_id")"

    if [ "$public_ip" = "None" ] || [ -z "$public_ip" ]; then
        echo "    (no public IP — skipping Docker stop)"
        return 0
    fi

    local identity
    identity="$(cloudforge_ssh_identity_file)"
    local ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
    if [ -f "$identity" ]; then
        ssh_opts+=(-i "$identity")
    fi

    ssh "${ssh_opts[@]}" "ubuntu@${public_ip}" \
        "cd ~/cloudforge && docker compose down 2>/dev/null || true" 2>/dev/null \
        && echo "    Docker container stopped." \
        || echo "    (could not reach instance — skipping Docker stop)"
}

cloudforge_mount_data_best_effort() {
    local public_ip="$1"
    local identity
    identity="$(cloudforge_ssh_identity_file)"
    local ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
    if [ -f "$identity" ]; then
        ssh_opts+=(-i "$identity")
    fi

    ssh "${ssh_opts[@]}" "ubuntu@${public_ip}" \
        "sudo mount -a" 2>/dev/null \
        && echo "    /data mounted." \
        || echo "    (mount -a skipped — /data may mount on next SSH login)"
}

cloudforge_update_ssh_config() {
    local public_ip="$1"
    local identity
    identity="$(cloudforge_ssh_identity_file)"
    local config="${HOME}/.ssh/config"
    local start="# >>> cloudforge-managed ${ENV_NAME} >>>"
    local end="# <<< cloudforge-managed ${ENV_NAME} <<<"

    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    touch "$config"
    chmod 600 "$config"

    local tmp
    tmp="$(mktemp)"
    if [ -f "$config" ]; then
        awk -v start="$start" -v end="$end" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip       { print }
        ' "$config" > "$tmp"
    fi

    {
        echo ""
        echo "$start"
        echo "Host ${SSH_HOST}"
        echo "    HostName ${public_ip}"
        echo "    User ubuntu"
        echo "    IdentityFile ${identity}"
        echo "    StrictHostKeyChecking accept-new"
        echo "$end"
    } >> "$tmp"

    mv "$tmp" "$config"
    echo "    Updated ${config} → Host ${SSH_HOST} → ${public_ip}"
}
