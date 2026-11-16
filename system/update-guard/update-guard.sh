#!/usr/bin/env bash
set -uo pipefail
usage() {
    cat <<'USAGE'
Safe updates: a snapshot before every upgrade, with a boot menu entry that undoes it; the new system
gets three tries to start, then the snapshot comes back by itself.

  update-guard pre        before an upgrade (pacman hook): the snapshot, and the way back to it
  update-guard post       after it (pacman hook): the new boot image is on trial
  update-guard boot       at every start: after a rollback, tidies up; writes the status
  update-guard boot-ok    at a start on trial: succeeds once the desktop or the login screen is up, its shell too
  update-guard rebuilt UKI   after mkinitcpio made a boot image: one on trial stays so
  update-guard undo       the next start undoes the last update
  update-guard release    let go of packages held since an update was undone, once newer versions are out
  update-guard status     the status as JSON
USAGE
}

R="${UPDATE_GUARD_ROOT:-}"
STATE="$R/var/lib/vyntaris"
STATUS="$STATE/update-guard.json"
POINT="$STATE/rollback-point"
ROLLED="$STATE/rolled-back"
LAST="$STATE/last-rollback"
PROVEN="$R/run/vyntaris/boot-ok"
ENTRY=vyntaris-rollback.conf
TOP_POINT=.vyntaris-rollback
TRIES=3

log() { echo "update-guard: $*"; }

boot_path() { bootctl --print-boot-path 2>/dev/null; }

