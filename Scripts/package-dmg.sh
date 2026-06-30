#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$("$ROOT_DIR/Scripts/build-app.sh")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist" 2>/dev/null || printf "0.1")"
DMG_PATH="$ROOT_DIR/.build/Chira-${VERSION}.dmg"
STAGING_DIR="$ROOT_DIR/.build/dmg"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/Chira.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "Chira ${VERSION}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
