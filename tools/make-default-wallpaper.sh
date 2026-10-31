#!/usr/bin/env bash
# Makes the default wallpaper's files from the original picture (see THIRD-PARTY.md).
set -euo pipefail
source_picture="$1"
out="$(cd "$(dirname "$0")/.." && pwd)/config/quickshell/assets/wallpapers"
accent="#cba6f7"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

magick "$source_picture" -resize 3840x2160 -colorspace sRGB -depth 16 "$work/picture.png"
# The lights are the warm part of the picture; its background is a cool blue.
warm='mx=max(u.r,max(u.g,u.b)); mn=min(u.r,min(u.g,u.b)); dd=mx-mn;
      aa=abs(u.hue*360-30); ds=min(aa,360-aa); wh=1-max(0,min(1,(ds-115)/30));'
# base: the warmth becomes the floor's own cool tint, so none of it shows around the new colour.
magick "$work/picture.png" -fx "$warm channel(u.r+wh*(mx*0.83-u.r), u.g+wh*(mx*0.86-u.g), u.b+wh*(mx-u.b))" -depth 16 "$work/base.png"
# lights: how much of the colour goes where, as strong as the warmth was (0.33 is about an accent's saturation).
magick "$work/picture.png" -fx "$warm ws=max(0,min(1,(dd-0.004)/0.016)); wh*ws*min(1,dd/(max(mx,0.01)*0.33))" \
    -colorspace Gray -depth 16 "$work/lights.png"
# The floor's warmth is only a shade or two, too little to read pixel by pixel, so there it comes from a blurred
# picture: every grey warmer than the floor's blue turns to one cool tint, and the glow is one soft shape.
magick "$work/picture.png" -blur 0x24 -depth 16 "$work/smooth.png"
magick "$work/smooth.png" -fx "max(0,min(1,(u.r/max(u.b,0.01)-0.74)/0.08))" -colorspace Gray -blur 0x16 -depth 16 "$work/cool.png"
magick "$work/smooth.png" -fx "max(0,min(1,(u.r/max(u.b,0.01)-0.95)/0.25))" -colorspace Gray -blur 0x16 -depth 16 "$work/glow.png"
# Its grain goes too, or the glow would show it in colour; only smooth changes are blurred, so the shapes keep their edges.
magick "$work/picture.png" -selective-blur 0x8+3% -depth 16 "$work/quiet.png"
magick "$work/quiet.png" "$work/cool.png" -fx "mx=max(u.r,max(u.g,u.b)); channel(u.r+v.r*(mx*0.80-u.r), u.g+v.r*(mx*0.85-u.g), u.b+v.r*(mx-u.b))" -depth 16 "$work/floor-base.png"
# The floor starts below the lit cubes; the shapes standing on it are darker than it and keep their edges.
magick "$work/picture.png" -fx "max(0,min(1,(j-1480)/120))*max(0,min(1,(max(u.r,max(u.g,u.b))-0.06)/0.03))" -colorspace Gray -depth 16 "$work/floor.png"
magick "$work/base.png" "$work/floor-base.png" "$work/floor.png" -composite -sampling-factor 1x1 -quality 98 "$out/default-base.jpg"
magick "$work/lights.png" "$work/glow.png" "$work/floor.png" -composite \
    -colorspace Gray -depth 8 -define png:compression-level=9 "$out/default-lights.png"
"$(dirname "$0")/../config/quickshell/scripts/paint-wallpaper.sh" "$out/default-base.jpg" "$out/default-lights.png" "$accent" "$out/default.jpg"
