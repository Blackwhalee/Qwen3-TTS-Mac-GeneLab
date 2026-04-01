#!/bin/bash
set -euo pipefail
#
# 构建时运行：将 conda 环境打包成可移植 tarball
# 产物：dist/yujie-python-env.tar.gz（约 1.5-2.5GB）
# 用户首次启动 app 时，会自动下载这个 tarball 并解压。
#
# 用法：bash packaging/phase2/scripts/build_env_pack.sh
#
# 打包前请用「当前 conda 环境」的 pip 安装本项目（勿用系统 pip）：
#   /path/to/env/bin/python -m pip uninstall qwen-tts-mac-genelab -y
#   /path/to/env/bin/python -m pip install /path/to/Qwen3-TTS-Mac-GeneLab
# 若 conda-pack 报 setuptools 与 pip 冲突，本脚本已加 --ignore-missing-files。
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DIST="$PROJECT_ROOT/dist"
ENV_NAME="qwen3-tts-mac-genelab"
OUTPUT="$DIST/yujie-python-env.tar.gz"

mkdir -p "$DIST"

echo "========================================"
echo "  Build Portable Python Environment"
echo "========================================"

# 1. Ensure conda-pack is installed
CONDA_BASE="$(conda info --base)"
source "$CONDA_BASE/etc/profile.d/conda.sh"
conda activate "$ENV_NAME"

pip install conda-pack --quiet 2>/dev/null || true

# 2. Pack (exclude unnecessary stuff to reduce size)
echo "[1/3] Packing conda environment '$ENV_NAME' …"
echo "       This may take several minutes."
#
# conda-pack 若报错「Cannot pack an environment with editable packages」：
# 在该环境中先去掉可编辑安装，例如：
#   conda activate $ENV_NAME
#   pip uninstall qwen_tts_mac_genelab -y   # 名称以 pip list 为准
#   cd \"\$PROJECT_ROOT\" && pip install .   # 非 -e 安装；或改用仅含依赖的干净环境
#
conda-pack \
    --name "$ENV_NAME" \
    --output "$OUTPUT" \
    --force \
    --ignore-missing-files \
    --exclude "*.pyc" \
    --exclude "__pycache__" \
    --exclude "*.egg-info" \
    --exclude "tests" \
    --exclude "test" \
    2>&1

echo "[2/3] Packing project source code …"
# Bundle the project's Python source into a separate tarball
SRC_TAR="$DIST/yujie-project-src.tar.gz"
cd "$PROJECT_ROOT"
tar czf "$SRC_TAR" \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='build' \
    --exclude='*.egg-info' \
    --exclude='docs' \
    --exclude='.github' \
    --exclude='examples' \
    --exclude='finetuning' \
    --exclude='assets' \
    mac/ ui/ qwen_tts/ \
    packaging/phase2/scripts/engine_server.py \
    packaging/phase1/model_manager.py

echo "[3/3] Done."
echo ""
echo "Outputs:"
echo "  Python env:    $OUTPUT ($(du -sh "$OUTPUT" | cut -f1))"
echo "  Project src:   $SRC_TAR ($(du -sh "$SRC_TAR" | cut -f1))"
echo ""
echo "Upload these to your hosting (GitHub Releases, S3, etc.)."
echo "Then set the download URLs in EnvironmentManager.swift."
