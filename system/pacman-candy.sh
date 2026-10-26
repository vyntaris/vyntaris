#!/usr/bin/env bash
set -euo pipefail
conf="${1:-/etc/pacman.conf}"
SUDO=""; [ -w "$conf" ] || SUDO=sudo
if grep -q '^#\?Color' "$conf"; then
    $SUDO sed -i 's/^#\?Color.*/Color/' "$conf"
else
    $SUDO sed -i '/^\[options\]/a Color' "$conf"
fi
grep -q '^ILoveCandy' "$conf" || $SUDO sed -i '/^Color$/a ILoveCandy' "$conf"
