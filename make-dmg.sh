#!/bin/bash
# make-dmg.sh — 把 dist/SysMonBar.app 打包成經典「拖進 Applications」安裝映像檔
# 適合放到 GitHub Releases 讓其他人下載。
set -euo pipefail

APP_NAME="SysMonBar"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -d "dist/${APP_NAME}.app" ]]; then
  echo "❌ 找不到 dist/${APP_NAME}.app，請先執行 ./build.sh"
  exit 1
fi

STAGING="dist/dmg-staging"
DMG_PATH="dist/${APP_NAME}.dmg"

echo "📀 準備 DMG 內容 ..."
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "dist/${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "📀 產生 ${DMG_PATH} ..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null

rm -rf "$STAGING"

echo ""
echo "✅ 完成：${DMG_PATH}"
echo "   打開後把 ${APP_NAME}.app 拖進 Applications 捷徑即可安裝，可直接上傳到 GitHub Releases。"
