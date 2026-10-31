import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.config
import qs.services

Scope {
    id: root

    property int warned: 101
    property int profileBefore: -1
    property real brightnessBefore: -1

    readonly property string beforeFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/vyntaris/power-saver-before"
    function remember() {
        const kept = profileBefore >= 0 || brightnessBefore >= 0;
        Quickshell.execDetached(["sh", "-c", kept ? 'mkdir -p "$(dirname "$1")" && echo "$2 $3" > "$1"' : 'rm -f "$1"',
                                 "sh", beforeFile, String(profileBefore), String(brightnessBefore)]);
    }
    Process {
        running: true
        command: ["cat", root.beforeFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const kept = text.trim().split(" ").map(Number);
                if (kept.length === 2 && !kept.some(isNaN)) {
                    root.profileBefore = kept[0];
                    root.brightnessBefore = kept[1];
                }
                root.check();
            }
        }
    }

    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "-a", Tr.t("Battery"), "-i", "battery-caution",
                                 "-u", urgency, title, body]);
    }

    Connections {
        target: Battery
        function onPercentChanged() { root.check(); }
        function onStatusChanged() { root.check(); }
    }

    readonly property bool toPerformance: Config.battery.performanceOnAC && Battery.available && Power.hasPerformance
    Connections {
        target: UPower
        function onOnBatteryChanged() { Qt.callLater(root.followCharger); }
    }
    property bool followed: false
    function followCharger() {
        if (!toPerformance) return;
        if (!UPower.onBattery) {
            if (GameMode.active) GameMode.profileBefore = PowerProfile.Performance;
            else Power.set(PowerProfile.Performance);
        } else if (GameMode.active) {
            if (GameMode.profileBefore === PowerProfile.Performance) GameMode.profileBefore = PowerProfile.Balanced;
        } else if (Power.profile === PowerProfile.Performance) {
            Power.set(PowerProfile.Balanced);
        }
    }

    function check() {
        if (!Battery.available || !Battery.device?.ready) return;
        if (!Battery.status || Battery.percent <= 0) return;
        if (!followed) { followed = true; if (!UPower.onBattery) followCharger(); }

        if (Battery.charging) {
            warned = 101;
            if (profileBefore >= 0) {
                if (!root.toPerformance) Power.set(profileBefore);
                profileBefore = -1;
            }
            if (brightnessBefore >= 0) {
                if (Brightness.available) Brightness.set(brightnessBefore);
                brightnessBefore = -1;
            }
            remember();
            return;
        }

        const p = Battery.percent;
        if (p <= Config.battery.critical && warned > Config.battery.critical) {
            warned = Config.battery.critical;
            notify("critical", Tr.f("Battery critically low: {0}%", p), Tr.t("Plug in the charger now."));
        } else if (p <= Config.battery.low && warned > Config.battery.low) {
            warned = Config.battery.low;
            let body = Tr.t("Plug in the charger soon.");
            if (Config.battery.autoPowerSaver && Power.profile !== PowerProfile.PowerSaver) {
                profileBefore = Power.profile;
                Power.set(PowerProfile.PowerSaver);
                if (Brightness.available && Brightness.value > 0.6) {
                    brightnessBefore = Brightness.value;
                    Brightness.set(0.6);
                }
                remember();
                body += " " + Tr.t("Power saver is on until it's charging.");
            }
            notify("normal", Tr.f("Battery low: {0}%", p), body);
        }
    }
}
