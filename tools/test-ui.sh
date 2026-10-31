#!/usr/bin/env bash
# The shell in a nested Hyprland with its own home, driven with a real pointer and keyboard.
# It needs a running Hyprland, so it runs on a desktop and not in CI. Pictures stay in the
# folder it names at the end, for looking at what no check can judge.
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$R/tools/test-ui.sh"
PANELS="control system battery media updates packages cloud night gamepanel sound awake apps power keyboard bluetooth phone capture privacy gpu timer wifi vpn launcher wallpaper overview"
BASE='"loginSound":"off","sounds":false,"syncApps":false'

check() {
    if [ "$2" = "$3" ]; then echo "  ok    $1"
    else echo "  FAIL  $1: wanted '$3', got '$2'"; echo "$1" >> "$S/failures"; fi
}
ipc() { qs -p "$Q/shell.qml" ipc call "$@" >> "$S/ipc.log" 2>&1; }
shot() { for _ in 1 2 3; do timeout 6 grim -o CHK "$S/shots/$1.png" && break; sleep 1; done; }
pointer() { "$S/ui-pointer" "$1" "$2" 1920 1080; }
click() { "$S/ui-pointer" "$1" "$2" 1920 1080 click; }
accent() { python3 -I -c "import json,sys;print(json.load(open(sys.argv[1]))['theme'].get('accent'))" "$H/.config/quickshell/settings.json"; }
on_screen() { awww query | grep -F 'CHK' | grep -F 'image: ' | sed 's/.*image: //; s|.*/||'; }
shots_taken() { find "$H/Pictures" -name '*.png' | wc -l; }

# Writes every picture the wallpaper daemon shows, so a wrong one can't slip by between looks.
watch_wallpaper() {
    local last="" now
    while :; do
        now="$(on_screen)"
        if [ -n "$now" ] && [ "$now" != "$last" ]; then echo "$now" >> "$S/shown"; last="$now"; fi
        sleep 0.05
    done
}

case_panels() {
    sleep 11
    local p
    for p in $PANELS; do ipc island open "$p"; sleep 1.6; shot "panel-$p"; ipc island close; sleep 0.4; done
    check "no panel failed to load" "$(grep -c "ERROR" "$S/shell.log")" 0
}

case_screenshot() {
    sleep 11
    ipc screenshot screen; sleep 1.3; shot menu
    check "a screenshot is saved" "$(shots_taken)" 1
    sleep 7; shot menu-gone

    ipc screenshot screen; sleep 1.3; click 1195 98; sleep 0.8
    check "Delete deletes it" "$(shots_taken)" 1

    ipc screenshot screen; sleep 1.3; click 1050 58; sleep 0.3; wtype -k End; wtype -- -named; wtype -k Return; sleep 0.8; shot renamed
    check "the name field renames it" "$(find "$H/Pictures" -name '*-named.png' | wc -l)" 1
    pointer 960 600; click 1243 16; sleep 0.8; shot menu-closed

    ipc screenshot region; sleep 1.2; wtype -k Escape; sleep 1.2
    check "cancelling saves nothing" "$(shots_taken)" 2

    ipc island open sound; sleep 1.5; ipc screenshot screen; sleep 1.4; shot menu-over-panel
    pointer 960 600; click 1243 16; sleep 0.8; shot panel-back
    ipc island close
}

case_pointer() {
    sleep 11
    ipc apps open; sleep 1.5; click 655 286; sleep 0.6; shot apps-category; wtype -k Escape; sleep 1
    ipc launcher open; sleep 1.5; click 850 117; sleep 0.6; shot launcher-category; wtype -k Escape; sleep 1
    ipc island open timer; sleep 1.5; click 955 130; sleep 0.6; shot timer-started; ipc island close; sleep 1
    ipc island open capture; sleep 1.5; click 900 85; sleep 2
    check "Capture's Screen takes a picture" "$(shots_taken)" 1
    sleep 7
}

case_accent() {
    magick -size 1280x720 xc:'#3a7a3a' "$S/green.png"
    magick -size 1280x720 xc:'#c23b3b' "$S/red.png"
    sleep 12
    ipc wallpaper set "$S/red.png"; sleep 3
    check "the accent follows the wallpaper" "$(accent)" "#c23b3b"
    ipc wallpaper set "$S/green.png"; sleep 3
    check "and follows it again" "$(accent)" "#3a7a3a"
    ipc wallpaper set "$Q/assets/wallpapers/default.jpg"; sleep 4
    check "the default wallpaper gives Mauve" "$(accent)" mauve
    check "and is shown as it is" "$(on_screen)" default.jpg
    sleep 5
    check "and it stays that way" "$(accent)" mauve
}

case_startup() {
    sleep 14
    kill "$QS"; sleep 2
    qs -p "$Q/shell.qml" >> "$S/shell.log" 2>&1 &
    QS=$!
    sleep 7
    check "only the right picture is shown at startup" "$(sort -u "$S/shown" | tr '\n' ' ')" "a6e3a1.jpg "
    check "the login screen gets the same picture" "$(cmp -s "$H/.cache/vyntaris/accent-wallpaper/current.jpg" "$H/.cache/vyntaris/accent-wallpaper/a6e3a1.jpg" && echo same)" same
}

if [ "${1:-}" = "--inside" ]; then
    S="$2"; Q="$S/q"; H="$S/home"; PID_AWWW=""
    awww-daemon > "$S/awww.log" 2>&1 &
    PID_AWWW=$!
    watch_wallpaper &
    PID_WATCH=$!
    qs -p "$Q/shell.qml" > "$S/shell.log" 2>&1 &
    QS=$!
    "case_$3"
    kill "$QS" "$PID_WATCH" "$PID_AWWW" 2>/dev/null
    sleep 1
    exit 0
