#!/usr/bin/env bash
set -euo pipefail
settings="${1:-}"
flavor="$(/usr/lib/vyntaris/json get "$settings" theme.flavor mocha)"
[ "$flavor" = latte ] && flavor=mocha
read -r top bottom < <(/usr/lib/vyntaris/json palette "$flavor" base crust)
tmp="$(mktemp -d)"
magick -size 3840x2160 "gradient:$top-$bottom" "PNG24:$tmp/wall.png"
for i in 0 1 2; do install -m644 "$tmp/wall.png" "/usr/share/hypr/wall$i.png"; done
rm -rf "$tmp"
grep -q '^NoExtract.*usr/share/hypr/wall' /etc/pacman.conf ||
    sed -i '/^\[options\]/a NoExtract = usr/share/hypr/wall*.png' /etc/pacman.conf
echo "   $top → $bottom"
