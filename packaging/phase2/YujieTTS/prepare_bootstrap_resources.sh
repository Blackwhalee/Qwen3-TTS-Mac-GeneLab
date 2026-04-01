#!/usr/bin/env bash
# 将 build_env_pack.sh 产出复制进 App 资源，供 App Store 首启本地解压（避免用户依赖 GitHub）。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEST="$SCRIPT_DIR/YujieTTS/Resources/bootstrap"
DIST="$GENELAB_ROOT/dist"

mkdir -p "$DEST"
for f in yujie-python-env.tar.gz yujie-project-src.tar.gz; do
  if [[ ! -f "$DIST/$f" ]]; then
    echo "错误：缺少 $DIST/$f" >&2
    echo "请先在仓库根目录执行: bash packaging/phase2/scripts/build_env_pack.sh" >&2
    exit 1
  fi
  cp -f "$DIST/$f" "$DEST/"
  echo "已复制 $f"
done
echo "完成。请在 Xcode 中 Clean 后执行 Archive。"
