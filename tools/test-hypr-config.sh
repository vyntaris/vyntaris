#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
LUA="$(command -v lua5.4 || command -v lua)"
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then echo "   ok    $what"; else echo "   FAIL  $what"; fails=$((fails + 1)); fi; }

config() {
    rm -rf "${T:?}/home"; mkdir -p "$T/home/.config/quickshell" "$T/home/.config/hypr"
    [ -n "$1" ] && printf '%s' "$1" > "$T/home/.config/quickshell/settings.json"
    [ -n "${2:-}" ] && printf '%s' "$2" > "$T/home/.config/hypr/user.lua"
    HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_RUNTIME_DIR="$T" "$LUA" "$REPO/tools/hypr-stub.lua" "$REPO/config/hypr" > "$T/out" 2>&1
}
bound() { grep -qxF "BIND=$1" "$T/out"; }
whole() { ! grep -q '^ERROR=' "$T/out" && [ "$(sed -n 's/^BINDS=//p' "$T/out")" -ge 100 ]; }
kinds() {
    HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" "$LUA" -e "
        package.path = '$REPO/config/hypr/?.lua;' .. package.path
        local s = require('lib.settings').load()
        local want = { theme = { flavor = 'string', accent = 'string', animationSpeed = 'number', cursorSize = 'number' },
            input = { kbLayout = 'string', sensitivity = 'number', naturalScroll = 'boolean' },
            apps = { terminal = 'string', browser = 'string' }, windows = { rounding = 'number' },
            display = { monitors = 'table' }, bar = { windowGap = 'number', corners = 'string' } }
        for g, keys in pairs(want) do
            assert(type(s[g]) == 'table', g)
            for k, t in pairs(keys) do assert(type(s[g][k]) == t, g .. '.' .. k .. ' is ' .. type(s[g][k])) end
        end
        assert(s.display.scale == 'auto' or (type(s.display.scale) == 'number' and s.display.scale >= 0.5 and s.display.scale <= 4), 'scale')
        for _, m in ipairs(s.display.monitors) do assert(m.scale == nil or m.scale == 'auto' or type(m.scale) == 'number', 'monitor scale') end
        for _, m in ipairs(s.display.monitors) do assert(m.transform == nil or m.transform == 1 or m.transform == 2 or m.transform == 3, 'monitor rotation') end
        assert(s.theme.animationSpeed >= 0, 'speed')
        assert(s.apps.terminal:match('%S'), 'terminal')
        for _, m in ipairs(s.display.monitors) do assert(type(m.name) == 'string' and m.name ~= '', 'monitor') end"
}

echo ":: settings.json"
config ""
check "none at all: the defaults"           whole
while IFS= read -r case; do
    [ -z "$case" ] && continue
    config "$case"
    check "whole with $case" whole
    check "… every setting of its kind"       kinds
