#!/usr/bin/env bash
# 将解压到「应用支持目录」的 conda-pack Python 环境内所有 Mach-O 二进制用开发者证书签名，
# 以便随主 App 提交 Mac App Store（须先在 Xcode 登录 Apple ID、选好 Team）。
#
# 用法（示例）:
#   export SIGN_IDENTITY="Apple Distribution: Your Name (TEAMID)"
#   ./sign_python_env_for_appstore.sh "$HOME/Library/Containers/com.blackwhale.YujieTTS/Data/Library/Application Support/YujieTTS/python-env"
#
# 若环境仍在非沙盒路径:
#   ./sign_python_env_for_appstore.sh "$HOME/Library/Application Support/YujieTTS/python-env"
#
set -euo pipefail
ENV_ROOT="${1:?第一个参数为 python-env 目录绝对路径}"
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  echo "请设置 SIGN_IDENTITY，例如: export SIGN_IDENTITY=\"Apple Distribution: … (TEAMID)\"" >&2
  exit 1
fi

sign_one() {
  local f="$1"
  if file "$f" | grep -q "Mach-O"; then
    codesign --force --sign "$IDENTITY" --timestamp --options runtime "$f" || true
  fi
}

while IFS= read -r -d '' f; do
  sign_one "$f"
done < <(find "$ENV_ROOT" -type f -print0)

echo "Done. 请在 Xcode 对 .app 做 Archive → Validate → Distribute App → Mac App Store Connect。"
