#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TaskSnap.app"
SOURCE_APP="$(cd "$(dirname "$0")" && pwd)/${APP_NAME}"
DEST_APP="/Applications/${APP_NAME}"

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "未找到 ${APP_NAME}。请直接从 TaskSnap DMG 中运行这个安装脚本。"
    exit 1
fi

echo "正在安装 TaskSnap..."

osascript -e 'tell application "TaskSnap" to quit' >/dev/null 2>&1 || true
sleep 1

install_app() {
    rm -rf "$DEST_APP"
    ditto "$SOURCE_APP" "$DEST_APP"
    xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
}

if ! install_app 2>/tmp/tasksnap-install-error.log; then
    echo "需要管理员权限才能写入 /Applications。"
    sudo rm -rf "$DEST_APP"
    sudo ditto "$SOURCE_APP" "$DEST_APP"
    sudo xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
fi

echo "安装完成，正在启动 TaskSnap..."
open "$DEST_APP"

echo "完成。"
