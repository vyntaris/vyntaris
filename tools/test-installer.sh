#!/usr/bin/env bash
# The installer's parts that can't wait for a VM: finding its boot entry on any firmware, never stopping without
# saying where, telling key errors from the rest, and fix-keyring on a stand-in system.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$REPO/iso/airootfs/usr/local/bin/install-desktop"
FIX="$REPO/iso/airootfs/usr/local/bin/fix-keyring"
QML="$REPO/config/installer/shell.qml"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "   ok    $*"; }
no() { echo "   FAIL  $*"; fails=$((fails + 1)); }
same() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1: wanted [$3], got [$2]"; fi; }

echo ":: Boot entry"
# The function as the installer has it, with efibootmgr standing in
sed -n '/^boot_entry() {/,/^}/p' "$INST" > "$T/boot_entry"
[ -s "$T/boot_entry" ] || no "boot_entry() not found in install-desktop"
entries() {
    printf 'BootCurrent: 0001\nBootOrder: 0001,0003\n'
    printf 'Boot0001* Windows Boot Manager\tHD(1,GPT,0a1b-2c,0x800,0x32000)/\\EFI\\Microsoft\\Boot\\bootmgfw.efi\n'
    printf 'Boot0003* Linux Boot Manager\tHD(1,GPT,%s,0x800,0x32000)/\\EFI\\systemd\\systemd-bootx64.efi\n' "$1"
}
export -f entries
look() {   # what the efibootmgr stand-in does, partuuid → the entry found (empty: none), under the installer's set -e
    bash -c 'set -euo pipefail
        efibootmgr() { '"$1"'; }
        loader_partuuid="$2"
        source "$1"
        entry="$(boot_entry)"
        echo "entry=$entry"' sh "$T/boot_entry" "$2" 2>/dev/null
}
same "found" "$(look 'entries ab12-cd34' ab12-cd34)" "entry=0003"
same "found though efibootmgr fails on another entry" "$(look 'entries ab12-cd34; echo "Could not parse device path" >&2; return 3' ab12-cd34)" "entry=0003"
same "found though the list is long (no SIGPIPE)" \
    "$(look 'entries ab12-cd34; for i in $(seq 20000); do echo "Boot$i* Lenovo junk VenHw(ABCDEF)"; done' ab12-cd34)" "entry=0003"
same "found with the firmware's upper case" "$(look 'entries AB12-CD34' ab12-cd34)" "entry=0003"
same "another partition's isn't taken" "$(look 'entries ffff-0000' ab12-cd34)" "entry="
same "no partition UUID: none, and it goes on" "$(look 'entries ab12-cd34' '')" "entry="
same "efibootmgr missing or dead: none, and it goes on" "$(look 'return 127' ab12-cd34)" "entry="

echo ":: Never a silent stop"
trapline="$(grep -m1 "^trap '.*' ERR$" "$INST")"
[ -n "$trapline" ] || no "install-desktop has no ERR trap"
out="$(bash -c 'set -euo pipefail; c_err=""; c_off=""
'"$trapline"'
x="$(false)"
echo "went on"' 2>&1)"
case "$out" in *"stopped at line 3: x=\"\$(false)\""*) ok "a failing command says its line and itself" ;; *) no "trap said: $out" ;; esac
case "$out" in *"went on"*) no "it went on after the failure" ;; *) ok "and the install stops there" ;; esac

echo ":: Key errors"
key_error="$(sed -n "s/^key_error='\(.*\)'$/\1/p" "$INST")"
[ -n "$key_error" ] || no "key_error not found in install-desktop"
ui="$(grep -o 'if (/.*/i.test(line)) keyError = true' "$QML" | sed 's#^if (/##; s#/i.test(line)) keyError = true$##')"
same "the installer and its window agree on what a key error is" "$ui" "$key_error"
keyish=(
    'error: linux: signature from "Jan Alexander Steffens (heftig) <heftig@archlinux.org>" is unknown trust'
    'error: mesa: signature from "Laurent Carlier <lordheavym@archlinux.org>" is marginal trust'
    'error: glibc: signature from "Frederik Schwan <freswa@archlinux.org>" is invalid'
    'error: failed to commit transaction (invalid or corrupted package (PGP signature))'
    "error: database 'core' is not valid (invalid or corrupted database (PGP signature))"
    'error: key "3B94A80E50A477C7" could not be looked up remotely'
    'error: key "DDB867B92AA789C165EEFA799B729B06A680C281" could not be imported'
    'error: required key missing from keyring'
    'error: keyring is not writable'
    'error: GPGME error: No data'
)
benign=(
    'checking keyring...'
    '(676/676) checking keys in keyring                 [######################] 100%'
    'downloading required keys...'
    '==> Updating trust database...'
    '==> Appending keys from archlinux.gpg...'
    'error: failed retrieving file '"'"'linux-7.3.5.arch1-1-x86_64.pkg.tar.zst'"'"' from geo.mirror.pkgbuild.com : Operation too slow'
    'error: failed to commit transaction (failed to retrieve some files)'
    'error: target not found: tesseract-data-xyz'
)
# The JS regex, as the window runs it
js() { node -e 'const r = new RegExp(process.argv[1], "i"); process.stdout.write(r.test(process.argv[2]) ? "y" : "n")' "$ui" "$1"; }
have_node=""; command -v node >/dev/null && have_node=1
for l in "${keyish[@]}"; do
    if printf '%s\n' "$l" | grep -qiE "$key_error"; then ok "key error: ${l:7:52}"; else no "missed by the installer: $l"; fi
    [ -z "$have_node" ] || [ "$(js "$l")" = y ] || no "missed by the window: $l"
