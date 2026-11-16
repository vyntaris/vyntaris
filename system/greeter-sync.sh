#!/usr/bin/env bash
set -euo pipefail
# GREETER_SYNC_ROOT and VYNTARIS_JSON: where it works and the helper it uses, for tools/test-greeter-sync.sh
R="${GREETER_SYNC_ROOT:-}"
JSON="${VYNTARIS_JSON:-/usr/lib/vyntaris/json}"
user="$1"
home="$(getent passwd "$user" | cut -d: -f6)"
[ -n "$home" ] || exit 1
settings="$home/.config/quickshell/settings.json"

# Apps run as administrator (Timeshift) in the user's theme: a copy of the theme's names and colours only, made by
# root. Not the user's own folders: GTK reads modules from settings.ini, which would run the user's code as root.
root_theme() {
    local v d
    install -d -m700 "$R/root/.config"
    for v in gtk-3.0 gtk-4.0; do
        d="$R/root/.config/$v"
        [ -L "$d" ] && rm -f "$d"
        install -d -m755 "$d"
        { runuser -u "$user" -- cat -- "$home/.config/$v/settings.ini" 2>/dev/null || true; } |
            grep -E '^\[Settings\]$|^gtk-(theme-name|icon-theme-name|cursor-theme-name|cursor-theme-size|font-name|application-prefer-dark-theme)=[A-Za-z0-9 ._+-]*$' \
            > "$d/settings.ini.new" || true
        mv -f "$d/settings.ini.new" "$d/settings.ini"
        { runuser -u "$user" -- cat -- "$home/.config/$v/gtk.css" 2>/dev/null || true; } | grep -v '@import' > "$d/gtk.css.new" || true
        mv -f "$d/gtk.css.new" "$d/gtk.css"
    done
    [ -L "$R/root/.config/dconf" ] && rm -f "$R/root/.config/dconf"
    return 0
}
root_theme

g="$R/etc/greetd/greeter"
[ -d "$g" ] || exit 0

wp="$(runuser -u "$user" -- "$JSON" get "$settings" wallpaper.path "" 2>/dev/null || true)"
raw="$wp"
case "$wp" in
    ""|vyntaris:*|/usr/share/backgrounds/vyntaris/default.*)
        wp="$home/.cache/vyntaris/accent-wallpaper/current.jpg"
        runuser -u "$user" -- test -r "$wp" || wp="$R/usr/share/backgrounds/vyntaris/default.jpg" ;;
    heic:*) wp="${wp#heic:}" ;;
    times:*)
        have="${wp#times:}"; have="${have%%:*}"; wp="${wp#times:"$have":}"
        case ",$have," in *,day,*) when=day ;; *) when="${have%%,*}" ;; esac
        wp="${wp/\{t\}/$when}" ;;
