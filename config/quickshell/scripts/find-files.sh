#!/bin/sh
q="$1" what="${2:-both}" limit="${3:-20}"
[ -n "$q" ] || exit 0
if [ "$what" != contents ]; then
    find "$HOME" -xdev -maxdepth 6 \( -name ".*" -o -name node_modules -o -name target \) -prune \
        -o -iname "*$q*" -printf "%y %p\n" 2>/dev/null | sed 's/^\([^d]\) /f /' | head -n "$limit"
fi
if [ "$what" != names ] && [ "${#q}" -ge 3 ]; then
    /usr/lib/vyntaris/doc-index search "$q" "$limit" 2>/dev/null | cut -f1 | sed 's/^/c /'
    if command -v rg >/dev/null; then
        timeout 3 rg -l -i -F --max-filesize 4M --max-depth 8 --max-count 1 -- "$q" "$HOME" 2>/dev/null
    else
        timeout 3 grep -rIl -i -F -m 1 --exclude-dir='.*' --exclude-dir=node_modules -- "$q" "$HOME" 2>/dev/null
    fi | head -n "$limit" | sed 's/^/c /'
fi
