#!/usr/bin/env bash
# 修改 project.yml 后在本目录执行，重新生成 YujieTTS.xcodeproj（须已安装 xcodegen）。
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "请先安装: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate
echo "OK: YujieTTS.xcodeproj 已更新"
