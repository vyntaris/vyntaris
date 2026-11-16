#!/usr/bin/env bash
# The login screen and root's apps in step with the user's desktop (system/greeter-sync.sh), in a folder of its own:
# runuser, getent, plymouth and systemd are stand-ins, nothing runs as root.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$REPO/system/greeter-sync.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "   ok    $*"; }
no() { echo "   FAIL  $*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else no "$what"; fi; }

export VYNTARIS_JSON="${VYNTARIS_JSON:-$REPO/rust/target/release/vyntaris-json}"
[ -x "$VYNTARIS_JSON" ] || (cd "$REPO/rust" && cargo build -q --release -p vyntaris-json) || exit 1
R="$T/root-fs"; U="$T/home/ana"; G="$R/etc/greetd/greeter"
mkdir -p "$T/bin" "$G" "$U/.config/quickshell" "$U/.config/gtk-3.0" "$U/.config/gtk-4.0" "$U/.cache/vyntaris/accent-wallpaper" \
    "$R/root/.config" "$R/usr/share/backgrounds/vyntaris" "$R/usr/share/plymouth/themes/island"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/bin/$1"; chmod 755 "$T/bin/$1"; }
stub runuser 'while [ "$1" != -- ]; do shift; done; shift; exec "$@"'
stub getent "echo 'ana:x:1000:1000:Ana Anić,,,:$U:/bin/zsh'"
stub chown ':'
stub plymouth-set-default-theme 'echo "${FAKE_THEME:-island}"'
stub systemctl 'echo "systemctl $*" >> "'"$T"'/calls"'
stub systemd-run 'echo "systemd-run $*" >> "'"$T"'/calls"'
export PATH="$T/bin:$PATH" GREETER_SYNC_ROOT="$R"
png() { python3 -I -c '
import struct, sys, zlib
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
raw = b"".join(b"\0" + bytes([int(sys.argv[2]), 80, 200]) for _ in range(1))
sys.stdout.buffer.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))' "$1" "${2:-10}" > "$1"; }
sync() { : > "$T/calls"; "$SYNC" ana; }

echo ":: root's apps in the user's theme: names only, never the user's folders"
printf '[Settings]\ngtk-theme-name=adw-gtk3-dark\ngtk-modules=/home/ana/evil.so\ngtk-icon-theme-name=Vyntaris\ngtk-font-name=Inter 10;rm\ngtk-application-prefer-dark-theme=1\n' \
    > "$U/.config/gtk-3.0/settings.ini"
printf '@import url("/home/ana/x.css");\n@define-color accent_bg_color #cba6f7;\n' > "$U/.config/gtk-4.0/gtk.css"
ln -s "$U/.config/gtk-3.0" "$R/root/.config/gtk-3.0"   # how it was before: a link
ln -s "$U/.config" "$R/root/.config/dconf"
printf '{"theme":{"accent":"blue"}}' > "$U/.config/quickshell/settings.json"
sync
check "the old link is gone, a folder of root's"  test -d "$R/root/.config/gtk-3.0" -a ! -L "$R/root/.config/gtk-3.0"
check "the theme, icons and dark kept"            grep -qx 'gtk-theme-name=adw-gtk3-dark' "$R/root/.config/gtk-3.0/settings.ini"
check "… icons"                                   grep -qx 'gtk-icon-theme-name=Vyntaris' "$R/root/.config/gtk-3.0/settings.ini"
check "gtk-modules left out (the user's code as root)" bash -c '! grep -q gtk-modules "$0"' "$R/root/.config/gtk-3.0/settings.ini"
check "a value with odd characters left out"      bash -c '! grep -q gtk-font-name "$0"' "$R/root/.config/gtk-3.0/settings.ini"
check "the colours kept, @import left out"        grep -q accent_bg_color "$R/root/.config/gtk-4.0/gtk.css"
check "… @import"                                 bash -c '! grep -q @import "$0"' "$R/root/.config/gtk-4.0/gtk.css"
check "dconf no longer linked"                    test ! -e "$R/root/.config/dconf"

