#!/usr/bin/bash
set -u
R="${UPDATE_GUARD_ROOT:-}"
ENTRY_VAR="$R/sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"
TOP="$R/run/vyntaris-top"

log() { echo "vyntaris-rollback: $*"; }
show() { plymouth display-message --text="$*" >/dev/null 2>&1 || true; log "$*"; }

entry="$(tail -c +5 "$ENTRY_VAR" 2>/dev/null | tr -d '\000')"
[ "$entry" = vyntaris-rollback.conf ] || exit 0

root="" flags=""
for arg in $(<"$R/proc/cmdline"); do
    case "$arg" in
        root=*) root="${arg#root=}" ;;
        rootflags=*) flags="${arg#rootflags=}" ;;
    esac
done
case "$root" in
    UUID=*) dev="/dev/disk/by-uuid/${root#UUID=}" ;;
    PARTUUID=*) dev="/dev/disk/by-partuuid/${root#PARTUUID=}" ;;
    LABEL=*) dev="/dev/disk/by-label/${root#LABEL=}" ;;
    /dev/*) dev="$root" ;;
    *) log "no root= on the command line"; exit 0 ;;
esac

mkdir -p "$TOP"
mount -t btrfs -o subvolid=5 "$dev" "$TOP" || { log "couldn't mount $dev"; exit 1; }
done_() { sync; umount "$TOP"; exit "$1"; }

point="$TOP/.vyntaris-rollback"
[ -f "$point" ] || { log "nothing to undo (done already)"; done_ 0; }
snap="" sub=""
while IFS='=' read -r k v; do
    case "$k" in snapshot) snap="$v" ;; subvol) sub="$v" ;; esac
done < "$point"
want="$(tr ',' '\n' <<<"$flags" | sed -n 's/^subvol=//p')"; want="${want#/}"
case "$snap$sub" in *..*) log "bad rollback point"; done_ 1 ;; esac
if [ -z "$snap" ] || [ -z "$sub" ] || [[ "$sub" == */* ]] || [ "$sub" != "$want" ]; then
    log "the rollback point doesn't fit this system ($sub, mounted from ${want:-?})"; done_ 1
fi
[ -d "$TOP/$snap" ] || { log "the snapshot $snap is gone"; done_ 1; }

show "Undoing the last update…"
stamp="$(date +%Y-%m-%d_%H-%M-%S)"
broken="$sub.broken-$stamp"
mv "$TOP/$sub" "$TOP/$broken" || { log "couldn't move the system aside"; done_ 1; }
if ! btrfs subvolume snapshot "$TOP/$snap" "$TOP/$sub" >/dev/null; then
    log "couldn't put the snapshot in place: the system stays as it was"
    mv "$TOP/$broken" "$TOP/$sub"
    done_ 1
fi
# Subvolumes inside the system (/swap for hibernation, /var/lib/machines) aren't in a snapshot: it has empty folders
# where they were. They go over from the system set aside, the outermost ones (the rest come with them).
nested=()
while read -r line; do
    p="${line##* path }"
    [ "${p#"$broken"/}" != "$p" ] && nested+=("${p#"$broken"/}")
done < <(btrfs subvolume list -o "$TOP/$broken" 2>/dev/null)
for rel in "${nested[@]}"; do
    inner=0
    for other in "${nested[@]}"; do [ "$other" != "$rel" ] && [ "${rel#"$other"/}" != "$rel" ] && inner=1; done
    [ "$inner" = 1 ] && continue
    target="$TOP/$sub/$rel"
    if [ -d "$target" ] && ! rmdir "$target" 2>/dev/null; then log "$rel isn't empty in the snapshot: left in $broken"; continue; fi
    mkdir -p "${target%/*}"
    mv "$TOP/$broken/$rel" "$target" || log "couldn't carry $rel over"
done
mkdir -p "$TOP/$sub/var/lib/vyntaris"
printf 'at=%s\nsnapshot=%s\nbroken=%s\n' "$stamp" "$snap" "$broken" > "$TOP/$sub/var/lib/vyntaris/rolled-back"
rm -f "$point"
show "The last update is undone"
done_ 0
