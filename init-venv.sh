#!/bin/bash
# Idempotent. Creates the default Python venv at /root/.venv (→ /data/home/.venv on EBS),
# installs PyTorch, Detectron2 0.6, and ML packages from requirements-ml.txt.
# Runs INSIDE the container — called from start-dev.sh.
set -euo pipefail

USE_GPU="${USE_GPU:-false}"
VENV_DIR="/root/.venv"
PIP="$VENV_DIR/bin/pip"
PYTHON="$VENV_DIR/bin/python"
CLOUDFORGE_DIR="${CLOUDFORGE_DIR:-/opt/cloudforge}"
REQUIREMENTS_ML="${CLOUDFORGE_DIR}/requirements-ml.txt"

TORCH_VERSION="2.5.1"
TORCHVISION_VERSION="0.20.1"
DETECTRON2_REF="git+https://github.com/facebookresearch/detectron2.git@v0.6"

if [ ! -d "$VENV_DIR" ] || [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "==> Creating default Python venv at $VENV_DIR"
    python3.11 -m venv "$VENV_DIR"
fi

echo "==> Upgrading pip"
"$PIP" install --no-cache-dir --upgrade pip setuptools wheel

if [ "$USE_GPU" = "true" ]; then
    echo "==> Installing PyTorch ${TORCH_VERSION} + torchvision ${TORCHVISION_VERSION} (CUDA 12.1)"
    "$PIP" install --no-cache-dir \
        "torch==${TORCH_VERSION}" "torchvision==${TORCHVISION_VERSION}" \
        --index-url https://download.pytorch.org/whl/cu121
else
    echo "==> Installing PyTorch ${TORCH_VERSION} + torchvision ${TORCHVISION_VERSION} (CPU)"
    "$PIP" install --no-cache-dir \
        "torch==${TORCH_VERSION}" "torchvision==${TORCHVISION_VERSION}" \
        --index-url https://download.pytorch.org/whl/cpu
fi

if [ ! -f "$REQUIREMENTS_ML" ]; then
    echo "ERROR: $REQUIREMENTS_ML not found."
    echo "       Ensure the cloudforge repo is mounted at /opt/cloudforge (docker-compose volume)."
    exit 1
fi
echo "==> Installing ML packages from requirements-ml.txt"
"$PIP" install --no-cache-dir -r "$REQUIREMENTS_ML"

if ! "$PYTHON" -c "import detectron2" 2>/dev/null; then
    echo "==> Installing Detectron2 0.6 (build from source; may take several minutes)"
    "$PIP" install --no-cache-dir --no-build-isolation "${DETECTRON2_REF}"
else
    echo "==> Detectron2 already installed — skipping"
fi

# ── .bashrc auto-activation ───────────────────────────────────────────────────

BASHRC="/root/.bashrc"
MARKER="# cloudforge: activate default venv"

if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'EOF'

# cloudforge: activate default venv
[ -f "$HOME/.venv/bin/activate" ] && source "$HOME/.venv/bin/activate"
EOF
fi

echo ""
echo "Default venv ready at $VENV_DIR"
"$PYTHON" -c "import torch; print(f'  PyTorch {torch.__version__} (CUDA available: {torch.cuda.is_available()})')"
"$PYTHON" -c "import detectron2; print(f'  Detectron2 {detectron2.__version__}')"
"$PYTHON" -c "import cv2, rasterio; print(f'  OpenCV {cv2.__version__}, rasterio {rasterio.__version__}')"
echo ""
echo "For project repos, install web/app deps into a child venv:"
echo "  bash ${CLOUDFORGE_DIR}/scripts/install-project-venv.sh /data/projects/<repo>"