done
for l in "${benign[@]}"; do
    if printf '%s\n' "$l" | grep -qiE "$key_error"; then no "taken for a key error: $l"; else ok "not a key error: ${l:0:52}"; fi
    [ -z "$have_node" ] || [ "$(js "$l")" = n ] || no "the window takes it for a key error: $l"
done
[ -n "$have_node" ] || echo "   skip  the window's regex (no node)"

echo ":: The window"
if grep -q "| stdbuf -oL tr '\\\\\\\\r' '\\\\\\\\n'" "$QML"; then ok "the log comes line by line, not in 4 KB blocks"; else no "the installer's output is block-buffered again"; fi
grep -q 'keyError ? Tr.t("The details below say why. Fix it in a terminal (fix-keyring' "$QML" \
    && ok "fix-keyring is named only for key errors" || no "the fix-keyring hint isn't tied to key errors"

echo ":: fix-keyring"
B="$T/bin"; L="$T/calls"
mkdir -p "$B"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$B/$1"; chmod 755 "$B/$1"; }
stub id 'echo 0'
stub timedatectl '[ "${1:-}" = show ] && echo yes; exit 0'
stub systemctl 'exit 0'
stub gpgconf 'exit 0'
stub pacman-key 'echo "pacman-key $*" >> "$CALLS"; [ "$1" != "--${FAIL_KEY:-none}" ]'
stub pacman 'echo "pacman $*" >> "$CALLS"; n=$(grep -c "^pacman -Sy" "$CALLS"); [ "$n" -gt "${REFUSE:-0}" ]'
stub archlinux-keyring-wkd-sync 'echo wkd >> "$CALLS"; [ -z "${WKD_FAILS:-}" ]'
run() {   # args… → exit code; the calls in $L, the output in $T/out
    : > "$L"; mkdir -p "$T/root/etc/pacman.d/gnupg"; touch "$T/root/etc/pacman.d/gnupg/pubring.gpg"
    env PATH="$B:$PATH" CALLS="$L" KEYRING_ROOT="$T/root" "$@" > "$T/out" 2>&1
}
calls() { paste -sd'|' "$L"; }

run "$FIX"; same "a fresh keyring: one update" "$?:$(calls)" "0:pacman -Sy --noconfirm archlinux-keyring"
[ -e "$T/root/etc/pacman.d/gnupg/pubring.gpg" ] && ok "without --reset the keys stay" || no "without --reset the keys were removed"

run env REFUSE=1 "$FIX"; same "refused: asks the key servers, then again" "$?:$(calls)" \
    "0:pacman -Sy --noconfirm archlinux-keyring|wkd|pacman -Sy --noconfirm archlinux-keyring"

run "$FIX" --reset; same "--reset: empty, init, populate, then the update" "$?:$(calls)" \
    "0:pacman-key --init|pacman-key --populate|pacman -Sy --noconfirm archlinux-keyring"
[ -e "$T/root/etc/pacman.d/gnupg/pubring.gpg" ] && no "--reset left the old keys" || ok "--reset removes the old keys"

run env FAIL_KEY=populate "$FIX" --reset
same "--reset stops when populate fails" "$?:$(calls)" "1:pacman-key --init|pacman-key --populate"

run env REFUSE=9 WKD_FAILS=1 "$FIX"
code=$?; same "still refused: fails" "$code" "1"
grep -q "fix-keyring --reset" "$T/out" && ok "and says to try --reset" || no "no --reset hint: $(tail -1 "$T/out")"
run env REFUSE=9 WKD_FAILS=1 "$FIX" --reset
grep -q "build a new ISO" "$T/out" && ok "refused after a reset: the ISO's keys are too old" || no "no hint after --reset: $(tail -1 "$T/out")"

stub id 'echo 1000'
run "$FIX"; same "not root: refused, nothing touched" "$?:$(calls)" "1:"

[ "$fails" = 0 ] && echo ":: all fine" || echo ":: $fails failed"
exit "$((fails > 0))"
