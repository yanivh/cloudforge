#!/bin/bash
# Idempotent git + SSH setup inside the devenv container.
# Reads GIT_NAME and GIT_EMAIL from .env, generates an SSH key if absent,
# configures git identity, and prints the public key to add to GitHub.
set -euo pipefail

cd "$(dirname "$0")"

# ── Load .env ─────────────────────────────────────────────────────────────────

if [ ! -f .env ]; then
    echo "ERROR: .env not found. Run: cp .env.example .env"
    exit 1
fi

set -a; source .env; set +a

if [ -z "${GIT_NAME:-}" ] || [ -z "${GIT_EMAIL:-}" ]; then
    echo "ERROR: GIT_NAME and GIT_EMAIL must be set in .env"
    exit 1
fi

# ── Ensure container is running ───────────────────────────────────────────────

if ! docker ps --filter "name=^devenv$" --filter "status=running" --format '{{.Names}}' | grep -q devenv; then
    echo "ERROR: devenv container is not running. Run: bash start-dev.sh"
    exit 1
fi

# ── SSH key ───────────────────────────────────────────────────────────────────

KEY_PATH="/root/.ssh/id_ed25519"

if docker exec devenv test -f "$KEY_PATH"; then
    echo "==> SSH key already exists — skipping generation"
else
    echo "==> Generating SSH key for $GIT_EMAIL"
    docker exec devenv bash -c "
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        ssh-keygen -t ed25519 -C '$GIT_EMAIL' -f $KEY_PATH -N ''
        chmod 600 $KEY_PATH
    "
    echo "    Done."
fi

# ── Git identity ──────────────────────────────────────────────────────────────

echo "==> Configuring git identity"
docker exec devenv bash -c "
    git config --global user.name  '$GIT_NAME'
    git config --global user.email '$GIT_EMAIL'
    git config --global init.defaultBranch main
"

# ── Print public key ──────────────────────────────────────────────────────────

PUB_KEY=$(docker exec devenv cat "${KEY_PATH}.pub")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Add this public key to GitHub:"
echo "  https://github.com/settings/ssh/new"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "$PUB_KEY"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Test connection (optional — only if key was just added) ───────────────────

read -r -p "Press Enter after adding the key to GitHub to test the connection (or Ctrl+C to skip)..."

echo "==> Testing GitHub SSH connection"
if docker exec devenv bash -c "ssh -T -o StrictHostKeyChecking=no git@github.com 2>&1 | grep -q 'successfully authenticated'"; then
    echo "    Connected! Git is ready to use."
else
    echo "    Could not verify — make sure the key was saved in GitHub and try:"
    echo "      docker exec -it devenv ssh -T git@github.com"
fi
