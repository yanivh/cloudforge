#!/bin/bash
# Link cloudforge parent ML venv into a project child venv via .pth (same pattern as
# 00_GUI/.venv/Lib/site-packages/_shared_ml.pth on Windows).
#
# Usage:
#   bash scripts/link-shared-ml-venv.sh /data/projects/<repo>/00_GUI/.venv
set -euo pipefail

CHILD_VENV="${1:-}"
PARENT_VENV="${PARENT_VENV:-/root/.venv}"

if [ -z "$CHILD_VENV" ]; then
    echo "Usage: $0 <path-to-child-venv>"
    echo "Example: $0 /data/projects/myapp/00_GUI/.venv"
    exit 1
fi

PYTHON_VERSION="$(python3.11 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PARENT_SITE="${PARENT_VENV}/lib/python${PYTHON_VERSION}/site-packages"
CHILD_SITE="${CHILD_VENV}/lib/python${PYTHON_VERSION}/site-packages"
PTH_FILE="${CHILD_SITE}/_shared_ml.pth"

if [ ! -d "$PARENT_SITE" ]; then
    echo "ERROR: Parent site-packages not found: $PARENT_SITE"
    echo "       Run bash start-dev.sh first to create the parent venv."
    exit 1
fi

mkdir -p "$CHILD_SITE"
echo "$PARENT_SITE" > "$PTH_FILE"
echo "Linked parent ML venv:"
echo "  $PTH_FILE -> $PARENT_SITE"