fi

OUT="${1:-$(mktemp -d "${TMPDIR:-/tmp}/vyntaris-ui.XXXXXX")}"
mkdir -p "$OUT"
wayland-scanner client-header "$R/tools/ui-test/virtual-pointer.xml" "$OUT/virtual-pointer.h" || exit 1
wayland-scanner private-code "$R/tools/ui-test/virtual-pointer.xml" "$OUT/virtual-pointer-protocol.c" || exit 1
gcc -O1 -I"$OUT" "$R/tools/ui-test/pointer.c" "$OUT/virtual-pointer-protocol.c" -o "$OUT/ui-pointer" -lwayland-client || exit 1

# run NAME SECONDS SETTINGS
run() {
    local S="$OUT/$1" Q H sig wl pid before
    Q="$S/q"; H="$S/home"
    echo ":: $1"
    rm -rf "$S"; mkdir -p "$H/.config/quickshell" "$H/.config/qt6ct" "$H/.local/share" "$H/.local/state/quickshell/by-shell/vyntaris" "$H/Pictures" "$S/shots"
    cp "$OUT/ui-pointer" "$S/ui-pointer"
    cp -r "$R/config/quickshell" "$Q"
    grep -rl '/usr/share/backgrounds/vyntaris' "$Q/config" "$Q/modules" | xargs sed -i "s|/usr/share/backgrounds/vyntaris|$Q/assets/wallpapers|g"
    printf '%s\n' "$3" > "$H/.config/quickshell/settings.json"
    touch "$H/.local/state/quickshell/by-shell/vyntaris/welcome-done"
    ln -s "$HOME/.local/share/applications" "$H/.local/share/applications"
    ln -s "$HOME/.local/share/icons" "$H/.local/share/icons"
    printf '[Appearance]\nicon_theme=Vyntaris-Qt\nstyle=Fusion\n' > "$H/.config/qt6ct/qt6ct.conf"
    cat > "$S/nested.lua" <<'LUA'
hl.monitor({ output = "", mode = "1920x1080", position = "auto", scale = 1 })
hl.config({
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0,
             disable_watchdog_warning = true, enable_anr_dialog = false },
    debug = { suppress_errors = true },
    animations = { enabled = false },
})
LUA
    before="$(hyprctl instances -j | python3 -I -c "import json,sys;print(' '.join(i['instance'] for i in json.load(sys.stdin)))")"
    (env -u HYPRLAND_INSTANCE_SIGNATURE Hyprland --config "$S/nested.lua" > "$S/hyprland.log" 2>&1 < /dev/null &)
    sleep 4
    read -r sig wl pid < <(BEFORE="$before" hyprctl instances -j | BEFORE="$before" python3 -I -c "
import json,os,sys
[print(i['instance'], i['wl_socket'], i['pid']) for i in json.load(sys.stdin) if i['instance'] not in os.environ['BEFORE'].split()]")
    [ -n "${sig:-}" ] || { echo "  FAIL  no nested Hyprland"; echo nested >> "$OUT/failures"; return; }
    HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl output create headless CHK > /dev/null; sleep 0.5
    HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl eval 'hl.monitor({ output = "CHK", mode = "1920x1080@60", position = "0x0", scale = 1 })' > /dev/null
    HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl eval 'hl.monitor({ output = "WAYLAND-1", disabled = true })' > /dev/null
    sleep 1
    ( export WAYLAND_DISPLAY=$wl HYPRLAND_INSTANCE_SIGNATURE=$sig QT_QPA_PLATFORM=wayland GSETTINGS_BACKEND=memory QT_QPA_PLATFORMTHEME=qt6ct \
          HOME=$H XDG_CONFIG_HOME=$H/.config XDG_CACHE_HOME=$H/.cache XDG_DATA_HOME=$H/.local/share XDG_STATE_HOME=$H/.local/state XDG_PICTURES_DIR=$H/Pictures
      timeout "$2" dbus-run-session -- bash "$SELF" --inside "$S" "$1" > "$S/inside.log" 2>&1 ) < /dev/null
    grep -E '^  (ok|FAIL)' "$S/inside.log"
    sed 's/\x1b\[[0-9;]*m//g' "$S/shell.log" 2>/dev/null | grep -E ' ERROR|TypeError|ReferenceError|Unable to assign|binding loop|non-existent property|is not a type' | cut -c1-150 | sort -u > "$S/qml-errors"
    if [ -s "$S/qml-errors" ]; then echo "  FAIL  QML errors:"; sed 's/^/        /' "$S/qml-errors"; echo "$1 qml" >> "$OUT/failures"; fi
    [ -f "$S/failures" ] && cat "$S/failures" >> "$OUT/failures"
    kill "$pid" 2>/dev/null
    sleep 1
}

which="${2:-panels screenshot pointer accent startup}"
for c in $which; do
    case "$c" in
        panels) run panels 120 "{\"theme\":{$BASE},\"bar\":{\"notchStyle\":\"slant\"}}" ;;
        screenshot) run screenshot 90 "{\"theme\":{$BASE},\"bar\":{\"notchStyle\":\"slant\"}}" ;;
        pointer) run pointer 70 "{\"theme\":{$BASE},\"bar\":{\"notchStyle\":\"slant\"}}" ;;
        accent) run accent 70 "{\"theme\":{$BASE,\"wallpaperAccent\":true},\"bar\":{\"notchStyle\":\"slant\"}}" ;;
        startup) run startup 60 "{\"theme\":{$BASE,\"accent\":\"green\"},\"bar\":{\"notchStyle\":\"slant\"}}" ;;
    esac
done

echo "pictures: $OUT"
if [ -s "$OUT/failures" ]; then echo ":: $(wc -l < "$OUT/failures") failed"; exit 1; fi
echo ":: all fine"
