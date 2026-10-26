pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import QtQuick

Singleton {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.enabled ?? false

    function setEnabled(on) {
        if (!adapter) return;
        if (!on) {
            adapter.enabled = false;
            Quickshell.execDetached(["rfkill", "block", "bluetooth"]);
            return;
        }
        Quickshell.execDetached(["rfkill", "unblock", "bluetooth"]);
        powerOn.restart();
    }
    function toggle() { setEnabled(!enabled); }

    onEnabledChanged: obex.restart()
    Component.onCompleted: obex.restart()
    Timer {
        id: obex
        interval: 1500
        onTriggered: Quickshell.execDetached(root.enabled
            ? ["systemctl", "--user", "start", "vyntaris-obex-agent.service"]
            : ["systemctl", "--user", "stop", "vyntaris-obex-agent.service", "obex.service"])
    }

    Timer { id: powerOn; interval: 400; onTriggered: if (root.adapter) root.adapter.enabled = true }
}
