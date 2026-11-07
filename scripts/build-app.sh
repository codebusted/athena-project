#!/bin/zsh
# Builds Athena.app (release) into ./build without needing Xcode, and the `athena` CLI next to it.
#   ./scripts/build-app.sh            → build/Athena.app + build/athena
#   ./scripts/build-app.sh --install  → also copies Athena.app to ~/Applications and athena to ~/.local/bin
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product AthenaApp
swift build -c release --product athena
BIN=$(swift build -c release --show-bin-path)

APP=build/Athena.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AthenaApp" "$APP/Contents/MacOS/Athena"
cp "$BIN/athena" build/athena

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Athena</string>
  <key>CFBundleDisplayName</key><string>Athena</string>
  <key>CFBundleIdentifier</key><string>com.athena.coach</string>
  <key>CFBundleExecutable</key><string>Athena</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Menu bar app: no Dock icon; one instance only. -->
  <key>LSUIElement</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Plain HTTP to the local Ollama server only. -->
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP and build/athena"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications ~/.local/bin
  pkill -x Athena 2>/dev/null || true
  rm -rf ~/Applications/Athena.app
  cp -R "$APP" ~/Applications/Athena.app
  cp build/athena ~/.local/bin/athena
  echo "Installed ~/Applications/Athena.app and ~/.local/bin/athena"
  echo "Launch with: open ~/Applications/Athena.app"
fi
