#!/bin/bash
exec >/dev/ttyS1 2>&1
user="${1:-tester}"
dual="${2:-}"
fail=0
say() { echo "CI: $*"; }
bad() { echo "CI: FAIL $*"; fail=1; }
wait_for() {
    local secs="$1"; shift
    for ((i = 0; i < secs; i += 2)); do "$@" >/dev/null 2>&1 && return 0; sleep 2; done
    return 1
}

say "booted $(uname -r)"
say "ENTRY=$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f 2>/dev/null | tr -d '\000')"

modprobe qemu_fw_cfg 2>/dev/null
action="$(cat /sys/firmware/qemu_fw_cfg/by_name/opt/vyntaris/action/raw 2>/dev/null)"
if [ "$action" = bad-update ]; then
    timeout 300 systemctl is-system-running --wait >/dev/null 2>&1
    /usr/lib/vyntaris/update-guard pre | sed 's/^/CI:    /'
    mv /usr/bin/Hyprland /usr/bin/Hyprland.off
    /usr/lib/vyntaris/update-guard post | sed 's/^/CI:    /'
    say "update-guard: $(cat /var/lib/vyntaris/update-guard.json)"
    ls /boot/EFI/Linux /boot/loader/entries | sed 's/^/CI:    /'
    say "BAD-UPDATE-DONE"
    sync; systemctl reboot
    exit 0
fi
say "system: $(timeout 300 systemctl is-system-running --wait 2>/dev/null)"
failed="$(systemctl --failed --no-legend --plain | awk '{print $1}')"
for u in $failed; do bad "unit $u"; journalctl -b -u "$u" -n 6 --no-pager -o cat | sed 's/^/CI:    /'; done

grep -q '^NAME="Vyntaris"' /etc/os-release && say "os-release: $(. /etc/os-release; echo "$PRETTY_NAME $VERSION_ID")" || bad "os-release isn't Vyntaris"
pacman -Q vyntaris >/dev/null && say "$(pacman -Q vyntaris)" || bad "the vyntaris package isn't installed"
grep -q '^\[vyntaris\]' /etc/pacman.conf && say "the [vyntaris] repository is set" || bad "no [vyntaris] repository in pacman.conf"
sed -n '/^\[vyntaris\]/,/^\[/p' /etc/pacman.conf | grep -q '^SigLevel = Required' && say "it takes only signed packages" || bad "the [vyntaris] repository doesn't require signatures"
pacman-key --list-keys "$(cut -d: -f1 /usr/share/pacman/keyrings/vyntaris-trusted)" >/dev/null 2>&1 && say "pacman has Vyntaris's key" || bad "Vyntaris's signing key isn't in pacman's keyring"
[ -f /boot/EFI/Linux/vyntaris.efi ] && say "boot image vyntaris.efi" || bad "no /boot/EFI/Linux/vyntaris.efi"
[ "$(plymouth-set-default-theme 2>/dev/null)" = island ] && say "boot splash: island" || bad "the boot splash isn't set"
drv="$(/usr/lib/vyntaris/drivers 2>&1)"
if python3 -c 'import json,sys; d={x["id"]: x for x in json.load(sys.stdin)["devices"]}; sys.exit(0 if "vm-guest" in d and not d["vm-guest"]["missing"] else 1)' <<<"$drv"; then
    say "drivers: the virtual machine's guest tools are installed"
else bad "drivers: $drv"; fi
systemctl is-enabled -q vyntaris-drivers.timer && say "drivers: checked after every start" || bad "vyntaris-drivers.timer isn't enabled"

st="$(cat /var/lib/vyntaris/update-guard.json 2>/dev/null)"
grep -qE '"protected": ?true' <<<"$st" && say "safe updates: on" || bad "safe updates are off: $st"
if [ -f /var/lib/vyntaris/last-rollback ]; then
    say "ROLLED-BACK $(tr '\n' ' ' < /var/lib/vyntaris/last-rollback)"
    [ -x /usr/bin/Hyprland ] && say "the undone update's damage is gone" || bad "Hyprland is still missing after the rollback"
    compgen -G "/boot/EFI/Linux/vyntaris+*.efi" >/dev/null && bad "the failed update's boot image is still there" || say "the boot image is the one from before the update"
    [ -e /boot/loader/entries/vyntaris-rollback.conf ] && bad "the entry to undo it is still on the menu" || say "the boot menu's entry to undo it is gone"
