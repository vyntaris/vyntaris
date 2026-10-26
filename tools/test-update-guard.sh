#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO/system/update-guard/update-guard.sh"
INITRD="$REPO/system/update-guard/initrd-rollback.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "   ok    $*"; }
no() { echo "   FAIL  $*"; fails=$((fails + 1)); }
check() {
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$what"; else no "$what"; fi
}

TOP="$T/top"; ESP="$T/esp"; SYS="$TOP/@"
mkdir -p "$SYS"/{var/lib/vyntaris,usr/bin,usr/lib/modules/6.1.1-arch1-1,usr/lib/vyntaris,etc/timeshift} \
    "$ESP/EFI/Linux" "$ESP/loader/entries" "$T/run" "$T/bin"
ln -s "$ESP" "$SYS/boot"
ln -s "$T/run" "$SYS/run"
echo linux > "$SYS/usr/lib/modules/6.1.1-arch1-1/pkgbase"
echo "kernel 6.1" > "$SYS/usr/lib/modules/6.1.1-arch1-1/vmlinuz"
echo "hyprland 1" > "$SYS/usr/bin/Hyprland"
printf '#!/bin/sh\ntouch "%s/snapshots-listed"\n' "$T" > "$SYS/usr/lib/vyntaris/snapshots"; chmod 755 "$SYS/usr/lib/vyntaris/snapshots"
echo 'HOOKS=(base systemd autodetect block filesystems vyntaris-rollback)' > "$SYS/etc/mkinitcpio.conf"
echo '{ "btrfs_mode" : "true" }' > "$SYS/etc/timeshift/timeshift.json"
echo "uki before the update" > "$ESP/EFI/Linux/vyntaris.efi"

stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/bin/$1"; chmod 755 "$T/bin/$1"; }
stub id 'echo 0'
stub bootctl 'case "$1" in --print-boot-path) echo "$UPDATE_GUARD_ROOT/boot" ;; is-installed) exit 0 ;; set-oneshot) echo "$2" > "'"$T"'/oneshot" ;; esac'
stub findmnt 'case "$*" in *FSTYPE*) echo "${FAKE_FS:-btrfs}" ;; *OPTIONS*) echo "rw,noatime,subvol=/@" ;; *SOURCE*) echo "/dev/fake[/@]" ;; esac'
stub mount 'd="${!#}"; rmdir "$d" && ln -s "'"$TOP"'" "$d"'
stub umount 'rm "$1" && mkdir "$1"'
stub btrfs 'args=("$@"); [ "${args[0]}" = -q ] && args=("${args[@]:1}")
case "${args[0]} ${args[1]}" in
    "subvolume snapshot") cp -a "${args[2]}" "${args[3]}" ;;
    "subvolume delete") rm -rf "${args[2]}" ;;
esac'
stub timeshift 'snaps="'"$TOP"'/timeshift-btrfs/snapshots"
case "$1" in
    --create) n="$(cat "'"$T"'/clock")"; mkdir -p "$snaps/$n"; cp -a "'"$TOP"'/@" "$snaps/$n/@" ;;
    --list) echo "Num     Name                 Tags  Description"
            i=0; for d in $(ls "$snaps" 2>/dev/null); do echo "$i    >  $d  D  before upgrade"; i=$((i + 1)); done ;;
