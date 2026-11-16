#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../pkg"
rm -rf src pkg ./*.pkg.tar.*
makepkg -f --nodeps --noconfirm
# yay, the AUR helper the Store and updates build with, isn't in Arch's repositories: it's built here from the
# AUR's yay-bin and goes out in Vyntaris's repository with the rest, so every system has it from the start.
# Pinned to a commit someone read: a change on the AUR (anyone's push there) isn't signed with our key until the pin is
# moved. To move it: read `git -C <clone> diff <old>..<new>`, then put the new commit here.
YAY_BIN_COMMIT=a2812a593d4017a657bbedf98761db78072b5e4c
aur="$(mktemp -d)"; trap 'rm -rf "$aur"' EXIT
git clone -q https://aur.archlinux.org/yay-bin.git "$aur/yay-bin"
git -C "$aur/yay-bin" -c advice.detachedHead=false checkout -q "$YAY_BIN_COMMIT" ||
    { echo "yay-bin: the pinned commit $YAY_BIN_COMMIT isn't on the AUR any more" >&2; exit 1; }
(cd "$aur/yay-bin" && makepkg -f --nodeps --noconfirm >/dev/null)
cp "$aur"/yay-bin/yay-bin-[0-9]*.pkg.tar.zst .
# VWA is its own package, installed from the Store.
(cd vwa && rm -rf src pkg build ./*.pkg.tar.* && makepkg -f --nodeps --noconfirm >/dev/null)
cp vwa/vwa-[0-9]*.pkg.tar.zst .
ls -1 "$PWD"/vyntaris-*.pkg.tar.zst "$PWD"/yay-bin-*.pkg.tar.zst "$PWD"/vwa-*.pkg.tar.zst
