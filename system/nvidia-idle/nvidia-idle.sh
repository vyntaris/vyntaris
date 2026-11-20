#!/usr/bin/env bash
# On-demand NVIDIA: the driver stays loaded after the app that loaded it quits, and where the card can't sleep
# under it (Runtime D3 not supported) it stays awake. Started when an app closes the card (vyntaris-nvidia-idle.path):
# unused a few seconds later, the driver goes and the card sleeps.
set -u
grep -qx 'blacklist nvidia' /etc/modprobe.d/vyntaris-nvidia-on-demand.conf 2>/dev/null || exit 0
sleep 10
[ -d /sys/module/nvidia ] && [ ! -d /sys/module/nvidia_drm ] || exit 0
grep -qs 'Runtime D3 status: *Enabled' /proc/driver/nvidia/gpus/*/power && exit 0
[ -n "$(find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/nvidia*' -print -quit 2>/dev/null)" ] && exit 0
loaded=()
for m in nvidia_uvm nvidia_modeset nvidia; do [ -d "/sys/module/$m" ] && loaded+=("$m"); done
modprobe -r "${loaded[@]}" 2>/dev/null || true
