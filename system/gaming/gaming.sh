#!/usr/bin/env bash
set -euo pipefail
usage() {
    cat <<'USAGE'
Games, ready: Steam (with Proton), Lutris, GameMode, MangoHud, Gamescope and Wine, with the 32-bit
graphics drivers older games need.

  gaming --setup     (root) all of it, with the system brought up to date (Steam needs multilib, turned on)
  gaming --status    what's there, as JSON
USAGE
}
CONF="${GAMING_PACMAN_CONF:-/etc/pacman.conf}"
PACKAGES=(steam lutris gamemode lib32-gamemode mangohud lib32-mangohud gamescope wine
          vulkan-icd-loader lib32-vulkan-icd-loader ttf-liberation)

multilib_on() { grep -q '^\[multilib\]' "$CONF"; }

multilib() {
    multilib_on && return 0
    if grep -q '^#\[multilib\]' "$CONF"; then
        sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$CONF"
    else
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> "$CONF"
    fi
    multilib_on
}

status() {
    local have=()
    for p in steam lutris mangohud gamemode; do pacman -Q "$p" >/dev/null 2>&1 && have+=("\"$p\""); done
    printf '{"multilib": %s, "installed": [%s]}\n' "$(multilib_on && echo true || echo false)" "$(IFS=,; echo "${have[*]}")"
}

T() { /usr/lib/vyntaris/json tr "$@" 2>/dev/null || printf '%s' "$1"; }

setup() {
    [ "$(id -u)" -eq 0 ] || { echo "run this with sudo" >&2; exit 1; }
    echo ":: Arch's 32-bit repository (multilib)"
    multilib
    echo ":: Steam, Lutris, GameMode, MangoHud, Gamescope, Wine (and the system brought up to date)"
    pacman -Syu --needed --noconfirm "${PACKAGES[@]}"
    echo ":: The 32-bit graphics drivers"
    /usr/lib/vyntaris/drivers --install
    echo
    T "Games are ready: Steam and Lutris are in the launcher. Restart once if the graphics driver was updated."
}

case "${1:-}" in
    --setup) setup ;;
    --status) status ;;
    --multilib) multilib ;;
    *) usage >&2; exit 2 ;;
esac
