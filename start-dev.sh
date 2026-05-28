#!/bin/bash
# Daily start script. Run from the cloudforge repo directory.
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
    echo "ERROR: .env file not found."
    echo "       cp .env.example .env  and fill in the required values"
    exit 1
fi

echo "==> Starting dev environment"
docker compose up -d --build

echo ""
echo "Dev environment is running."
echo ""
echo "Open a shell inside the container:"
echo "  docker exec -it devenv bash"
echo ""
echo "Or attach via VS Code Dev Containers:"
echo "  Command Palette → 'Dev Containers: Attach to Running Container' → devenv"
echo ""
echo "GPU status:"
docker exec devenv nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null \
    || echo "  (GPU not visible yet — container may still be starting)"

# Run git setup automatically if GIT_NAME and GIT_EMAIL are configured
set -a; source .env; set +a
if [ -n "${GIT_NAME:-}" ] && [ -n "${GIT_EMAIL:-}" ]; then
    echo ""
    bash git-setup.sh
fi
