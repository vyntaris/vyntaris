#!/bin/sh
# Text from a picture to the clipboard: ocr.sh FILE, or ocr.sh region COLOUR.
# 0 copied (prints it), 2 cancelled, 3 no text, 4 no tesseract.
command -v tesseract >/dev/null || exit 4
img=$(mktemp --suffix .png) || exit 1
trap 'rm -f "$img"' EXIT

if [ "$1" = region ]; then
    geom=$(slurp -d -b "#00000080" -s "#00000000" -c "$2" -w 2 </dev/null) || exit 2
    sleep 0.1
    grim -g "$geom" - | magick - -alpha off "$img" || exit 1
else
    magick "$1[0]" -background white -alpha remove -alpha off "$img" 2>/dev/null || exit 1
fi

# English and the system's language.
case "${LANG:-}" in
    sr_*@latin*) want=srp_latn ;; sr_*) want="srp srp_latn" ;; hr_*) want=hrv ;;
    de_*) want=deu ;; fr_*) want=fra ;; it_*) want=ita ;; pt_*) want=por ;; es_*) want=spa ;; pl_*) want=pol ;;
    *) want= ;;
esac
have=$(tesseract --list-langs 2>/dev/null)
langs=eng
for l in $want; do printf '%s\n' "$have" | grep -qx "$l" && langs="$l+$langs"; done

# Screen text is small for Tesseract, and dark themes are light on dark: bigger, grey, dark on light.
read -r w h dark <<EOF
$(magick "$img" -colorspace Gray -format "%w %h %[fx:mean<0.5]" info:)
EOF
grow=100%; [ "$w" -lt 2000 ] && [ "$h" -lt 2000 ] && grow=200%; [ "$w" -lt 1000 ] && [ "$h" -lt 1000 ] && grow=300%
neg=; [ "$dark" = 1 ] && neg=-negate
magick "$img" -colorspace Gray $neg -normalize -filter Lanczos -resize "$grow" "$img"

# Lines it isn't sure of (the half-cut ones at a region's edge) are left out.
text=$(tesseract "$img" - -l "$langs" --psm 4 tsv 2>/dev/null | awk -F '\t' '
    function flush() { if (n && sum / n >= 60) { if (para != last && out) print ""; print line; last = para; out = 1 } line = ""; n = sum = 0 }
    $1 == 4 { flush(); para = $3 "." $4 }
    $1 == 5 && $12 ~ /[^ ]/ { line = line (n ? " " : "") $12; n++; sum += $11 }
    END { flush() }')
[ -n "$text" ] || exit 3
printf '%s' "$text" | wl-copy
printf '%s\n' "$text"
