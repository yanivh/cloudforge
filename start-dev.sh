#!/bin/bash
# Daily start script. Run from the cloudforge repo directory on the EC2 host.
set -euo pipefail

cd "$(dirname "$0")"

# ── Config ────────────────────────────────────────────────────────────────────

CANONICAL_ENV=/etc/cloudforge/devenv.env
USE_LOCAL=false

for arg in "$@"; do
    case "$arg" in
        --local-env) USE_LOCAL=true ;;
    esac
done

if $USE_LOCAL; then
    if [ ! -f .env ]; then
        echo "ERROR: --local-env set but .env not found in $(pwd)."
        exit 1
    fi
    echo "==> Loading config from .env (local override)"
    set -a; source .env; set +a
else
    if [ ! -f "$CANONICAL_ENV" ]; then
        echo "ERROR: $CANONICAL_ENV not found."
        echo "       Run setup.sh first, then edit $CANONICAL_ENV"
        exit 1
    fi
    echo "==> Loading config from $CANONICAL_ENV"
    set -a; source "$CANONICAL_ENV"; set +a
fi

# ── Validate config ───────────────────────────────────────────────────────────

ERRORS=()
[[ -z "${GIT_NAME:-}"  || "${GIT_NAME}"  == "Your Name"       ]] && ERRORS+=("GIT_NAME is not set or still a placeholder")
[[ -z "${GIT_EMAIL:-}" || "${GIT_EMAIL}" == "you@example.com" ]] && ERRORS+=("GIT_EMAIL is not set or still a placeholder")

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "ERROR: Config validation failed:"
    for e in "${ERRORS[@]}"; do echo "  - $e"; done
    if $USE_LOCAL; then
        echo "  Edit .env and set real values."
    else
        echo "  Edit $CANONICAL_ENV and set real values."
    fi
    exit 1
fi

CONTAINER="${ENV_NAME:-devenv}"

# ── Start environment ─────────────────────────────────────────────────────────

echo "==> Starting dev environment (container: $CONTAINER)"
docker compose up -d --build

# ── GPU check (hard fail) ─────────────────────────────────────────────────────

echo "==> Verifying GPU access"
if ! docker compose exec -T devenv nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null; then
    echo "ERROR: GPU not accessible inside the container."
    echo "       Check that the NVIDIA Container Toolkit is installed and configured:"
    echo "         sudo nvidia-ctk runtime configure --runtime=docker"
    echo "         sudo systemctl restart docker"
    echo "       Then re-run this script."
    docker compose down
    exit 1
fi

# ── Default venv init (idempotent) ───────────────────────────────────────────

echo "==> Checking default Python venv"
if docker compose exec -T devenv test -f /root/.venv/bin/activate 2>/dev/null; then
    echo "    Venv exists — skipping init"
else
    echo "    First-time setup: creating venv and installing PyTorch (may take several minutes)"
    docker compose exec -T devenv bash -s < init-venv.sh
fi

# ── Git setup (idempotent) ────────────────────────────────────────────────────

if [ -n "${GIT_NAME:-}" ] && [ -n "${GIT_EMAIL:-}" ]; then
    CURRENT_NAME=$(docker compose exec -T devenv git config --global user.name 2>/dev/null || true)
    CURRENT_EMAIL=$(docker compose exec -T devenv git config --global user.email 2>/dev/null || true)
    if [ "$CURRENT_NAME" != "$GIT_NAME" ] || [ "$CURRENT_EMAIL" != "$GIT_EMAIL" ]; then
        echo ""
        bash git-setup.sh
    else
        echo "==> Git identity already configured — skipping"
    fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Dev environment is running."
echo ""
echo "Open a shell inside the container:"
echo "  docker exec -it $CONTAINER bash"
echo ""
echo "Or attach via VS Code Dev Containers:"
echo "  Command Palette → 'Dev Containers: Attach to Running Container' → $CONTAINER"
echo ""
echo "GPU status:"
docker compose exec -T devenv nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null \
    | sed 's/^/  /'
