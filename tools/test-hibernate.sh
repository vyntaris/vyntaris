#!/usr/bin/env bash
# Hibernation turned on and off (system/bin/vyntaris-hibernate) on a stand-in system: the swap file, fstab and the
# kernel's line are files in a folder of its own; btrfs, sudo and mkinitcpio are stand-ins.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HIB="$REPO/system/bin/vyntaris-hibernate"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "   ok    $*"; }
no() { echo "   FAIL  $*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else no "$what"; fi; }

R="$T/sys"
mkdir -p "$T/bin" "$R/etc/kernel" "$R/proc"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/bin/$1"; chmod 755 "$T/bin/$1"; }
log='echo "$(basename "$0") $*" >> "'"$T"'/calls"'
stub sudo 'exec "$@"'
stub findmnt 'case "$*" in *FSTYPE*) echo "${FAKE_FS:-btrfs}" ;; *UUID*) echo 1111-2222 ;; esac'
stub df 'printf "Avail\n%s\n" "${FAKE_FREE:-100000}"'
stub btrfs "$log"'
case "$1 $2" in
    "subvolume create") mkdir -p "$3" ;;
    "filesystem mkswapfile") echo swap > "${!#}" ;;
    "inspect-internal map-swapfile") echo 533760 ;;
esac'
stub dd "$log"'; for a; do case "$a" in of=*) echo swap > "${a#of=}" ;; esac; done'
stub mkswap "$log"
stub swapon "$log"
stub swapoff "$log"
stub mkinitcpio "$log"
stub filefrag 'printf "Filesystem type is: ef53\n ext:     logical_offset:        physical_offset: length:\n   0:        0..       0:     34816..     34816:      1:\n"'
export PATH="$T/bin:$PATH" HIBERNATE_ROOT="$R" VYNTARIS_JSON=/nonexistent
fresh() {
    rm -rf "$R/swap" "$R/swapfile"; : > "$T/calls"
    printf 'UUID=abcd / btrfs rw,subvol=/@ 0 0\n' > "$R/etc/fstab"
    printf 'root=UUID=abcd rw rootflags=subvol=@ quiet splash\n' > "$R/etc/kernel/cmdline"
    printf 'MemTotal:       %s kB\n' "${1:-16000000}" > "$R/proc/meminfo"
}

echo ":: on, on Btrfs"
fresh 16000000
"$HIB" >/dev/null
check "a swap file in its own subvolume (/swap)"  test -f "$R/swap/swapfile"
check "… made the Btrfs way"                      grep -q '^btrfs filesystem mkswapfile --size 7812m' "$T/calls"
check "half the RAM"                              grep -q -- '--size 7812m' "$T/calls"
check "in fstab, by its real path"                grep -qx '/swap/swapfile none swap defaults,pri=1 0 0' "$R/etc/fstab"
check "the kernel resumes from it"                grep -q 'resume=UUID=1111-2222 resume_offset=533760' "$R/etc/kernel/cmdline"
check "… the rest of its line kept"               grep -q '^root=UUID=abcd rw rootflags=subvol=@ quiet splash ' "$R/etc/kernel/cmdline"
check "boot images made again"                    grep -q '^mkinitcpio -P' "$T/calls"
"$HIB" >/dev/null
check "on again: one fstab line"                  test "$(grep -c swapfile "$R/etc/fstab")" = 1
check "… one resume"                              test "$(grep -o 'resume=' "$R/etc/kernel/cmdline" | wc -l)" = 1
check "… the file not made twice"                 test "$(grep -c mkswapfile "$T/calls")" = 1

echo ":: off"
"$HIB" off >/dev/null
check "the file gone"                             test ! -e "$R/swap/swapfile"
check "out of fstab"                              bash -c '! grep -q swapfile "$0"' "$R/etc/fstab"
check "the kernel's line as it was"               test "$(cat "$R/etc/kernel/cmdline")" = "root=UUID=abcd rw rootflags=subvol=@ quiet splash"
check "turned off before it went"                 grep -q '^swapoff' "$T/calls"

echo ":: sizes and space"
fresh 64000000
"$HIB" >/dev/null
check "lots of RAM: 8 GB at most"                 grep -q -- '--size 8192m' "$T/calls"
fresh 16000000
check "not enough room: refused"                  bash -c '! FAKE_FREE=5000 "$0"' "$HIB"
check "… nothing made"                            test ! -e "$R/swap/swapfile" -a "$(grep -c swapfile "$R/etc/fstab")" = 0

echo ":: on ext4"
fresh 8000000
FAKE_FS=ext4 "$HIB" >/dev/null
check "a plain file (/swapfile)"                  test -f "$R/swapfile"
check "… made with dd and mkswap"                 grep -q '^dd ' "$T/calls"
check "… only its owner reads it"                 test "$(stat -c %a "$R/swapfile")" = 600
check "the offset from filefrag"                  grep -q 'resume_offset=34816' "$R/etc/kernel/cmdline"
check "in fstab"                                  grep -qx '/swapfile none swap defaults,pri=1 0 0' "$R/etc/fstab"

echo ":: what the rest of the system keeps for it"
check "a rollback carries /swap over (it's a subvolume inside the system)" grep -q 'nested' "$REPO/system/update-guard/initrd-rollback.sh"

echo
[ "$fails" = 0 ] && echo "hibernate: all checks passed" || echo "hibernate: $fails failed"
exit $((fails > 0))
