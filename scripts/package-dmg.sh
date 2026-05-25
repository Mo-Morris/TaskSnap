#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>" >&2
    exit 64
fi

VERSION="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_ROOT="$(mktemp -d "/tmp/TaskSnap-release-${VERSION}.XXXXXX")"
STAGING_DIR="${RELEASE_ROOT}/staging"
APP_DIR="${STAGING_DIR}/TaskSnap.app"
DMG_PATH="${RELEASE_ROOT}/TaskSnap-${VERSION}.dmg"

cd "$REPO_ROOT"
swift build -c release

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${REPO_ROOT}/.build/release/TaskSnap" "${APP_DIR}/Contents/MacOS/TaskSnap"
chmod +x "${APP_DIR}/Contents/MacOS/TaskSnap"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TaskSnap</string>
    <key>CFBundleIdentifier</key>
    <string>com.momorris.tasksnap</string>
    <key>CFBundleName</key>
    <string>TaskSnap</string>
    <key>CFBundleDisplayName</key>
    <string>TaskSnap</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION#v}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION#v}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${TASKSNAP_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ln -s /Applications "${STAGING_DIR}/Applications"
hdiutil create -volname "TaskSnap ${VERSION}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "$DMG_PATH"
