pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property bool canHibernate: false
    property bool lavd: false
    readonly property string lidAction: Config.power.lidAction || "suspend"

    function refresh() { hib.running = true; sched.running = true; }
    function lidClosed() {
        if (lidAction === "lock") LockState.lock();
        else if (lidAction === "hibernate" && canHibernate) Quickshell.execDetached(["sh", "-c", Config.power.hibernate]);
        else if (lidAction === "hibernate") Quickshell.execDetached(["sh", "-c", Config.power.suspend]);
    }

    Process {
        id: hib
        running: true
        command: ["sh", "-c", "grep -q 'resume=' /proc/cmdline && swapon --show=TYPE --noheadings | grep -q file"]
        onExited: code => root.canHibernate = code === 0
    }
    Process {
        id: sched
        running: true
        command: ["sh", "-c", "grep -q '^enabled' /sys/kernel/sched_ext/state && grep -q '^lavd' /sys/kernel/sched_ext/root/ops"]
        onExited: code => root.lavd = code === 0
    }

    Process {
        running: Panels.app === "" && root.lidAction !== "suspend"
        command: ["systemd-inhibit", "--what=handle-lid-switch", "--who=Desktop shell", "--why=Lid action set in Settings", "--mode=block", "sleep", "infinity"]
    }
}
