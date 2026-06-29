#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/Chira.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

mkdir -p "$ROOT_DIR/.build/release"
clang \
    -fobjc-arc \
    -Wall \
    -Wextra \
    -O2 \
    -mmacosx-version-min=14.0 \
    -o "$ROOT_DIR/.build/release/Chira" \
    "$ROOT_DIR"/Sources/Chira/*.m \
    -framework AppKit

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/Chira" "$MACOS_DIR/Chira"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

chmod +x "$MACOS_DIR/Chira"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
