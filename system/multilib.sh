#!/usr/bin/env bash
# Arch's 32-bit repository (multilib: Steam, Wine), turned on once. An admin who turns it off later keeps it off.
set -euo pipefail
conf="${1:-/etc/pacman.conf}"
once="${MULTILIB_ONCE:-/var/lib/vyntaris/multilib-once}"
[ -e "$once" ] && exit 0
if ! grep -q '^\[multilib\]' "$conf"; then
    if grep -q '^#\[multilib\]' "$conf"; then
        sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$conf"
    else
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> "$conf"
    fi
fi
mkdir -p "$(dirname "$once")"
: > "$once"
