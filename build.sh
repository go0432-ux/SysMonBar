#!/bin/bash
# build.sh — 編譯 SysMonBar 並在 dist/ 產生一個標準的 .app（可直接拖進 /Applications）
set -euo pipefail

APP_NAME="SysMonBar"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 編譯 ${APP_NAME} (Release，最佳化)..."
swift build -c release

BIN_PATH=".build/release/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "❌ 找不到編譯後的執行檔：$BIN_PATH"
  exit 1
fi

echo "📦 打包成 .app ..."
rm -rf "dist"
mkdir -p "dist/${APP_NAME}.app/Contents/MacOS"
mkdir -p "dist/${APP_NAME}.app/Contents/Resources"
cp "$BIN_PATH" "dist/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

if [[ -d "Resources" ]]; then
  echo "🌐 複製多國語言資源 ..."
  cp -R Resources/*.lproj "dist/${APP_NAME}.app/Contents/Resources/" 2>/dev/null || true
fi

cat > "dist/${APP_NAME}.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.sysmonbar</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hant</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hant</string>
        <string>zh-Hans</string>
    </array>
</dict>
</plist>
PLIST

echo "✍️  Ad-hoc code signing（讓本機可以直接開啟，不需要開發者憑證）..."
codesign --force --deep --sign - "dist/${APP_NAME}.app"

echo ""
echo "✅ 完成！輸出在 dist/${APP_NAME}.app"
echo ""
echo "接下來可以："
echo "  1) 直接把 dist/${APP_NAME}.app 拖進「應用程式」(Applications) 資料夾"
echo "  2) 或執行 ./install.sh 自動幫你複製過去並開啟"
echo "  3) 或執行 ./make-dmg.sh 產生可分享的安裝映像檔 (.dmg)"
echo ""
echo "🌐 語言會依照系統設定（系統設定 > 一般 > 語言與地區）自動切換：正體中文／简体中文／English"
