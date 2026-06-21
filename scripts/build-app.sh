#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FanPilot"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

cd "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Helpers"

xcrun swiftc \
  -O \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/FanPilot/*.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework IOKit \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME"

xcrun swiftc \
  -O \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/FanPilotSMCProbe/*.swift \
  Sources/FanPilot/AppleSMCClient.swift \
  Sources/FanPilot/HardwareErrors.swift \
  Sources/FanPilot/Models.swift \
  Sources/FanPilot/SMCProbeRunner.swift \
  -framework IOKit \
  -o "$APP_DIR/Contents/Helpers/FanPilotSMCProbe"

if [[ -f "$ROOT_DIR/Resources/AppIcon.png" ]]; then
  NORMALIZED_ICON="$ROOT_DIR/build/AppIcon-1024.png"
  ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 1024 1024 "$ROOT_DIR/Resources/AppIcon.png" --out "$NORMALIZED_ICON" >/dev/null
  cp "$NORMALIZED_ICON" "$APP_DIR/Contents/Resources/AppIcon.png"
  sips -z 16 16 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$NORMALIZED_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$NORMALIZED_ICON" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.FanPilot</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>FanPilot</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>0.1.1</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR/Contents/Helpers/FanPilotSMCProbe" >/dev/null
codesign --force --sign - "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
