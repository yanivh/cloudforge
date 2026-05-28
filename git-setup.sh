#!/bin/bash
# Idempotent git + SSH setup inside the devenv container.
# Reads GIT_NAME and GIT_EMAIL from the canonical config or .env,
# generates an SSH key if absent, configures git identity if needed,
# and prints the public key to add to GitHub.
set -euo pipefail

cd "$(dirname "$0")"

# ── Load config ───────────────────────────────────────────────────────────────

CANONICAL_ENV=/etc/cloudforge/devenv.env
USE_LOCAL=false

for arg in "$@"; do
    case "$arg" in
        --local-env) USE_LOCAL=true ;;
    esac
done

if $USE_LOCAL; then
    if [ ! -f .env ]; then
        echo "ERROR: --local-env set but .env not found."
        exit 1
    fi
    set -a; source .env; set +a
elif [ -f "$CANONICAL_ENV" ]; then
    set -a; source "$CANONICAL_ENV"; set +a
elif [ -f .env ]; then
    set -a; source .env; set +a
else
    echo "ERROR: No config found. Run setup.sh or pass --local-env with a .env file."
    exit 1
fi

if [ -z "${GIT_NAME:-}" ] || [ -z "${GIT_EMAIL:-}" ]; then
    echo "ERROR: GIT_NAME and GIT_EMAIL must be set in the config"
    exit 1
fi

CONTAINER="${ENV_NAME:-devenv}"

# ── Ensure container is running ───────────────────────────────────────────────

if ! docker ps --filter "name=^${CONTAINER}$" --filter "status=running" --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "ERROR: $CONTAINER container is not running. Run: bash start-dev.sh"
    exit 1
fi

# ── SSH key ───────────────────────────────────────────────────────────────────

KEY_PATH="/root/.ssh/id_ed25519"

if docker exec "$CONTAINER" test -f "$KEY_PATH"; then
    echo "==> SSH key already exists — skipping generation"
    KEY_EXISTS=true
else
    echo "==> Generating SSH key for $GIT_EMAIL"
    docker exec "$CONTAINER" bash -c "
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        ssh-keygen -t ed25519 -C '$GIT_EMAIL' -f $KEY_PATH -N ''
        chmod 600 $KEY_PATH
    "
    echo "    Done."
    KEY_EXISTS=false
fi

# ── Git identity ──────────────────────────────────────────────────────────────

CURRENT_NAME=$(docker exec "$CONTAINER" git config --global user.name 2>/dev/null || true)
CURRENT_EMAIL=$(docker exec "$CONTAINER" git config --global user.email 2>/dev/null || true)

if [ "$CURRENT_NAME" != "$GIT_NAME" ] || [ "$CURRENT_EMAIL" != "$GIT_EMAIL" ]; then
    echo "==> Configuring git identity"
    docker exec "$CONTAINER" bash -c "
        git config --global user.name  '$GIT_NAME'
        git config --global user.email '$GIT_EMAIL'
        git config --global init.defaultBranch main
    "
else
    echo "==> Git identity already configured — skipping"
fi

# ── Print public key (only when key was just created) ─────────────────────────

PUB_KEY=$(docker exec "$CONTAINER" cat "${KEY_PATH}.pub")

if ! $KEY_EXISTS; then
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

    read -r -p "Press Enter after adding the key to GitHub to test the connection (or Ctrl+C to skip)..."

    echo "==> Testing GitHub SSH connection"
    if docker exec "$CONTAINER" bash -c "ssh -T -o StrictHostKeyChecking=no git@github.com 2>&1 | grep -q 'successfully authenticated'"; then
        echo "    Connected! Git is ready to use."
    else
        echo "    Could not verify — make sure the key was saved in GitHub and try:"
        echo "      docker exec -it $CONTAINER ssh -T git@github.com"
    fi
fi
