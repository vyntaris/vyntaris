#!/usr/bin/env bash
set -euo pipefail
usage() {
    cat <<'USAGE'
Turns an existing Arch Linux system into Vyntaris: adds Vyntaris's package repository, installs the
desktop and its apps, then sets the system and you up. Run it as yourself; it asks for sudo.

  ./install.sh [--local] [--autologin] [--no-boot] [--no-aur] [--no-apps]
      --local      build the vyntaris package from this folder instead of downloading it
      --autologin  no login screen: log in on tty1 by yourself
      --no-boot    leave the boot as it is (no quiet boot, no splash)
      --no-aur     no AUR helper (yay)
      --no-apps    only the desktop, not the apps in packages.txt
USAGE
}
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://pkg.vyntarisos.com"

local_build=0; apps=1; setup_args=()
for arg in "$@"; do
    case "$arg" in
        --local) local_build=1 ;;
        --no-apps) apps=0 ;;
        --autologin|--no-boot|--no-aur) setup_args+=("$arg") ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done
[ "$(id -u)" -ne 0 ] || { echo "Run this as your normal user, not root." >&2; exit 1; }
command -v pacman >/dev/null || { echo "Vyntaris is built on Arch Linux: pacman not found." >&2; exit 1; }
step() { printf '\n\033[1;35m::\033[0m \033[1m%s\033[0m\n' "$*"; }

step "Vyntaris's package repository"
sudo "$REPO/system/pacman-candy.sh" /etc/pacman.conf
sudo pacman-key --add "$REPO/system/keyring/vyntaris.gpg" >/dev/null
sudo pacman-key --lsign-key "$(cut -d: -f1 "$REPO/system/keyring/vyntaris-trusted")" >/dev/null
if ! grep -q '^\[vyntaris\]' /etc/pacman.conf; then
    printf '\n# Vyntaris: the desktop and its updates\n[vyntaris]\nSigLevel = Required DatabaseOptional\nServer = %s\n' "$REPO_URL" |
        sudo tee -a /etc/pacman.conf >/dev/null
fi

step "The desktop"
sudo pacman -Sy --needed --noconfirm archlinux-keyring
if [ "$local_build" = 1 ]; then
    (cd "$REPO/pkg" && makepkg -sfi --noconfirm --needed)
else
    sudo pacman -Su --needed --noconfirm vyntaris
fi

if [ "$apps" = 1 ]; then
    step "Apps"
    mapfile -t packages < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$REPO/packages.txt" | grep -v '^$')
    sudo pacman -S --needed --noconfirm "${packages[@]}"
fi

sudo vyntaris-setup --user "$USER" "${setup_args[@]}"
vyntaris-user-setup

cat <<EOF

   Done. Restart: the login screen and the desktop come up as Vyntaris.
   This folder isn't needed any more: updates come with the system's (pacman -Syu, or the update panel).
EOF
