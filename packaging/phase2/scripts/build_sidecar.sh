#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_ROOT"

echo "========================================"
echo "  YujieTTS — Build Python Sidecar"
echo "========================================"

ENV_NAME="qwen3-tts-mac-genelab"
CONDA_PY="/opt/homebrew/Caskroom/miniforge/base/envs/${ENV_NAME}/bin/python3"

if [ ! -f "$CONDA_PY" ]; then
    echo "ERROR: conda env not found: $CONDA_PY"
    exit 1
fi

"$CONDA_PY" -m pip install pyinstaller --quiet 2>/dev/null || true

echo "[1/3] Cleaning …"
rm -rf build/sidecar dist/sidecar

echo "[2/3] Running PyInstaller …"
"$CONDA_PY" -m PyInstaller \
    --name yujie-engine \
    --onedir \
    --noconfirm \
    --clean \
    --distpath dist/sidecar \
    --workpath build/sidecar \
    --paths "$PROJECT_ROOT" \
    --hidden-import mac \
    --hidden-import mac.engine \
    --hidden-import mac.device_utils \
    --hidden-import mac.memory_manager \
    --hidden-import qwen_tts \
    --hidden-import mlx \
    --hidden-import mlx_audio \
    --hidden-import mlx_lm \
    --hidden-import transformers \
    --hidden-import safetensors \
    --hidden-import soundfile \
    --hidden-import scipy \
    --hidden-import numpy \
    --hidden-import uvicorn \
    --hidden-import uvicorn.logging \
    --hidden-import uvicorn.loops \
    --hidden-import uvicorn.loops.auto \
    --hidden-import uvicorn.protocols \
    --hidden-import uvicorn.protocols.http \
    --hidden-import uvicorn.protocols.http.auto \
    --hidden-import uvicorn.protocols.websockets \
    --hidden-import uvicorn.protocols.websockets.auto \
    --hidden-import uvicorn.lifespan \
    --hidden-import uvicorn.lifespan.on \
    --hidden-import fastapi \
    --hidden-import starlette \
    --hidden-import pydantic \
    --hidden-import pydantic_core \
    --hidden-import httpx \
    --hidden-import httpcore \
    --hidden-import anyio \
    --hidden-import cffi \
    --hidden-import _cffi_backend \
    --exclude-module torch \
    --exclude-module torchaudio \
    --exclude-module torchvision \
    --exclude-module matplotlib \
    --exclude-module PIL \
    --exclude-module tkinter \
    --exclude-module test \
    --exclude-module unittest \
    packaging/phase2/scripts/engine_server.py 2>&1 | tail -30

SIDECAR="dist/sidecar/yujie-engine"
if [ ! -d "$SIDECAR" ]; then
    echo "ERROR: sidecar build failed — $SIDECAR not found"
    exit 1
fi

echo "[3/3] Sidecar built: $SIDECAR"
echo "  Size: $(du -sh "$SIDECAR" | cut -f1)"
echo ""
echo "Copy into Xcode project Resources:"
echo "  cp -R $SIDECAR packaging/phase2/YujieTTS/YujieTTS/Resources/python-engine"
