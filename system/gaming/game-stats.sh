#!/usr/bin/env bash
set -uo pipefail
dir="${1:-${XDG_RUNTIME_DIR:-/tmp}/vyntaris-mangohud}"
sys="${GAME_STATS_SYS:-/sys}"

int() { [[ "${1:-}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && printf '%.0f' "$1" || printf -- -; }

log="" started=""
now="$(date +%s)"
for f in "$dir"/*.csv; do
    [ -f "$f" ] || continue
    [[ "$f" == *_summary.csv ]] && continue
    (( now - $(stat -c %Y "$f") <= 4 )) || continue
    s="${f: -23:19}"
    if [[ -z "$started" || "$s" > "$started" ]]; then started="$s"; log="$f"; fi
done
find "$dir" -maxdepth 1 -name '*.csv' -mmin +10 -delete 2>/dev/null

if [ -n "$log" ]; then
    IFS=, read -r fps _ _ _ load ctemp gtemp _ < <(tail -n1 "$log")
    echo "$(int "$fps") $(int "$ctemp") $(int "$gtemp") $(int "$load")"
    exit 0
fi

cpu="" gpu="" load=""
for h in "$sys"/class/hwmon/hwmon*; do
    case "$(cat "$h/name" 2>/dev/null)" in
        k10temp|coretemp|zenpower) [ -z "$cpu" ] && cpu="$(( ($(cat "$h/temp1_input" 2>/dev/null || echo 0) + 500) / 1000 ))" ;;
        amdgpu) [ -z "$gpu" ] && gpu="$(( ($(cat "$h/temp1_input" 2>/dev/null || echo 0) + 500) / 1000 ))" ;;
    esac
done
for d in "$sys"/bus/pci/devices/*; do
    [ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] && [[ "$(cat "$d/class" 2>/dev/null)" == 0x03* ]] || continue
    [ "$(cat "$d/power/runtime_status" 2>/dev/null)" = active ] || continue
    if command -v nvidia-smi >/dev/null; then
        IFS=', ' read -r gpu load < <(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
    fi
done
if [ -z "$load" ]; then
    for b in "$sys"/class/drm/card*/device/gpu_busy_percent; do [ -f "$b" ] && load="$(cat "$b")" && break; done
fi
echo "- $(int "$cpu") $(int "$gpu") $(int "$load")"