main_uki() {
    local b f; b="$(boot_path)" || return 1
    for f in "$b"/EFI/Linux/vyntaris.efi "$b"/EFI/Linux/vyntaris+*.efi; do
        [ -f "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}
on_trial() {
    local b; b="$(boot_path)" || return 1
    compgen -G "$b/EFI/Linux/vyntaris+*.efi" >/dev/null
}

root_subvol() {
    local s
    s="$(findmnt -no OPTIONS / | tr ',' '\n' | sed -n 's/^subvol=//p')"
    s="${s#/}"
    [ -n "$s" ] && [[ "$s" != */* ]] && echo "$s"
}

unsupported() {
    [ "$(findmnt -no FSTYPE /)" = btrfs ] || { echo "the system isn't on Btrfs"; return; }
    root_subvol >/dev/null || { echo "the system isn't in a subvolume of its own"; return; }
    bootctl is-installed >/dev/null 2>&1 || { echo "the boot loader isn't systemd-boot"; return; }
    main_uki >/dev/null || { echo "no unified kernel image (vyntaris.efi)"; return; }
    grep -qE '^HOOKS=.*\bvyntaris-rollback\b' "$R/etc/mkinitcpio.conf" || { echo "the initramfs can't undo updates yet"; return; }
    grep -q '"btrfs_mode" *: *"true"' "$R/etc/timeshift/timeshift.json" 2>/dev/null || { echo "Timeshift doesn't take Btrfs snapshots"; return; }
}

with_top() {
    local dev rc
    dev="$(findmnt -no SOURCE / | sed 's/\[.*//')"
    TOP="$(mktemp -d "$R/run/vyntaris-top.XXXXXX")" || return 1
    if ! mount -t btrfs -o subvolid=5 "$dev" "$TOP"; then rmdir "$TOP"; return 1; fi
    "$@"; rc=$?
    umount "$TOP"; rmdir "$TOP"
    return "$rc"
}

put() {
    cp -f "$1" "$2.new" && sync -f "$2.new" && mv -f "$2.new" "$2"
}

newest_snapshot() {
    timeshift --list --scripted 2>/dev/null |
        awk '$3 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$/ && $4 ~ /D/ {name = $3} END {print name}'
}

write_status() {
    local why point="" pending=false
    why="$(unsupported)"
    [ -f "$POINT" ] && point="$(<"$POINT")"
    if [ -z "$why" ] && on_trial && [ ! -f "$PROVEN" ]; then pending=true; fi
    install -d "$STATE"
    WHY="$why" POINT_NAME="$point" PENDING="$pending" LAST_FILE="$LAST" "${VYNTARIS_JSON:-/usr/lib/vyntaris/json}" guard-status "$STATUS"
}

make_point() {
    local name="$1" sub b uki
    sub="$(root_subvol)"; b="$(boot_path)"; uki="$(main_uki)"
    [ -d "$TOP/timeshift-btrfs/snapshots/$name/$sub" ] || { log "snapshot $name has no $sub"; return 1; }
    printf 'snapshot=timeshift-btrfs/snapshots/%s/%s\nsubvol=%s\n' "$name" "$sub" "$sub" > "$TOP/$TOP_POINT.new" &&
        mv -f "$TOP/$TOP_POINT.new" "$TOP/$TOP_POINT" || return 1
    install -d "$b/vyntaris" "$b/loader/entries" || return 1
    put "$uki" "$b/vyntaris/rollback.efi" || return 1
    local when; when="$(date -d "$(sed 's/_/ /; s/-\([0-9][0-9]\)-\([0-9][0-9]\)$/:\1:\2/' <<<"$name")" '+%-d %b %Y, %H:%M' 2>/dev/null || echo "$name")"
    printf 'title    Undo the update of %s\nsort-key vyntaris-rollback\nefi      /vyntaris/rollback.efi\n' "$when" \
        > "$b/loader/entries/$ENTRY.new" && mv -f "$b/loader/entries/$ENTRY.new" "$b/loader/entries/$ENTRY"
}

pre() {
    if ! timeshift --create --scripted --comments "before upgrade" --tags D >/dev/null 2>&1; then
        log "Timeshift couldn't take a snapshot"; write_status; return 0
    fi
    local why name
    why="$(unsupported)"
    if [ -n "$why" ]; then log "the update can't be undone from the boot menu: $why"; write_status; return 0; fi
    if on_trial && [ -f "$POINT" ]; then
        log "the last update hasn't started yet: the way back stays at $(<"$POINT")"; write_status; return 0
    fi
    name="$(newest_snapshot)"
    if [ -z "$name" ]; then log "no snapshot to go back to"; write_status; return 0; fi
    if with_top make_point "$name"; then
        echo "$name" > "$POINT"
        log "if this update keeps Vyntaris from starting, it undoes itself (snapshot $name)"
    else
        log "the boot menu's entry back couldn't be made"
    fi
    write_status
}

arm() {
    local b uki trial; b="$(boot_path)" || return 1
    trial="$b/EFI/Linux/vyntaris+$TRIES.efi"
    if [ -f "$b/EFI/Linux/vyntaris.efi" ]; then
        rm -f "$b"/EFI/Linux/vyntaris+*.efi
        mv -f "$b/EFI/Linux/vyntaris.efi" "$trial"
    else
        uki="$(main_uki)" || return 1
        [ "$uki" = "$trial" ] || mv -f "$uki" "$trial"
    fi
}
post() {
    release
    if [ -z "$(unsupported)" ] && [ -f "$POINT" ]; then
        rm -f "$PROVEN"
        arm && log "the next start tries the update ($TRIES tries before it's undone)"
    fi
    write_status
}

rebuilt() {
    [ "$(basename "${1:-}")" = vyntaris.efi ] || return 0
    local b; b="$(boot_path)" || return 0
    if compgen -G "$b/EFI/Linux/vyntaris+*.efi" >/dev/null; then arm; fi
    write_status
}

# The update that was undone isn't installed again: its packages are held (IgnorePkg) until a newer version is out.
HELD="$STATE/held-updates"
HELD_CONF="$R/etc/pacman.d/vyntaris-held.conf"
write_held() {
    install -d "$STATE" "$(dirname "$HELD_CONF")"
    if [ -s "$HELD" ]; then
        printf '# Held after an update was undone (update-guard); let go once newer versions are out.\nIgnorePkg = %s\n' \
            "$(cut -d' ' -f1 "$HELD" | tr '\n' ' ')" > "$HELD_CONF"
    else
        rm -f "$HELD" "$HELD_CONF"
    fi
    grep -qxF "Include = /etc/pacman.d/vyntaris-held.conf" "$R/etc/pacman.conf" 2>/dev/null ||
        sed -i '/^\[options\]/a Include = /etc/pacman.d/vyntaris-held.conf' "$R/etc/pacman.conf" 2>/dev/null
    [ -e "$HELD_CONF" ] || : > "$HELD_CONF"
}
hold_broken() {
    local broken; broken="$(sed -n 's/^broken=//p' "$ROLLED")"
    [ -n "$broken" ] && [ -d "$TOP/$broken/var/lib/pacman/local" ] || return 0
    join -j1 -o 1.1,1.2,2.2 -a1 -e none \
        <(pacman -Q --dbpath "$TOP/$broken/var/lib/pacman" 2>/dev/null | sort) \
        <(pacman -Q --dbpath "$R/var/lib/pacman" 2>/dev/null | sort) |
        awk '$2 != $3 {print $1, $2}' > "$HELD.new"
    cat "$HELD.new" "$HELD" 2>/dev/null | awk '!seen[$1]++' > "$HELD.all"; mv -f "$HELD.all" "$HELD"; rm -f "$HELD.new"
    [ -s "$HELD" ] && log "held back until newer versions are out: $(cut -d' ' -f1 "$HELD" | tr '\n' ' ')"
    write_held
}
release() {
    [ -s "$HELD" ] || return 0
    local name ver newest
    : > "$HELD.keep"
    while read -r name ver; do
        newest="$(pacman -Si --dbpath "$R/var/lib/pacman" "$name" 2>/dev/null | awk '/^Version/ {print $3; exit}')"
        if [ -n "$newest" ] && [ "$(vercmp "$newest" "$ver")" -gt 0 ]; then log "$name $newest is out: no longer held"
        else echo "$name $ver" >> "$HELD.keep"; fi
    done < "$HELD"
    mv -f "$HELD.keep" "$HELD"
    write_held
}

broken_cleanup() {
    local sub; sub="$(root_subvol)"
    find "$TOP/" -mindepth 1 -maxdepth 1 -name "$sub.broken-*" | sort | head -n -1 |
        while read -r d; do btrfs -q subvolume delete -R "$d" || log "couldn't delete $d"; done
}
finish() {
    local b k base
    b="$(boot_path)" || { log "no boot partition"; return 1; }
    if [ -f "$b/vyntaris/rollback.efi" ]; then
        put "$b/vyntaris/rollback.efi" "$b/EFI/Linux/vyntaris.efi.back" || { log "couldn't put the boot image back"; return 1; }
        rm -f "$b"/EFI/Linux/vyntaris+*.efi
        mv -f "$b/EFI/Linux/vyntaris.efi.back" "$b/EFI/Linux/vyntaris.efi" || return 1
    fi
    for k in "$R"/usr/lib/modules/*/pkgbase; do
        [ -f "$k" ] || continue
        base="$(<"$k")"
        install -Dm644 "$(dirname "$k")/vmlinuz" "$R/boot/vmlinuz-$base" || return 1
    done
    rm -f "$b/loader/entries/$ENTRY" "$b/vyntaris/rollback.efi" "$POINT"
    sync -f "$b/EFI/Linux" || { log "couldn't write the boot partition"; return 1; }
    with_top hold_broken || true
    with_top broken_cleanup || true
    mv -f "$ROLLED" "$LAST" && sync -f "$LAST"
    "$R/usr/lib/vyntaris/snapshots" >/dev/null 2>&1 || true
    log "rolled back to the snapshot $(sed -n 's/^snapshot=//p' "$LAST")"
}
at_boot() {
    if [ -f "$ROLLED" ]; then finish; else release; fi
    write_status
}

up_for_20s() {
    local pid up
    for pid in $(pgrep -x "$1"); do
        up="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')"
        [ "${up:-0}" -ge 20 ] && return 0
    done
    return 1
}

boot_ok() {
    local t
    for ((t = 0; t < 600; t += 5)); do
        if up_for_20s Hyprland && up_for_20s 'qs|quickshell'; then
            install -d "$(dirname "$PROVEN")" && touch "$PROVEN"
            write_status
            return 0
        fi
        sleep 5
    done
    log "neither the desktop nor the login screen came up whole: this start doesn't count"
    return 1
}

undo() {
    local why; why="$(unsupported)"
    [ -z "$why" ] || { echo "updates can't be undone here: $why" >&2; return 1; }
    [ -f "$POINT" ] || { echo "there is no update to undo" >&2; return 1; }
    bootctl set-oneshot "$ENTRY" && log "the next start undoes the update"
}

[ "$(id -u)" -eq 0 ] || [ "${1:-}" = status ] || { echo "run this as root" >&2; exit 1; }
case "${1:-}" in
    pre) pre ;;
    post) post ;;
    boot) at_boot ;;
    boot-ok) boot_ok ;;
    rebuilt) rebuilt "${2:-}" ;;
    undo) undo ;;
    release) release ;;
    status) cat "$STATUS" 2>/dev/null || echo '{"protected": false, "reason": "not set up yet"}' ;;
    *) usage >&2; exit 2 ;;
esac
