#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$("$ROOT_DIR/Scripts/build-app.sh")"
SCREENSHOT_PATH="${1:-$ROOT_DIR/.build/chira-smoke.png}"

pkill -x Chira >/dev/null 2>&1 || true
open "$APP_DIR"
sleep 1.5

PID="$(pgrep -x Chira | head -n 1 || true)"
if [[ -z "$PID" ]]; then
    echo "Chira did not launch" >&2
    exit 1
fi

ps -o pid,comm,rss,%cpu,etime -p "$PID"

if command -v screencapture >/dev/null 2>&1; then
    screencapture -x "$SCREENSHOT_PATH"
    echo "Screenshot: $SCREENSHOT_PATH"
fi
