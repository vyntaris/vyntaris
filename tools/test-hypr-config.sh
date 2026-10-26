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
    HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" "$LUA" "$REPO/tools/hypr-stub.lua" "$REPO/config/hypr" > "$T/out" 2>&1
}
whole() { ! grep -q '^ERROR=' "$T/out" && [ "$(sed -n 's/^BINDS=//p' "$T/out")" -ge 100 ]; }
kinds() {
    HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" "$LUA" -e "
        package.path = '$REPO/config/hypr/?.lua;' .. package.path
        local s = require('lib.settings').load()
        local want = { theme = { flavor = 'string', accent = 'string', animationSpeed = 'number', cursorSize = 'number' },
            input = { kbLayout = 'string', sensitivity = 'number', naturalScroll = 'boolean' },
            apps = { terminal = 'string', browser = 'string' }, windows = { rounding = 'number', blur = 'boolean' },
            display = { scale = 'number', monitors = 'table' }, bar = { windowGap = 'number', corners = 'string' } }
        for g, keys in pairs(want) do
            assert(type(s[g]) == 'table', g)
            for k, t in pairs(keys) do assert(type(s[g][k]) == t, g .. '.' .. k .. ' is ' .. type(s[g][k])) end
        end
        assert(s.display.scale >= 0.5 and s.display.scale <= 4, 'scale')
        assert(s.theme.animationSpeed > 0, 'speed')
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
CASES
config ""
printf '{"theme":{"flavor":"mocha"' > "$T/home/.config/quickshell/settings.json"
HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" "$LUA" "$REPO/tools/hypr-stub.lua" "$REPO/config/hypr" > "$T/out" 2>&1
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
