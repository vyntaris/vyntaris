#!/usr/bin/env bash
set -euo pipefail
user="$1"
home="$(getent passwd "$user" | cut -d: -f6)"
[ -n "$home" ] || exit 1
settings="$home/.config/quickshell/settings.json"
g=/etc/greetd/greeter
[ -d "$g" ] || exit 0

wp="$(runuser -u "$user" -- /usr/lib/vyntaris/json get "$settings" wallpaper.path "" 2>/dev/null || true)"
case "$wp" in \~/*) wp="$home/${wp#\~/}" ;; \~) wp="$home" ;; esac

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
dest=""
if [ -n "$wp" ] && runuser -u "$user" -- cat -- "$wp" > "$tmp" 2>/dev/null &&
   [[ "$(file -b --mime-type "$tmp")" == image/* ]]; then
    ext="${wp##*.}"; ext="${ext,,}"
    [[ "$ext" =~ ^(png|jpe?g|webp|svg|avif)$ ]] || ext=png
    rm -f "$g"/wallpaper.*
    install -m644 "$tmp" "$g/wallpaper.$ext"
    dest="$g/wallpaper.$ext"
fi
[ -n "$dest" ] || dest="$(ls "$g"/wallpaper.* 2>/dev/null | head -n1 || true)"

face=""
if runuser -u "$user" -- head -c 10485761 -- "$home/.face" > "$tmp" 2>/dev/null &&
   [ "$(stat -c %s "$tmp")" -le 10485760 ] && [[ "$(file -b --mime-type "$tmp")" == image/* ]]; then
    install -m644 "$tmp" "$g/face"
    face="$g/face"
else
    rm -f "$g/face"
fi
full="$(getent passwd "$user" | cut -d: -f5 | cut -d, -f1)"

runuser -u "$user" -- cat -- "$settings" 2>/dev/null | /usr/lib/vyntaris/json greeter "$user" "$dest" "$face" "$full" > "$g/greeter.json.new"
mv "$g/greeter.json.new" "$g/greeter.json"
chmod 644 "$g/greeter.json"

splash=/usr/share/plymouth/themes/island
if [ "$(plymouth-set-default-theme 2>/dev/null)" = island ]; then
    want="$(/usr/lib/vyntaris/json splash "$g/greeter.json" 2>/dev/null || true)"
    if [ -n "$want" ] && [ "$want" != "$(cat "$splash/colours" 2>/dev/null)" ]; then
        systemctl stop 'vyntaris-splash-colours-*.timer' 2>/dev/null || true
        if [ -z "$(systemctl list-units --state=active --no-legend 'vyntaris-splash-colours-*.service')" ]; then
            systemd-run --quiet --collect --on-active=60 --unit="vyntaris-splash-colours-$(date +%s)" \
                --description="The boot splash in $user's colours" \
                sh -c 'while [ -e /var/lib/pacman/db.lck ]; do sleep 5; done
                       exec nice -n 19 ionice -c 3 /usr/bin/vyntaris-setup --splash --user "$1"' sh "$user" || true
        fi
    fi
fi
