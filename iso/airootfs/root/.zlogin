if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

if [[ $(tty) == /dev/tty1 ]] && ! grep -q 'script=' /proc/cmdline && [[ ! -e /tmp/.installer-started ]]; then
    touch /tmp/.installer-started
    if ! grep -q 'installer=text' /proc/cmdline && command -v Hyprland >/dev/null; then
        Hyprland --config /usr/share/desktop-installer/hyprland.lua --i-am-really-stupid > /tmp/installer-hyprland.log 2>&1
    fi
    clear
    if [[ -e /tmp/.installer-text ]] || grep -q 'installer=text' /proc/cmdline || ! command -v Hyprland >/dev/null; then
        install-desktop || true
        command -v Hyprland >/dev/null && echo "The graphical installer: installer"
    else
        tail -n 8 /tmp/installer-hyprland.log 2>/dev/null
        df -h /run/archiso/cowspace 2>/dev/null | tail -n 1 | awk '{print "Room for changes: " $4 " free of " $2}'
        free -h | awk '/^Mem/ {print "Memory: " $7 " free of " $2}'
        echo "The graphical installer closed. Start it again: installer"
        echo "Or the text installer: install-desktop"
    fi
fi
