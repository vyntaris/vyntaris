#!/usr/bin/env bash
# vyntaris-setup's parts that decide what an update may change, on a stand-in system: the firewall a user edited stays,
# a service turned on once and then off stays off, root's old GTK links become a copy.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "   ok    $*"; }
no() { echo "   FAIL  $*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else no "$what"; fi; }

R="$T/sys"
mkdir -p "$T/bin" "$T/lib" "$R/usr/share/vyntaris" "$R/etc" "$R/root/.config" "$T/home/.config/gtk-3.0"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/bin/$1"; chmod 755 "$T/bin/$1"; }
stub id 'echo 0'
stub getent "echo 'ana:x:1000:1000::$T/home:/bin/zsh'"
stub systemd-detect-virt 'exit 0'   # "in a chroot": nothing is started, nft isn't run
stub systemctl 'case "$1" in cat) grep -qx "$2" "'"$T"'/units" ;; enable) echo "enable $2" >> "'"$T"'/enabled" ;; esac'
printf '#!/bin/sh\necho "$1" > "%s/synced"\n' "$T" > "$T/lib/greeter-sync.sh"; chmod 755 "$T/lib/greeter-sync.sh"
export PATH="$T/bin:$PATH"
printf 'a.timer\nb.service\n' > "$T/units"

# Its functions, on the stand-in system (VYNTARIS_SETUP_LIB: nothing of the main part runs)
setup() {
    # shellcheck disable=SC1090
    VYNTARIS_SETUP_LIB=1 VYNTARIS_SETUP_ROOT="$R" source "$REPO/system/bin/vyntaris-setup" "$@"
    set +e
    LIB="$T/lib"
}

echo ":: the firewall, through updates"
setup --user ana
ship() { printf '%s\n' "$1" > "$R/usr/share/vyntaris/nftables.conf"; }
ship "v1"; firewall >/dev/null
check "first time: installed"                     test "$(cat "$R/etc/nftables.conf")" = v1
check "… and what was shipped kept aside"         test "$(cat "$R/var/lib/vyntaris/nftables.conf.shipped")" = v1
ship "v2"; firewall >/dev/null
check "an update, nobody changed it: follows"     test "$(cat "$R/etc/nftables.conf")" = v2
echo "mine" > "$R/etc/nftables.conf"
ship "v3"; out="$(firewall)"
check "changed by the user: kept"                 test "$(cat "$R/etc/nftables.conf")" = mine
check "… the new one beside it"                   test "$(cat "$R/etc/nftables.conf.vyntaris-new")" = v3
check "… and said"                                grep -q vyntaris-new <<<"$out"
cp "$R/var/lib/vyntaris/nftables.conf.shipped" "$R/etc/nftables.conf"
ship "v4"; firewall >/dev/null
check "back to Vyntaris's: follows again"         test "$(cat "$R/etc/nftables.conf")" = v4
check "… the one beside it gone"                  test ! -e "$R/etc/nftables.conf.vyntaris-new"

echo ":: services: on once, then the user's"
: > "$T/enabled"
setup --user ana
enable a.timer b.service missing.service
check "the first setup turns them on"             test "$(grep -c enable "$T/enabled")" = 2
check "… not one that isn't there"                bash -c '! grep -q missing "$0"' "$T/enabled"
: > "$T/enabled"
setup --refresh
enable a.timer b.service
check "an update: not again (one turned off stays off)" bash -c '! grep -q . "$0"' "$T/enabled"
echo "c.timer" >> "$T/units"
enable a.timer c.timer
check "… but a new one is turned on"              test "$(cat "$T/enabled")" = "enable c.timer"
setup --user ana
: > "$T/enabled"; enable a.timer
check "setting up again by hand: turned on"       grep -q a.timer "$T/enabled"

echo ":: root's GTK theme, from links to a copy"
ln -s "$T/home/.config/gtk-3.0" "$R/root/.config/gtk-3.0"
ln -s "$T/home/.config/gtk-4.0" "$R/root/.config/gtk-4.0"
ln -s "$T/home/.config" "$R/root/.config/dconf"
setup --refresh
root_theme_links
check "the copy made for the folders' owner"      test "$(cat "$T/synced")" = "$(stat -c %U "$T/home/.config/gtk-3.0")"
check "the links gone"                            test ! -L "$R/root/.config/gtk-3.0" -a ! -L "$R/root/.config/gtk-4.0" -a ! -L "$R/root/.config/dconf"
rm -f "$T/synced"; root_theme_links
check "no links: nothing to do"                   test ! -e "$T/synced"

echo
[ "$fails" = 0 ] && echo "setup: all checks passed" || echo "setup: $fails failed"
exit $((fails > 0))
