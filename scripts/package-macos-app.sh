#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Litebar"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
ZIP_PATH="$DIST_DIR/${APP_NAME}.app.zip"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
fi
if [[ -z "$VERSION" ]]; then
  echo "Version is required. Pass as first argument, e.g. scripts/package-macos-app.sh 0.1.2"
  exit 1
fi

echo "[1/4] Building release binary"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "[2/4] Assembling app bundle"
rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

if [[ -d "$BIN_DIR/Litebar_Litebar.bundle" ]]; then
  cp -R "$BIN_DIR/Litebar_Litebar.bundle" "$APP_DIR/Contents/Resources/"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Litebar</string>
  <key>CFBundleIdentifier</key>
  <string>com.buddyh.litebar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Litebar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "[3/4] Ad-hoc signing app bundle"
codesign --force --deep --sign - "$APP_DIR"

echo "[4/4] Creating zip archive"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Created: $ZIP_PATH"
echo "SHA256: $(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
