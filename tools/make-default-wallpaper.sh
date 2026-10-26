#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
qml="$(command -v qml6 || command -v qml || echo /usr/lib/qt6/bin/qml)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen "$qml" tools/default-wallpaper.qml 2>&1 \
    | sed -n 's/^qml: SVG//p' > "$tmp/default.svg"
[ -s "$tmp/default.svg" ] || { echo "the drawing didn't come out" >&2; exit 1; }
rsvg-convert -w 2560 -h 1440 "$tmp/default.svg" -o config/quickshell/assets/wallpapers/default.png
echo "wrote config/quickshell/assets/wallpapers/default.png"
