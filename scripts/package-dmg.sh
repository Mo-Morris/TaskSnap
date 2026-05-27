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

ICONSET_DIR="${RELEASE_ROOT}/AppIcon.iconset"
"${REPO_ROOT}/.build/release/TaskSnap" --export-iconset "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION#v}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION#v}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${TASKSNAP_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ln -s /Applications "${STAGING_DIR}/Applications"

TMP_DMG="${RELEASE_ROOT}/TaskSnap-${VERSION}.rw.dmg"
VOLUME_NAME="TaskSnap ${VERSION}"
hdiutil create -srcfolder "$STAGING_DIR" -volname "$VOLUME_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size 128m "$TMP_DMG"

MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")"
MOUNT_DIR="$(printf '%s\n' "$MOUNT_OUTPUT" | awk -F '\t' 'NF>=3 && $3 != "" { print $3; exit }')"

if [[ -z "$MOUNT_DIR" ]]; then
    echo "Failed to determine mount point for $TMP_DMG" >&2
    echo "$MOUNT_OUTPUT" >&2
    exit 1
fi

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 800, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 160
        set text size of viewOptions to 13
        set position of item "TaskSnap.app" of container window to {170, 200}
        set position of item "Applications" of container window to {470, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

cp "${APP_DIR}/Contents/Resources/AppIcon.icns" "${MOUNT_DIR}/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR" || true
SetFile -a V "${MOUNT_DIR}/.VolumeIcon.icns" || true

sync
hdiutil detach "$MOUNT_DIR"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$TMP_DMG"

echo "$DMG_PATH"
