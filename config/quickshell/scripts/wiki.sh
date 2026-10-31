#!/bin/sh
# The Arch Wiki's offline pages (arch-wiki-docs).
# wiki.sh languages | pages LANG | theme FOLDER COLOURS RULES_FILE
root=/usr/share/doc/arch-wiki/html
case "$1" in
    languages)
        for d in "$root"/*/; do
            n=$(find "$d" -name '*.html' | wc -l)
            [ "$n" -gt 0 ] && printf '%s\t%s\n' "$(basename "$d")" "$n"
        done ;;
    pages)
        cd "$root/$2" && rg -m1 --no-heading --with-filename -o -r '$1' -g '*.html' '<title>([^<]*)</title>' . | sed 's|^\./||; s|\.html:|\t|; s| - ArchWiki$||' ;;
    theme)
        # Pages reach their stylesheet by a relative path, so a folder of links with its own one themes them.
        mkdir -p "$2" || exit 1
        for f in "$root"/*; do
            [ "$(basename "$f")" = ArchWikiOffline.css ] || ln -sfn "$f" "$2/$(basename "$f")"
        done
        ln -sfn "$root/ArchWikiOffline.css" "$2/original.css"
        { printf '@import url("original.css");\n%s\n' "$3"; cat "$4"; } > "$2/.css" && mv "$2/.css" "$2/ArchWikiOffline.css" ;;
esac
