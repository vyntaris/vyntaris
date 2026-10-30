#!/usr/bin/env bash
# Makes the default wallpaper's files from the original picture (see THIRD-PARTY.md).
set -euo pipefail
source_picture="$1"
out="$(cd "$(dirname "$0")/.." && pwd)/config/quickshell/assets/wallpapers"
accent="#cba6f7"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

magick "$source_picture" -resize 3840x2160 -colorspace sRGB "$work/picture.png"
# The lights are the warm part of the picture; its background is a cool blue.
warm='mx=max(u.r,max(u.g,u.b)); mn=min(u.r,min(u.g,u.b)); dd=mx-mn;
      aa=abs(u.hue*360-30); ds=min(aa,360-aa); wh=1-max(0,min(1,(ds-60)/30));'
# base: the picture with the warmth taken out, so none of it shows around the new colour.
magick "$work/picture.png" -channel RGB -fx "$warm u+wh*(mx-u)" -sampling-factor 1x1 -quality 92 "$out/default-base.jpg"
# lights: how much of the colour goes where, as strong as the warmth was (0.33 is about an accent's saturation).
magick "$work/picture.png" -fx "$warm ws=max(0,min(1,(dd-0.004)/0.016)); wh*ws*min(1,dd/(max(mx,0.01)*0.33))" \
    -colorspace Gray -depth 8 -define png:compression-level=9 "$out/default-lights.png"
magick "$out/default-base.jpg" \
    \( +clone -separate -evaluate-sequence Max -colorspace sRGB -type TrueColor \( +clone -fill "$accent" -colorize 100 \) -compose Multiply -composite \) \
    "$out/default-lights.png" -compose Over -composite -sampling-factor 1x1 -quality 92 "$out/default.jpg"
