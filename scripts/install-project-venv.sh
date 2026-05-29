#!/bin/bash
# Create a project venv, link parent ML packages, and install web/app requirements.
# Skips ML packages already provided by cloudforge parent venv (/root/.venv).
#
# Usage:
#   bash /opt/cloudforge/scripts/install-project-venv.sh /data/projects/<repo>
#   bash /opt/cloudforge/scripts/install-project-venv.sh /data/projects/<repo> requirements.txt
#   VENV_PATH=/data/projects/<repo>/00_GUI/.venv bash .../install-project-venv.sh /data/projects/<repo>
set -euo pipefail

PROJECT_DIR="${1:-}"
REQ_FILE="${2:-requirements.txt}"
CLOUDFORGE_DIR="${CLOUDFORGE_DIR:-/opt/cloudforge}"
PARENT_VENV="${PARENT_VENV:-/root/.venv}"

# Packages installed in parent venv — never pip-install into project venv.
ML_PACKAGE_PATTERN='^[[:space:]]*(torch|torchvision|torchaudio|detectron2|opencv-python-headless|opencv-python|rasterio)([=<>!\[]|[[:space:]]*#|[[:space:]]*$)'

if [ -z "$PROJECT_DIR" ]; then
    echo "Usage: $0 <project-dir> [requirements-file]"
    echo "Example: $0 /data/projects/CityBlues-BGI requirements.txt"
    exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
REQ_PATH="${PROJECT_DIR}/${REQ_FILE}"
VENV_DIR="${VENV_PATH:-${PROJECT_DIR}/.venv}"

if [ ! -f "$REQ_PATH" ]; then
    echo "ERROR: Requirements file not found: $REQ_PATH"
    exit 1
fi

if [ ! -d "$PARENT_VENV" ]; then
    echo "ERROR: Parent venv not found: $PARENT_VENV"
    echo "       Run: cd ~/cloudforge && bash start-dev.sh"
    exit 1
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "==> Creating project venv at $VENV_DIR"
    python3.11 -m venv "$VENV_DIR"
fi

echo "==> Linking parent ML site-packages"
bash "${CLOUDFORGE_DIR}/scripts/link-shared-ml-venv.sh" "$VENV_DIR"

PIP="${VENV_DIR}/bin/pip"
PYTHON="${VENV_DIR}/bin/python"

echo "==> Verifying parent ML is visible in project venv"
"$PYTHON" -c "import torch, detectron2; print('  ML OK:', torch.__version__, detectron2.__version__)"

FILTERED="$(mktemp)"
grep -viE "$ML_PACKAGE_PATTERN" "$REQ_PATH" > "$FILTERED" || true

if [ ! -s "$FILTERED" ]; then
    echo "ERROR: No installable requirements left after filtering ML packages."
    echo "       Check $REQ_PATH or pass a different requirements file."
    rm -f "$FILTERED"
    exit 1
fi

echo "==> Installing project requirements (ML packages skipped)"
echo "    Source: $REQ_PATH"
"$PIP" install --upgrade pip
"$PIP" install -r "$FILTERED"
rm -f "$FILTERED"

VENV_REL="${VENV_DIR#${PROJECT_DIR}/}"
VSCODE_DIR="${PROJECT_DIR}/.vscode"
mkdir -p "$VSCODE_DIR"
cat > "${VSCODE_DIR}/settings.json" << EOF
{
  "python.defaultInterpreterPath": "\${workspaceFolder}/${VENV_REL}/bin/python",
  "python.terminal.activateEnvironment": true,
  "terminal.integrated.cwd": "\${workspaceFolder}"
}
EOF

echo ""
echo "Project venv ready."
echo "  Activate: source ${VENV_DIR}/bin/activate"
echo "  Python:   ${PYTHON}"
echo "  VS Code:  open folder ${PROJECT_DIR} (Dev Container window)"
echo "            Python extension will use .vscode/settings.json -> ${VENV_REL}/bin/python"
