pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

Singleton {
    readonly property var focused:
        Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
}
