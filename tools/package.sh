#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../pkg"
rm -rf src pkg ./*.pkg.tar.*
makepkg -f --nodeps --noconfirm
ls -1 "$PWD"/vyntaris-*.pkg.tar.zst