esac'
stub pgrep 'case "$*" in *quickshell*) [ -z "${FAKE_NO_SHELL:-}" ] && echo 4343 ;; *) echo 4242 ;; esac'
stub ps 'echo "${FAKE_UPTIME:-30}"'
export VYNTARIS_JSON="${VYNTARIS_JSON:-$REPO/rust/target/release/vyntaris-json}"
[ -x "$VYNTARIS_JSON" ] || (cd "$REPO/rust" && cargo build -q --release -p vyntaris-json) || exit 1
export PATH="$T/bin:$PATH" UPDATE_GUARD_ROOT="$SYS"
guard() { "$GUARD" "$@"; }
status() { python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$SYS/var/lib/vyntaris/update-guard.json" "$1"; }
echo 2026-10-13_16-00-00 > "$T/clock"

echo ":: before an update: the snapshot and the boot menu's way back to it"
guard pre >/dev/null
check "a snapshot of the system"            test -f "$TOP/timeshift-btrfs/snapshots/2026-10-13_16-00-00/@/usr/bin/Hyprland"
check "the boot image kept beside it"       grep -q "uki before the update" "$ESP/vyntaris/rollback.efi"
check "an entry on the boot menu"           grep -q '^efi *\/vyntaris\/rollback.efi' "$ESP/loader/entries/vyntaris-rollback.conf"
check "… titled with the update's time"     grep -q '^title *Undo the update of 13 Oct 2026, 16:00' "$ESP/loader/entries/vyntaris-rollback.conf"
check "… sorted after Vyntaris itself"      grep -q '^sort-key vyntaris-rollback' "$ESP/loader/entries/vyntaris-rollback.conf"
check "the point the initramfs reads"       grep -qx 'snapshot=timeshift-btrfs/snapshots/2026-10-13_16-00-00/@' "$TOP/.vyntaris-rollback"
check "status: protected"                   test "$(status 's["protected"]')" = True
check "status: the point"                   test "$(status 's["point"]')" = 2026-10-13_16-00-00

echo ":: the update, then on trial"
echo "hyprland 2 (broken)" > "$SYS/usr/bin/Hyprland"
echo "kernel 6.2" > "$SYS/usr/lib/modules/6.1.1-arch1-1/vmlinuz"
echo "uki after the update" > "$ESP/EFI/Linux/vyntaris.efi"
guard post >/dev/null
check "the new boot image has 3 tries"      test -f "$ESP/EFI/Linux/vyntaris+3.efi"
check "… and no other"                      test ! -e "$ESP/EFI/Linux/vyntaris.efi"
check "status: pending"                     test "$(status 's["pending"]')" = True

echo ":: mkinitcpio makes the boot image again while it's on trial"
mv "$ESP/EFI/Linux/vyntaris+3.efi" "$ESP/EFI/Linux/vyntaris+1-2.efi"
echo "uki made again" > "$ESP/EFI/Linux/vyntaris.efi"
guard rebuilt "$ESP/EFI/Linux/vyntaris.efi"
check "it takes the place of the one on trial" test "$(ls "$ESP/EFI/Linux")" = "vyntaris+3.efi"
check "… with all the tries again"          grep -q "uki made again" "$ESP/EFI/Linux/vyntaris+3.efi"
guard rebuilt "$ESP/EFI/Linux/other.efi"
check "other boot images aren't touched"    test "$(ls "$ESP/EFI/Linux")" = "vyntaris+3.efi"

echo ":: another update before the last one proved itself"
echo 2026-10-14_09-30-00 > "$T/clock"
guard pre >/dev/null
check "the way back stays before the first" grep -q 2026-10-13_16-00-00 "$TOP/.vyntaris-rollback"
check "… with its boot image"               grep -q "uki before the update" "$ESP/vyntaris/rollback.efi"
check "the snapshot is still taken"         test -d "$TOP/timeshift-btrfs/snapshots/2026-10-14_09-30-00/@"

echo ":: three starts that never reached the desktop: systemd-boot starts the entry back"
mkdir -p "$T/initrd/sys/firmware/efi/efivars" "$T/initrd/proc" "$T/initrd/run"
efivar() { printf '\x06\x00\x00\x00'; printf '%s' "$1" | iconv -f utf-8 -t utf-16le; printf '\x00\x00'; }
echo "BOOT_IMAGE=x root=UUID=1234 rw rootflags=compress=zstd,subvol=@ quiet" > "$T/initrd/proc/cmdline"
efivar vyntaris.efi > "$T/initrd/sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"
UPDATE_GUARD_ROOT="$T/initrd" "$INITRD" >/dev/null
check "a normal start changes nothing"      grep -q "broken" "$SYS/usr/bin/Hyprland"
efivar vyntaris-rollback.conf > "$T/initrd/sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"
UPDATE_GUARD_ROOT="$T/initrd" "$INITRD" >/dev/null
check "the snapshot is the system now"      grep -q "hyprland 1" "$SYS/usr/bin/Hyprland"
check "the system as it was is kept aside"  compgen -G "$TOP/@.broken-*/usr/bin/Hyprland"
check "it says so in the system"            grep -q '^snapshot=timeshift-btrfs/snapshots/2026-10-13_16-00-00/@' "$SYS/var/lib/vyntaris/rolled-back"
check "the point is used up"                test ! -e "$TOP/.vyntaris-rollback"
UPDATE_GUARD_ROOT="$T/initrd" "$INITRD" >/dev/null
check "a second start from it changes nothing" test "$(compgen -G "$TOP/@.broken-*" | wc -l)" = 1

echo ":: the first start after: the boot image and the kernel go back too"
mkdir -p "$TOP/@.broken-2020-01-01_00-00-00"
guard boot >/dev/null
check "the boot image from before the update" grep -q "uki before the update" "$ESP/EFI/Linux/vyntaris.efi"
check "… and only it"                       test "$(ls "$ESP/EFI/Linux")" = "vyntaris.efi"
check "the kernel from before the update"   grep -q "kernel 6.1" "$ESP/vmlinuz-linux"
check "the entry back is off the menu"      test ! -e "$ESP/loader/entries/vyntaris-rollback.conf"
check "… with its boot image"               test ! -e "$ESP/vyntaris/rollback.efi"
check "only the newest system rolled back from stays" test "$(compgen -G "$TOP/@.broken-*" | wc -l)" = 1
check "the snapshot list is made again"     test -f "$T/snapshots-listed"
check "status: the rollback, for the desktop" test "$(status 's["rollback"]["snapshot"]')" = "timeshift-btrfs/snapshots/2026-10-13_16-00-00/@"
check "status: no point any more"           test "$(status 's["point"]')" = None

echo ":: an update that proves itself"
echo 2026-10-15_12-00-00 > "$T/clock"
guard pre >/dev/null && guard post >/dev/null
check "on trial"                            test -f "$ESP/EFI/Linux/vyntaris+3.efi"
FAKE_UPTIME=5 timeout 8 "$GUARD" boot-ok >/dev/null 2>&1
check "a desktop up for 5 s doesn't count yet" test ! -e "$T/run/vyntaris/boot-ok"
FAKE_NO_SHELL=1 timeout 8 "$GUARD" boot-ok >/dev/null 2>&1
check "Hyprland without its shell doesn't count" test ! -e "$T/run/vyntaris/boot-ok"
guard boot-ok >/dev/null
check "one up for 20 s does"                test -f "$T/run/vyntaris/boot-ok"
check "status: not pending"                 test "$(status 's["pending"]')" = False
guard undo >/dev/null
check "Undo: the next start is the entry back" grep -qx vyntaris-rollback.conf "$T/oneshot"

echo ":: where it can't undo updates"
FAKE_FS=ext4 guard pre >/dev/null
check "ext4: not protected, and why"        test "$(FAKE_FS=ext4 status 's["reason"]')" = "the system isn't on Btrfs"
sed -i 's/ vyntaris-rollback//' "$SYS/etc/mkinitcpio.conf"
guard post >/dev/null
check "no initramfs hook: not protected"    test "$(status 's["protected"]')" = False
check "undo refuses"                        bash -c '! "$0" undo' "$GUARD"

echo
[ "$fails" = 0 ] && echo "update-guard: all checks passed" || echo "update-guard: $fails failed"
exit $((fails > 0))
