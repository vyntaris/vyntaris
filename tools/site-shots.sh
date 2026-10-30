#!/bin/bash
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
SITE="${SITE:-$R/../vyntaris-site}"
[ -d "$SITE/shots" ] || { echo "the website's repository isn't at $SITE (set SITE)" >&2; exit 1; }
S="${TMPDIR:-/tmp}/vyntaris-site"; mkdir -p "$S/nest"
Q=$R/config/quickshell
H=$S/home; O=$S/shots; rm -rf "$O"; mkdir -p "$O"
cat > "$S/nest/site.lua" <<'LUA'
hl.monitor({ output = "", mode = "1920x1080", position = "auto", scale = 1 })
hl.config({
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0,
             disable_watchdog_warning = true, enable_anr_dialog = false },
    debug = { suppress_errors = true },
    general = { gaps_in = 5, gaps_out = 8, border_size = 2, layout = "dwindle",
                col = { active_border = { colors = { "rgba(89b4faff)", "rgba(89b4fa40)" }, angle = 135 }, inactive_border = "rgba(313244cc)" } },
    decoration = { rounding = 10, rounding_power = 2, shadow = { enabled = false }, blur = { enabled = false } },
    animations = { enabled = false },
    input = { follow_mouse = 0 },
    cursor = { invisible = true },
})
hl.layer_rule({ name = "qs-no-anim", match = { namespace = "^quickshell" }, no_anim = true })
LUA
bus_dir="${XDG_RUNTIME_DIR:-/tmp}/vsite"; mkdir -p "$bus_dir"
cat > "$S/session.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:dir=$bus_dir</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>
CONF
rm -rf "$H"; mkdir -p "$H/.config/quickshell" "$H/.local/state/quickshell/by-shell/vyntaris" "$H/Pictures/Wallpapers" "$H/Documents" "$H/Downloads" "$H/Music" "$H/Videos"
cp ~/Pictures/Wallpapers/*.png "$H/Pictures/Wallpapers/" 2>/dev/null
cp /etc/skel/.zshrc /etc/skel/.zprofile "$H/" 2>/dev/null
touch "$H/.local/state/quickshell/by-shell/vyntaris/welcome-done"
mkdir -p "$H/.local/state/vyntaris"; for f in crashes-seen errors-seen; do echo $(( $(date +%s) * 1000000 )) > "$H/.local/state/vyntaris/$f"; done
python3 - "$H" <<'E'
import json,sys,os
h=sys.argv[1]
d=json.load(open(os.path.expanduser('~/.config/quickshell/settings.json')))
d['wallpaper']['path']=''; d['wallpaper']['directory']='~/Pictures/Wallpapers'
d.setdefault('theme',{}).update({'flavor':'mocha','accent':'blue'})
d['weather']={'enabled':True,'city':'Čačak','lat':43.89139,'lon':20.34972}
d['life']={'birthday':'1998-04-12','years':70}
d.setdefault('bar',{})['workspaceIcons']=True
json.dump(d,open(h+'/.config/quickshell/settings.json','w'),indent=2)
E
hyprctl eval 'hl.window_rule({ name = "vtest-nested", match = { class = "^aquamarine$" }, workspace = "special:vtest silent" })' >/dev/null
before="$(hyprctl instances -j | python3 -c "import json,sys;print(' '.join(i['instance'] for i in json.load(sys.stdin)))")"
(env -u HYPRLAND_INSTANCE_SIGNATURE Hyprland --config $S/nest/site.lua > $S/nest/log-site 2>&1 < /dev/null &); sleep 4
read -r sig wl < <(hyprctl instances -j | python3 -c "
import json,sys
before='$before'.split()
[print(i['instance'], i['wl_socket']) for i in json.load(sys.stdin) if i['instance'] not in before]")
[ -n "$sig" ] || { echo "no nested Hyprland"; exit 1; }
H_() { HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl "$@" >/dev/null; }
H_ output create headless SITE; sleep 0.5
H_ eval 'hl.monitor({ output = "SITE", mode = "1920x1080@60", position = "0x0", scale = 1 })'
H_ eval 'hl.monitor({ output = "WAYLAND-1", disabled = true })'
sleep 1
export WAYLAND_DISPLAY=$wl HYPRLAND_INSTANCE_SIGNATURE=$sig HOME=$H XDG_CONFIG_HOME=$H/.config XDG_CACHE_HOME=$H/.cache XDG_DATA_HOME=$H/.local/share XDG_STATE_HOME=$H/.local/state
ipc() { qs -p $Q ipc call "$@" >/dev/null 2>&1; }
shot() { sleep "${2:-1.5}"; timeout 10 grim "$O/$1.png" 2>>$S/nest/grim.log; echo "shot $1 rc=$?"; }
bus="$(dbus-daemon --config-file=$S/session.conf --fork --print-address=1 --print-pid=1)"
DBUS_SESSION_BUS_ADDRESS="$(echo "$bus" | head -1)"; export DBUS_SESSION_BUS_ADDRESS; buspid="$(echo "$bus" | sed -n 2p)"
awww-daemon > $S/nest/awww.log 2>&1 &
sleep 1
qs -p $Q > $S/nest/site-app.log 2>&1 &
sleep 14
shot desktop 0
ipc island open control; shot control 6
ipc island close; ipc launcher query "fi"; shot launcher 2
ipc island close; ipc island open sound; shot sound 2
ipc island close; ipc wallpaper toggle; shot wallpapers 4
ipc island close; ipc gamemode panel; shot gamemode 2
ipc island close; ipc nightlight panel; shot nightlight 2
ipc island close; ipc lock preview; shot lock 4; ipc lock preview; sleep 1
kitty sh -c 'fastfetch; exec zsh' >/dev/null 2>&1 & k=$!; sleep 3
vdoc >/dev/null 2>&1 & t=$!; sleep 5
shot tiling 1
kill $k $t 2>/dev/null; sleep 1
qs -p $Q/settings.qml >/dev/null 2>&1 & p=$!; sleep 2; qs -p $Q/settings.qml ipc call app open open "" >/dev/null 2>&1; shot settings 4; kill $p 2>/dev/null; sleep 1
B=$R/rust/target/release
for f in crashes-seen errors-seen; do echo $(( $(date +%s) * 1000000 )) > "$H/.local/state/vyntaris/$f"; done
VYNTARIS_DOCTOR=/usr/lib/vyntaris/doctor $B/vyntaris-health > $S/nest/doctor.log 2>&1 & p=$!; shot doctor 12; kill $p 2>/dev/null; sleep 1
$B/vyntaris-store > $S/nest/store.log 2>&1 & p=$!; shot store 14; kill $p 2>/dev/null; sleep 1
vsheet > $S/nest/vsheet.log 2>&1 & p=$!; shot office 8; kill $p 2>/dev/null; sleep 1
ipc welcome open; sleep 1; ipc welcome go 1; shot welcome 3; ipc welcome close; sleep 2
pid="$(hyprctl instances -j | python3 -c "import json,sys;[print(i['pid']) for i in json.load(sys.stdin) if i['instance']=='$sig']")"
pkill -f "qs -p $Q" ; [ -n "$pid" ] && kill "$pid"; kill "$buspid" 2>/dev/null
kill "$buspid" 2>/dev/null
cd "$O" && for f in *.png; do n=${f%.png}; magick "$f" -quality 84 "$SITE/shots/$n.webp"; magick "$f" -resize 960x -quality 80 "$SITE/shots/$n-960.webp"; done
for spec in control:540x900+690+0 sound:540x560+690+0 launcher:680x720+620+0 wallpapers:900x330+510+0 gamemode:560x300+680+0 nightlight:560x220+680+0; do
    magick "$O/${spec%%:*}.png" -crop "${spec#*:}" +repage -quality 88 "$SITE/shots/${spec%%:*}-panel.webp"
done
D="$SITE/shots"
magick "$R/config/quickshell/assets/wallpapers/default.jpg" -resize 1920x1080^ -gravity center -extent 1920x1080 -quality 86 "$D/xp-wall.webp"
magick "$O/control.png" -crop 1920x30+0+0 +repage -alpha set \( -size 1920x30 xc:white -fill black -draw "rectangle 719,0 1201,29" \) \
    -alpha off -compose CopyOpacity -composite -quality 92 "$D/xp-bar.webp"
magick "$O/control.png" -crop 483x749+719+0 +repage -quality 90 "$D/xp-island.webp"
magick "$O/tiling.png" -crop 948x1026+8+47 +repage -quality 90 "$D/xp-term.webp"
magick "$O/tiling.png" -crop 948x1026+965+47 +repage -quality 90 "$D/xp-doc.webp"
for n in lock doctor store office settings; do magick "$O/$n.png" -quality 88 "$D/xp-$n.webp"; done
for n in desk island-launcher control gallery-lock app-doctor app-store app-settings; do
    cp "$SITE/shots/$n.webp" "$R/docs/screenshots/" 2>/dev/null || true
done
echo "screenshots in $SITE/shots and docs/screenshots"
