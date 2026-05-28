#!/bin/bash
# Idempotent. Creates the default Python venv at /root/.venv (→ /data/home/.venv on EBS),
# installs PyTorch + base ML packages, and sets up .bashrc auto-activation.
# Runs INSIDE the container — called from start-dev.sh on first start.
set -euo pipefail

VENV_DIR="/root/.venv"

if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
    echo "==> Default venv already exists at $VENV_DIR — skipping"
    exit 0
fi

echo "==> Creating default Python venv at $VENV_DIR"
python3.11 -m venv "$VENV_DIR"

echo "==> Upgrading pip"
"$VENV_DIR/bin/pip" install --no-cache-dir --upgrade pip

echo "==> Installing PyTorch 2.1 + CUDA 11.8 (this may take several minutes)"
"$VENV_DIR/bin/pip" install --no-cache-dir \
    torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 \
    --index-url https://download.pytorch.org/whl/cu118

echo "==> Installing base ML tools"
"$VENV_DIR/bin/pip" install --no-cache-dir \
    numpy pandas matplotlib ipython jupyter

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
echo "  Activate manually:  source ~/.venv/bin/activate"
echo "  Or open a new shell — .bashrc activates it automatically"
