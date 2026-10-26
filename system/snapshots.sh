#!/usr/bin/env bash
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run this as root" >&2; exit 1; }
if [ "${1:-}" = --cleanup ]; then
    keep="$(cat /var/lib/vyntaris/rollback-point 2>/dev/null)"
    timeshift --list --scripted 2>/dev/null | awk -v keep="$keep" '/ D / && $3 != keep {print $3}' | head -n -3 |
        xargs -r -n1 timeshift --delete --scripted --snapshot >/dev/null
fi

list() {
    /usr/lib/vyntaris/json snapshots "$1"
}

out=/var/lib/vyntaris/snapshots.tsv
install -d /var/lib/vyntaris
tmp="$(mktemp)"
if [ "$(findmnt -no FSTYPE /)" = btrfs ]; then
    top="$(mktemp -d)"
    if mount -o ro,subvolid=5 "$(findmnt -no SOURCE / | sed 's/\[.*//')" "$top" 2>/dev/null; then
        list "$top/timeshift-btrfs/snapshots" > "$tmp"
        umount "$top"
    fi
    rmdir "$top"
else
    list /timeshift/snapshots > "$tmp"
fi
install -m644 "$tmp" "$out"
rm -f "$tmp"
