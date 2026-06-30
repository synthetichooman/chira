#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$("$ROOT_DIR/Scripts/build-app.sh")"
SCREENSHOT_PATH="${1:-$ROOT_DIR/.build/chira-smoke.png}"

build_app_pids() {
    local executable="$APP_DIR/Contents/MacOS/Chira"
    { pgrep -x Chira 2>/dev/null || true; } | while read -r pid; do
        local command_path
        command_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
        if [[ "$command_path" == "$executable" ]]; then
            echo "$pid"
        fi
    done
}

other_chira_pids() {
    local executable="$APP_DIR/Contents/MacOS/Chira"
    { pgrep -x Chira 2>/dev/null || true; } | while read -r pid; do
        local command_path
        command_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
        if [[ "$command_path" != "$executable" ]]; then
            echo "$pid"
        fi
    done
}

while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" >/dev/null 2>&1 || true
done <<< "$(build_app_pids)"

for _ in 1 2 3 4 5; do
    [[ -z "$(build_app_pids)" ]] && break
    sleep 0.2
done

if [[ -n "$(other_chira_pids)" ]]; then
    echo "Another Chira instance is already running. Quit it before smoke-check." >&2
    exit 1
fi

if ! open "$APP_DIR"; then
    sleep 0.5
    open "$APP_DIR"
fi
sleep 1.5

PID="$(build_app_pids | head -n 1 || true)"
if [[ -z "$PID" ]]; then
    echo "Chira did not launch" >&2
    exit 1
fi

ps -o pid,comm,rss,%cpu,etime -p "$PID"

if command -v screencapture >/dev/null 2>&1; then
    screencapture -x "$SCREENSHOT_PATH"
    echo "Screenshot: $SCREENSHOT_PATH"
fi