esac
case "$wp" in \~/*) wp="$home/${wp#\~/}" ;; \~) wp="$home" ;; esac

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
dest=""
ext="${wp##*.}"; ext="${ext,,}"
case "$ext" in
    heic|heif) read_picture() { runuser -u "$user" -- magick "${wp}[0]" -quality 92 jpg:-; }; ext=jpg ;;
    *) read_picture() { runuser -u "$user" -- cat -- "$wp"; } ;;
esac
if [ -n "$wp" ] && read_picture > "$tmp" 2>/dev/null &&
   [[ "$(file -b --mime-type "$tmp")" == image/* ]]; then
    [[ "$ext" =~ ^(png|jpe?g|webp|svg|avif)$ ]] || ext=png
    rm -f "$g"/wallpaper.*
    install -m644 "$tmp" "$g/wallpaper.$ext"
    dest="$g/wallpaper.$ext"
fi
[ -n "$dest" ] || dest="$(ls "$g"/wallpaper.* 2>/dev/null | head -n1 || true)"

# A wallpaper that changes through the day: every picture, and when each one starts (minutes after midnight),
# for the greeter to pick from by the clock. The same schedule the desktop keeps.
dyn="$g/dynamic"
rm -rf "$dyn"
user_path() { case "$1" in \~/*) printf '%s' "$home/${1#\~/}" ;; *) printf '%s' "$1" ;; esac; }
case "$raw" in
    heic:*)
        src="$(user_path "${raw#heic:}")"
        work="$(mktemp -d)"
        chown "$user" "$work"
        if runuser -u "$user" -- "$JSON" heic-schedule "$src" > "$work/schedule.json" 2>/dev/null &&
           runuser -u "$user" -- nice -n 19 magick "$src" -quality 90 "$work/frame-%d.jpg" 2>/dev/null; then
            mkdir -p "$dyn"
            for f in "$work"/frame-*.jpg; do
                [[ "$(file -b --mime-type "$f")" == image/jpeg ]] && install -m644 "$f" "$dyn/${f##*/}"
            done
            [ "$(head -c 1 "$work/schedule.json")" = "[" ] && install -m644 "$work/schedule.json" "$dyn/schedule.json"
        fi
        rm -rf "$work" ;;
    times:*)
        have="${raw#times:}"; have="${have%%:*}"; pattern="$(user_path "${raw#times:"$have":}")"
        entries=()
        for t in morning day evening night; do
            case ",$have," in *,"$t",*) ;; *) continue ;; esac
            case "$t" in morning) m=360 ;; day) m=540 ;; evening) m=1080 ;; night) m=1230 ;; esac
            f="${pattern/\{t\}/$t}"; e="${f##*.}"; e="${e,,}"
            [[ "$e" =~ ^(png|jpe?g|webp|avif)$ ]] || continue
            runuser -u "$user" -- cat -- "$f" > "$tmp" 2>/dev/null && [[ "$(file -b --mime-type "$tmp")" == image/* ]] || continue
            mkdir -p "$dyn"
            install -m644 "$tmp" "$dyn/$t.$e"
            entries+=("{\"m\":$m,\"f\":\"$t.$e\"}")
        done
        [ ${#entries[@]} -gt 0 ] && (IFS=,; printf '[%s]' "${entries[*]}") > "$dyn/schedule.json" && chmod 644 "$dyn/schedule.json" ;;
esac
[ -f "$dyn/schedule.json" ] || rm -rf "$dyn"

face=""
if runuser -u "$user" -- head -c 10485761 -- "$home/.face" > "$tmp" 2>/dev/null &&
   [ "$(stat -c %s "$tmp")" -le 10485760 ] && [[ "$(file -b --mime-type "$tmp")" == image/* ]]; then
    install -m644 "$tmp" "$g/face"
    face="$g/face"
else
    rm -f "$g/face"
fi
full="$(getent passwd "$user" | cut -d: -f5 | cut -d, -f1)"

runuser -u "$user" -- cat -- "$settings" 2>/dev/null | "$JSON" greeter "$user" "$dest" "$face" "$full" > "$g/greeter.json.new"
mv "$g/greeter.json.new" "$g/greeter.json"
chmod 644 "$g/greeter.json"

splash="$R/usr/share/plymouth/themes/island"
if [ "$(plymouth-set-default-theme 2>/dev/null)" = island ]; then
    want="$("$JSON" splash "$g/greeter.json" 2>/dev/null || true)"
    if [ -n "$want" ] && [ "$want" != "$(cat "$splash/colours" 2>/dev/null)" ]; then
        systemctl stop 'vyntaris-splash-colours-*.timer' 2>/dev/null || true
        if [ -z "$(systemctl list-units --state=active --no-legend 'vyntaris-splash-colours-*.service')" ]; then
            systemd-run --quiet --collect --on-active=600 --unit="vyntaris-splash-colours-$(date +%s)" \
                --description="The boot splash in $user's colours" \
                sh -c 'while [ -e /var/lib/pacman/db.lck ]; do sleep 5; done
                       exec nice -n 19 ionice -c 3 /usr/bin/vyntaris-setup --splash --user "$1"' sh "$user" || true
        fi
    fi
fi
