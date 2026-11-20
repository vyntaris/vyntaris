#!/usr/bin/env bash
# On-demand NVIDIA: the driver stays loaded after the app that loaded it quits. Where the card can't sleep under it
# (Runtime D3 not supported), it's unloaded once nothing used it for two checks in a row, and the card sleeps.
set -u
mark=/run/vyntaris/nvidia-idle
grep -qx 'blacklist nvidia' /etc/modprobe.d/vyntaris-nvidia-on-demand.conf 2>/dev/null || exit 0
[ -d /sys/module/nvidia ] && [ ! -d /sys/module/nvidia_drm ] || { rm -f "$mark"; exit 0; }
grep -qs 'Runtime D3 status: *Enabled' /proc/driver/nvidia/gpus/*/power && exit 0
if [ -n "$(find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/nvidia*' -print -quit 2>/dev/null)" ]; then
    rm -f "$mark"
    exit 0
fi
if [ ! -e "$mark" ]; then
    mkdir -p "${mark%/*}"
    : > "$mark"
    exit 0
fi
rm -f "$mark"
loaded=()
for m in nvidia_uvm nvidia_modeset nvidia; do [ -d "/sys/module/$m" ] && loaded+=("$m"); done
modprobe -r "${loaded[@]}" 2>/dev/null || true
