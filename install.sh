#!/bin/bash
# install.sh — 把 dist/SysMonBar.app 複製到 /Applications 並開啟（build.sh 之後執行）
set -euo pipefail

APP_NAME="SysMonBar"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -d "dist/${APP_NAME}.app" ]]; then
  echo "❌ 找不到 dist/${APP_NAME}.app，請先執行 ./build.sh"
  exit 1
fi

echo "🚚 安裝到 /Applications ..."
rm -rf "/Applications/${APP_NAME}.app"
cp -R "dist/${APP_NAME}.app" "/Applications/${APP_NAME}.app"

echo "▶️  啟動 ${APP_NAME} ..."
open "/Applications/${APP_NAME}.app"

echo ""
echo "✅ 安裝完成！選單列應該已經出現。"
echo "💡 若要開機自動啟動：系統設定 > 一般 > 登入項目 > 加入 ${APP_NAME}"
echo "🗑  要移除的話，直接在選單裡按「解除安裝」，或執行 ./uninstall.sh"
