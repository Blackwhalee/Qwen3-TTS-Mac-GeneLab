#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_ROOT"

echo "========================================"
echo "  YujieTTS.app — Phase 1 Build (py2app)"
echo "========================================"

# --- 1. Conda ---
ENV_NAME="qwen3-tts-mac-genelab"
CONDA_PY="/opt/homebrew/Caskroom/miniforge/base/envs/${ENV_NAME}/bin/python3"

if [ ! -f "$CONDA_PY" ]; then
    echo "ERROR: conda env '${ENV_NAME}' not found at ${CONDA_PY}"
    exit 1
fi

echo "[1/4] Using Python: $CONDA_PY"

# --- 2. Ensure py2app is installed ---
"$CONDA_PY" -m pip install py2app --quiet 2>/dev/null || true

# --- 3. Clean previous build ---
echo "[2/4] Cleaning previous build …"
rm -rf build dist .eggs

# --- 4. Build ---
echo "[3/4] Running py2app …"
"$CONDA_PY" packaging/phase1/setup_py2app.py py2app 2>&1 | tail -40

# --- 5. Post-build fixups ---
echo "[4/4] Post-build fixups …"

APP="dist/launcher.app"
if [ ! -d "$APP" ]; then
    echo "ERROR: $APP not found after build"
    exit 1
fi

FINAL="dist/YujieTTS.app"
if [ "$APP" != "$FINAL" ]; then
    mv "$APP" "$FINAL"
fi

# Copy i18n resources if missing
RESOURCES="$FINAL/Contents/Resources"
if [ ! -d "$RESOURCES/ui/i18n" ]; then
    mkdir -p "$RESOURCES/ui/i18n"
    cp ui/i18n/*.json "$RESOURCES/ui/i18n/"
fi

# Copy yujie voice config
VOICE_DIR="$RESOURCES/default-voices"
mkdir -p "$VOICE_DIR"
if [ -f "$HOME/.openclaw/yujie-voice/config.json" ]; then
    cp "$HOME/.openclaw/yujie-voice/config.json" "$VOICE_DIR/yujie-config.json"
fi

echo ""
echo "BUILD COMPLETE: $FINAL"
echo "Size: $(du -sh "$FINAL" | cut -f1)"
echo ""
echo "To test:  open dist/YujieTTS.app"
echo "To sign:  bash packaging/phase1/sign_and_dmg.sh"
