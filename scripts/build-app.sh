#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/version.env"

APP_NAME="RunBar"
BUNDLE_ID="dev.runbar.app"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
ICON_SOURCE="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$ICON_SOURCE" ]]; then
  "$ROOT/scripts/build-icon.sh"
fi

echo "Building $APP_NAME ${MARKETING_VERSION} (${BUILD_NUMBER})…"
# --disable-sandbox: SwiftPM's sandbox-exec cannot nest inside Homebrew's build sandbox.
swift build --disable-sandbox -c release --product RunBar

BIN="$(swift build --disable-sandbox -c release --show-bin-path)/RunBar"
if [[ ! -x "$BIN" ]]; then
  echo "Release binary not found at $BIN" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN" "$MACOS/$APP_NAME"
cp "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

chmod +x "$MACOS/$APP_NAME"
codesign --force --sign - "$APP"

echo "Built $APP"
