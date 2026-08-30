#!/bin/bash
# uninstall.sh — 完全移除 SysMonBar，不留殘留檔案
set -euo pipefail

APP_NAME="SysMonBar"

echo "🛑 結束 ${APP_NAME} ..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true

echo "🗑  刪除 /Applications/${APP_NAME}.app ..."
rm -rf "/Applications/${APP_NAME}.app"

echo "✅ 已完全移除，沒有殘留設定檔或背景服務。"