done <<'CASES'
{bad json
null
[]
"x"
{"theme":"x","input":5,"apps":[],"windows":true,"display":"x","bar":null}
{"theme":{"flavor":5,"accent":{},"animationSpeed":"fast","cursorSize":"x"}}
{"theme":{"flavor":"nope","accent":"nope","animationSpeed":0,"cursorSize":100000}}
{"input":{"kbLayout":5,"kbLayout":"","sensitivity":"x","naturalScroll":"yes"}}
{"apps":{"terminal":5,"browser":"   "}}
{"windows":{"rounding":"big","gapsIn":-5,"border":null}}
{"display":{"scale":0,"monitors":[{"name":5},{"name":""},7,{"name":"DP-1","scale":"x","mode":3}]}}
{"display":{"monitors":{"name":"DP-1"}}}
{"display":{"scale":"auto","monitors":[{"name":"DP-1","scale":"auto"}]}}
{"display":{"scale":"huge","monitors":[{"name":"DP-1","scale":"big"}]}}
{"display":{"monitors":[{"name":"DP-1","transform":"x"},{"name":"DP-2","transform":9},{"name":"DP-3","transform":1.5}]}}
{"display":{"monitors":[{"name":"DP-1","color":"neon","bitdepth":12,"sdrBrightness":"x","icc":"../a.txt"},{"name":"DP-2","color":7,"icc":5}]}}
CASES
config '{"display":{"scale":"auto","monitors":[{"name":"DP-1","scale":"auto"}]}}'
check "Auto scale: Hyprland is asked for auto" eval '"$LUA" -e "package.path = [[$REPO/config/hypr/?.lua;]] .. package.path" -e "" >/dev/null; HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" "$LUA" -e "package.path = [[$REPO/config/hypr/?.lua;]] .. package.path; local s = require([[lib.settings]]).load(); assert(s.display.scale == [[auto]] and s.display.monitors[1].scale == [[auto]])"'
config '{"display":{"monitors":[{"name":"DP-1","transform":1},{"name":"DP-2","transform":7}]}}'
check "Rotation: 90 degrees kept, anything else dropped" eval 'HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" "$LUA" -e "package.path = [[$REPO/config/hypr/?.lua;]] .. package.path; local s = require([[lib.settings]]).load(); assert(s.display.monitors[1].transform == 1 and s.display.monitors[2].transform == nil)"'
config '{"display":{"monitors":[{"name":"DP-1","color":"hdr","sdrBrightness":9,"icc":"/home/a/m.icc"},{"name":"DP-2","color":"neon","bitdepth":12,"icc":"m.icc"}]}}'
check "Colors: HDR, brightness held to 3 and a full ICC path kept, the rest dropped" eval 'HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" "$LUA" -e "package.path = [[$REPO/config/hypr/?.lua;]] .. package.path; local s = require([[lib.settings]]).load(); local a, b = s.display.monitors[1], s.display.monitors[2]; assert(a.color == [[hdr]] and a.sdrBrightness == 3 and a.icc == [[/home/a/m.icc]] and b.color == nil and b.bitdepth == nil and b.icc == nil)"'
config '{"theme":{"animationSpeed":0}}'
check "Animations off: Hyprland's are off too"     grep -qxF ANIMATIONS=false "$T/out"
config '{"theme":{"animationSpeed":1}}'
check "Animations on: Hyprland's are on"           grep -qxF ANIMATIONS=true "$T/out"
config '{"theme":{"animationStyle":"calm","workspaceSlide":"vertical"}}'
check "Workspaces slide up and down when asked"    grep -qxF ANIM=workspaces:slidevert "$T/out"
config '{"theme":{"animationStyle":"snappy","workspaceSlide":"horizontal"}}'
check "… and sideways"                             grep -qxF ANIM=workspaces:slide "$T/out"
config '{"theme":{"animationStyle":"lift","workspaceSlide":""}}'
check "… else the style's own"                     grep -qxF ANIM=workspaces:slidevert "$T/out"
config ""
check "New install: up and down"                   grep -qxF ANIM=workspaces:slidevert "$T/out"
config '{"theme":{"workspaceSlide":"vertical"}}'
check "Swipe up and down when workspaces slide so" eval 'grep -qxF GESTURE=3:vertical:workspace "$T/out" && ! grep -q "GESTURE=3:horizontal" "$T/out"'
config '{"theme":{"workspaceSlide":"horizontal"}}'
check "… and sideways when they slide sideways"   eval 'grep -qxF GESTURE=3:horizontal:workspace "$T/out" && ! grep -q "GESTURE=3:vertical" "$T/out"'
echo ":: shortcuts"
config '{"shortcuts":{"SUPER + E":"SUPER + SHIFT + F"}}'
check "other keys: bound to them"            bound "SUPER + SHIFT + F"
check "… not to its own"                     eval '! bound "SUPER + E"'
check "… and written down for Help"          grep -q '"default":"SUPER + E","keys":"SUPER + SHIFT + F"' "$T/vyntaris-shortcuts.json"
check "… every one written down"             eval '[ "$(grep -c description "$T/vyntaris-shortcuts.json")" -ge 100 ]'
config '{"shortcuts":{"SUPER + E":""}}'
check "none: not bound"                      eval '! bound "SUPER + E"'
check "… still listed, off"                  grep -q '"default":"SUPER + E","keys":""' "$T/vyntaris-shortcuts.json"
config '{"shortcuts":{"SUPER + mouse:272":"SUPER + X"}}'
check "a mouse one stays"                    bound "SUPER + mouse:272"
for case in '{"shortcuts":5}' '{"shortcuts":{"SUPER + E":5}}' '{"shortcuts":["x"]}'; do
    config "$case"
    check "whole with $case"                 whole
    check "… its own keys"                   bound "SUPER + E"
done

config ""
printf '{"theme":{"flavor":"mocha"' > "$T/home/.config/quickshell/settings.json"
HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_RUNTIME_DIR="$T" "$LUA" "$REPO/tools/hypr-stub.lua" "$REPO/config/hypr" > "$T/out" 2>&1
check "a file cut short (a full disk): whole"  whole
check "… kept aside by the shell, and said"  grep -q '\.broken' "$REPO/config/quickshell/config/Config.qml"
check "nothing said in Hyprland's own notifications" bash -c "! grep -q 'hl.notification' '$REPO/config/hypr/hyprland.lua'"

echo ":: user.lua"
for u in 'this is not lua' 'error("boom")' 'local x = nil; x.y = 1' 'hl.bind()'; do
    config "{}" "$u"
    check "whole with: $u" whole
done
config "{}" 'error("boom")'
check "a mistake in it is said, in Vyntaris's notifications" grep -q "^NOTE=.*notify-send -a Vyntaris.*user.lua" "$T/out"

[ "$fails" -eq 0 ] && echo ":: all fine" || { echo ":: $fails failed"; exit 1; }