echo ":: the login screen: wallpaper, face, name, colours"
png "$R/usr/share/backgrounds/vyntaris/default.jpg"
sync
check "no wallpaper set: the default one"         cmp -s "$R/usr/share/backgrounds/vyntaris/default.jpg" "$G"/wallpaper.*
png "$U/.cache/vyntaris/accent-wallpaper/current.jpg" 99
sync
check "… or its accent version when there is one" cmp -s "$U/.cache/vyntaris/accent-wallpaper/current.jpg" "$G/wallpaper.jpg"
png "$U/mine.png" 50
printf '{"wallpaper":{"path":"~/mine.png"},"theme":{"accent":"green","flavor":"latte"}}' > "$U/.config/quickshell/settings.json"
sync
check "the user's own, ~ meaning their home"      cmp -s "$U/mine.png" "$G/wallpaper.png"
check "… the old one gone"                        test ! -e "$G/wallpaper.jpg"
printf 'not a picture' > "$U/fake.png"
printf '{"wallpaper":{"path":"%s"}}' "$U/fake.png" > "$U/.config/quickshell/settings.json"
sync
check "something that isn't a picture: the last one stays" cmp -s "$U/mine.png" "$G/wallpaper.png"
check "greeter.json: who, and the full name"      grep -q '"fullName": *"Ana Anić"' "$G/greeter.json"
check "… the wallpaper it shows"                  grep -q "\"wallpaper\": *\"$G/wallpaper.png\"" "$G/greeter.json"
check "… readable by the login screen"            test "$(stat -c %a "$G/greeter.json")" = 644
png "$U/.face" 30
sync
check "the face picture"                          cmp -s "$U/.face" "$G/face"
head -c 10485770 /dev/zero > "$U/.face"
sync
check "a face over 10 MB: not copied"             test ! -e "$G/face"

echo ":: a wallpaper that changes through the day"
png "$U/day.png" 1; png "$U/night.png" 2
printf '{"wallpaper":{"path":"times:day,night:~/{t}.png"}}' > "$U/.config/quickshell/settings.json"
sync
check "each picture"                              test -f "$G/dynamic/day.png" -a -f "$G/dynamic/night.png"
check "… and when it starts"                      grep -q '{"m":540,"f":"day.png"},{"m":1230,"f":"night.png"}' "$G/dynamic/schedule.json"
printf '{"wallpaper":{"path":"~/mine.png"}}' > "$U/.config/quickshell/settings.json"
sync
check "back to one picture: no schedule left"     test ! -e "$G/dynamic"

echo ":: the boot splash follows, later and once"
printf '{"theme":{"accent":"red"}}' > "$U/.config/quickshell/settings.json"
echo "mocha mauve" > "$R/usr/share/plymouth/themes/island/colours"
sync
check "new colours: rebuilt in 10 min"            grep -q 'systemd-run .*--on-active=600' "$T/calls"
echo "mocha red" > "$R/usr/share/plymouth/themes/island/colours"
sync
check "the same colours: nothing"                 bash -c '! grep -q systemd-run "$0"' "$T/calls"
printf '{"theme":{"accent":"#d29bf0","wallpaperAccent":true}}' > "$U/.config/quickshell/settings.json"
echo "mocha mauve" > "$R/usr/share/plymouth/themes/island/colours"
sync
check "an accent from the wallpaper, close to mauve: nothing" bash -c '! grep -q systemd-run "$0"' "$T/calls"
FAKE_THEME=bgrt sync
check "another splash theme: not touched"         bash -c '! grep -q systemd-run "$0"' "$T/calls"

echo ":: no login screen (autologin)"
rm -rf "$R/etc/greetd" "$R/root/.config/gtk-3.0"
sync
check "root's theme still made"                   test -f "$R/root/.config/gtk-3.0/settings.ini"
check "nothing else"                              test ! -e "$R/etc/greetd"

echo
[ "$fails" = 0 ] && echo "greeter-sync: all checks passed" || echo "greeter-sync: $fails failed"
exit $((fails > 0))