fi
[ -f "/home/$user/.local/state/vyntaris/user-setup" ] && say "user setup done" || bad "vyntaris-user-setup never ran for $user"

if [ "$dual" = dual ]; then
    other="$(lsblk -lnpo NAME,LABEL | awk '$2 == "other" {print $1}')"
    if [ -n "$other" ] && mount -o ro "$other" /mnt 2>/dev/null; then
        [ "$(cat /mnt/marker 2>/dev/null)" = "the other system's" ] && say "the other system's partition is untouched" || bad "the other system's partition lost its contents"
        umount /mnt
    else bad "the other system's partition is gone"; fi
    findmnt -n /efi >/dev/null && say "the shared EFI partition is on /efi" || bad "no /efi"
    [ -f /efi/EFI/Microsoft/Boot/bootmgfw.efi ] && say "the other system's boot manager is still there" || bad "the other system's boot manager is gone"
    entries="$(bootctl list --no-pager 2>/dev/null)"
    grep -q "auto-windows\|Windows Boot Manager" <<<"$entries" && say "the boot menu lists the other system" || bad "the boot menu doesn't list the other system"
    grep -q "vyntaris.efi" <<<"$entries" && say "the boot menu lists Vyntaris" || bad "the boot menu doesn't list Vyntaris"
    t="$(sed -n 's/^timeout *//p' /efi/loader/loader.conf 2>/dev/null)"
    [ "${t:-0}" -gt 0 ] 2>/dev/null && say "the boot menu shows for $t s" || bad "the boot menu is hidden (timeout ${t:-not set})"
fi

if wait_for 180 pgrep -u greeter -f "qs -p /etc/greetd/greeter"; then say "login screen up"; else
    bad "no login screen"; journalctl -b -u greetd -n 15 --no-pager -o cat | sed 's/^/CI:    /'
fi
sleep 8
say "READY-FOR-LOGIN"

uid="$(id -u "$user")"
wait_for 240 pgrep -u "$user" -f "qs -c vyntaris" || true
pgrep -u "$user" -x Hyprland >/dev/null && say "Hyprland running" || bad "no Hyprland session for $user"
sleep 30
for u in vyntaris-shell.service vyntaris-wallpaper.service; do
    systemctl --user -M "$user@" is-active -q "$u" && say "$u active" || bad "$u isn't active"
done
for u in $(systemctl --user -M "$user@" --failed --no-legend --plain 2>/dev/null | awk '{print $1}'); do bad "user unit $u"; done
log="$(journalctl -b _SYSTEMD_USER_UNIT=vyntaris-shell.service _SYSTEMD_USER_UNIT=vyntaris-wallpaper.service --no-pager -o cat | sed 's/\x1b\[[0-9;]*m//g')"
errs="$(grep -E "^ ERROR( scene| qml)?:|Failed to load configuration|is not a type|non-existent property|Invalid property|Expected token|is not installed|ReferenceError|SyntaxError|TypeError|Cannot assign" <<<"$log")"
if [ -n "$errs" ]; then bad "the shell logged errors:"; sed 's/^/CI:    /' <<<"$errs" | head -20; else say "the shell logged no errors"; fi
say "the shell logged $(grep -c " WARN " <<<"$log") warnings"
grep " WARN " <<<"$log" | sort | uniq -c | sort -rn | head -8 | sed 's/^/CI:    /'
sig="$(ls "/run/user/$uid/hypr" 2>/dev/null | head -n1)"
cfg="$(runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl configerrors 2>&1)"
if [ -z "$(tr -d '[:space:]' <<<"$cfg")" ] || grep -qi "no errors" <<<"$cfg"; then say "Hyprland's config: no errors"; else
    bad "Hyprland's config:"; sed 's/^/CI:    /' <<<"$cfg" | head -10
fi

say "CHECK-RESULT=$([ "$fail" = 0 ] && echo ok || echo fail)"
