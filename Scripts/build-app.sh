#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/Chira.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

build_app_pids() {
    local executable="$MACOS_DIR/Chira"
    { pgrep -x Chira 2>/dev/null || true; } | while read -r pid; do
        local command_path
        command_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
        if [[ "$command_path" == "$executable" ]]; then
            echo "$pid"
        fi
    done
}

terminate_existing_build_app() {
    local pids
    pids="$(build_app_pids)"
    if [[ -z "$pids" ]]; then
        return
    fi

    while read -r pid; do
        [[ -n "$pid" ]] && kill "$pid" >/dev/null 2>&1 || true
    done <<< "$pids"

    for _ in 1 2 3 4 5; do
        [[ -z "$(build_app_pids)" ]] && break
        sleep 0.2
    done
}

GIT_SHA="unknown"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || printf unknown)"
    if ! git diff --quiet --ignore-submodules HEAD --; then
        GIT_SHA="${GIT_SHA}+"
    fi
fi

mkdir -p "$ROOT_DIR/.build/release"
clang \
    -fobjc-arc \
    -Wall \
    -Wextra \
    -O2 \
    -mmacosx-version-min=14.0 \
    -DCHIRA_GIT_SHA=\"${GIT_SHA}\" \
    -o "$ROOT_DIR/.build/release/Chira" \
    "$ROOT_DIR"/Sources/Chira/*.m \
    -framework AppKit \
    -framework ImageIO \
    -framework ServiceManagement

terminate_existing_build_app

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/Chira" "$MACOS_DIR/Chira"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

chmod +x "$MACOS_DIR/Chira"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
