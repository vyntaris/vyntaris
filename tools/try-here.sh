#!/usr/bin/env bash
# Runs the desktop from this checkout without building or pushing anything: try-here.sh on | off.
# The shell looks in ~/.config/quickshell first, so a link there overrides the installed one until it's removed.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
link="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/vyntaris"
case "${1:-}" in
    on)
        if [ -e "$link" ] && [ ! -L "$link" ]; then echo "$link is a real folder, not touching it" >&2; exit 1; fi
        ln -sfn "$repo/config/quickshell" "$link"
        systemctl --user restart vyntaris-shell.service
        hyprctl eval 'hl.bind("SUPER + SHIFT + H", hl.dsp.exec_cmd("qs -c vyntaris ipc call wiki toggle"), { description = "Arch Wiki" })' >/dev/null || true
        echo "the desktop now runs from $repo/config/quickshell (back with: $0 off)" ;;
    off)
        [ -L "$link" ] && rm "$link"
        systemctl --user restart vyntaris-shell.service
        echo "the desktop runs from the installed package again" ;;
    *) echo "usage: $0 on|off" >&2; exit 2 ;;
esac
