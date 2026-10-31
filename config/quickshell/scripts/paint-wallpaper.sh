#!/bin/sh
# paint-wallpaper.sh BASE LIGHTS COLOUR OUT: the default wallpaper with its lights in COLOUR.
exec magick "$1" \
    \( +clone -separate -evaluate-sequence Max -colorspace sRGB -type TrueColor \
       \( +clone -fill "$3" -colorize 100 \) -compose Multiply -composite \) \
    "$2" -compose Over -composite -sampling-factor 1x1 -quality 97 "$4"
