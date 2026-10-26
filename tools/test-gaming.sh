#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then echo "   ok    $what"; else echo "   FAIL  $what"; fails=$((fails + 1)); fi; }

echo ":: multilib"
cat > "$T/pacman.conf" <<'CONF'
[core]
Include = /etc/pacman.d/mirrorlist

#[multilib-testing]
#Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
CONF
GAMING_PACMAN_CONF="$T/pacman.conf" "$REPO/system/gaming/gaming.sh" --multilib
check "Arch's commented-out block, turned on" grep -qzP '\n\[multilib\]\nInclude = /etc/pacman.d/mirrorlist' "$T/pacman.conf"
check "… not the testing one"                 grep -q '^#\[multilib-testing\]' "$T/pacman.conf"
cp "$T/pacman.conf" "$T/before"
GAMING_PACMAN_CONF="$T/pacman.conf" "$REPO/system/gaming/gaming.sh" --multilib
check "a second time changes nothing"         cmp -s "$T/pacman.conf" "$T/before"
printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n' > "$T/bare.conf"
GAMING_PACMAN_CONF="$T/bare.conf" "$REPO/system/gaming/gaming.sh" --multilib
check "a pacman.conf without it gets it"      grep -q '^\[multilib\]' "$T/bare.conf"

echo ":: what the island shows"
stats() { GAME_STATS_SYS="$T/sys" "$REPO/system/gaming/game-stats.sh" "$T/logs"; }
mkdir -p "$T/logs" "$T/sys/class/hwmon/hwmon0" "$T/sys/class/hwmon/hwmon1" "$T/sys/bus/pci/devices"
echo k10temp > "$T/sys/class/hwmon/hwmon0/name"; echo 71500 > "$T/sys/class/hwmon/hwmon0/temp1_input"
echo amdgpu > "$T/sys/class/hwmon/hwmon1/name"; echo 64000 > "$T/sys/class/hwmon/hwmon1/temp1_input"
check "no game: the sensors"                  test "$(stats)" = "- 72 64 -"
header="os,cpu,gpu\nfps,frametime,cpu_load,cpu_power,gpu_load,cpu_temp,gpu_temp,gpu_core_clock"
printf "$header\n%s\n" "60.2,16.6,30,15,40,55,50,1500" > "$T/logs/steam_2026-10-13_17-00-00.csv"
printf "$header\n%s\n%s\n" "120,8.3,50,20,90,70,66,1800" "143.6,6.9,52,21,97,73,68,1900" > "$T/logs/eldenring.exe_2026-10-13_17-05-00.csv"
printf "summary\n" > "$T/logs/eldenring.exe_2026-10-13_17-05-00_summary.csv"
check "a game with MangoHud: the newest row of the game started last" test "$(stats)" = "144 73 68 97"
touch -d '-1 minute' "$T/logs/eldenring.exe_2026-10-13_17-05-00.csv"
check "a log no longer written to: the one still running" test "$(stats)" = "60 55 50 40"
touch -d '-20 minutes' "$T/logs/"*.csv
stats >/dev/null
check "logs of games long over are deleted"   test -z "$(ls "$T/logs")"

echo
[ "$fails" = 0 ] && echo "gaming: all checks passed" || echo "gaming: $fails failed"
exit $((fails > 0))
