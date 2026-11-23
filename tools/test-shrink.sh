#!/usr/bin/env bash
# Making room next to another system (iso/…/vyntaris-shrink-info, vyntaris-shrink) on image files: a GPT disk
# with an EFI partition and a Windows (NTFS) or Linux (ext4) one holding a file. Needs ntfs-3g (with
# ntfsresize), gdisk and e2fsprogs; no root (the file system is its own image, SHRINK_DEV).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/iso/airootfs/usr/local/bin"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "   ok    $*"; }
no() { echo "   FAIL  $*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else no "$what"; fi; }
for t in sgdisk mkntfs ntfsresize ntfscp ntfscat mkfs.ext4 debugfs; do
    command -v "$t" >/dev/null || { echo "test-shrink: needs $t"; exit 1; }
done
cd "$T" || exit 1
head -c 120M /dev/urandom > file.bin
want="$(sha256sum < file.bin)"
gib=$((1024 * 1024 * 1024))

disk() {  # a 6 GiB disk: EFI, then one partition of type $1 (with attributes 0 and 63, as Windows' have)
    rm -f disk.img; truncate -s 6G disk.img
    sgdisk -n 1:2048:+100M -t 1:ef00 -c 1:EFI -n 2:0:0 -t "2:$1" -c "2:Basic data partition" -A 2:set:0 -A 2:set:63 disk.img >/dev/null
    first="$(sgdisk -i 2 disk.img | awk '/^First sector/ {print $3}')"
    last="$(sgdisk -i 2 disk.img | awk '/^Last sector/ {print $3}')"
    guid="$(sgdisk -i 2 disk.img | sed -n 's/^Partition unique GUID: //p')"
    rm -f fs.img; truncate -s $(( (last - first + 1) * 512 )) fs.img
}
info() { bash "$BIN/vyntaris-shrink-info" fs.img | sed -n "s/^$1=//p"; }
after() { sgdisk -i 2 disk.img | sed -n "s/^$1: //p"; }

echo ":: Windows (NTFS)"
disk 0700
mkntfs -F -Q -L Windows fs.img >/dev/null 2>&1
ntfscp -f fs.img file.bin file.bin >/dev/null 2>&1
check "it can shrink, and how far"            test "$(info fs)" = ntfs -a -z "$(info problem)" -a "$(info min)" -gt 0
min="$(info min)"
check "… its files and 2 GiB to grow stay"   test "$min" -ge $((2 * gib)) -a "$min" -lt $((3 * gib))
room="$(SHRINK_DEV=fs.img bash "$BIN/vyntaris-shrink" disk.img 2 $((3 * gib)))"
check "made smaller"                          test -n "$room"
check "… the room starts on a 1 MiB boundary" test $(( ${room% *} % 2048 )) = 0
check "… and ends where the partition did"   test "${room#* }" = "$last"
check "… same start"                          test "$(after 'First sector' | awk '{print $1}')" = "$first"
check "… same GUID"                           test "$(after 'Partition unique GUID')" = "$guid"
check "… same name"                           test "$(after 'Partition name')" = "'Basic data partition'"
check "… same attributes"                     test "$(after 'Attribute flags')" = 8000000000000001
check "… same type"                           sh -c "sgdisk -i 2 disk.img | grep -q 'Microsoft basic data'"
vol="$(ntfsresize --info --force --no-action fs.img 2>/dev/null | sed -n 's/^Current volume size: \([0-9]*\) bytes.*/\1/p')"
check "… NTFS fits the partition"             test "${vol:-0}" -le $((3 * gib)) -a "${vol:-0}" -gt $((3 * gib - 1048576))
check "… and the file is whole"               test "$(ntfscat -f fs.img file.bin 2>/dev/null | sha256sum)" = "$want"
check "not smaller than its files"            sh -c "! SHRINK_DEV=fs.img bash '$BIN/vyntaris-shrink' disk.img 2 $((50 * 1024 * 1024))"

echo ":: Linux (ext4)"
disk 8300
mkdir files; cp file.bin files/
mkfs.ext4 -q -d files fs.img
check "it can shrink"                         test "$(info fs)" = ext4 -a -z "$(info problem)"
room="$(SHRINK_DEV=fs.img bash "$BIN/vyntaris-shrink" disk.img 2 $((3 * gib)) 2>/dev/null)"
check "made smaller"                          test -n "$room" -a "${room#* }" = "$last"
check "… the file system checks out"          e2fsck -fn fs.img
check "… and the file is whole"               test "$(debugfs -R 'cat /file.bin' fs.img 2>/dev/null | sha256sum)" = "$want"

echo ":: what can't shrink"
disk 0700
mkfs.vfat fs.img >/dev/null 2>&1 || truncate -s 1M fs.img
check "another file system: said so"          test "$(info problem)" = unsupported

[ "$fails" = 0 ] && echo ":: all fine" || { echo ":: $fails failed"; exit 1; }
