import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 420
    readonly property real hang: content.implicitHeight + 26

    width: fullWidth
    height: Theme.barHeight + hang

    readonly property var s: SystemStats

    function uptimeText(sec) {
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return (d > 0 ? d + "d " : "") + h + "h " + String(m).padStart(2, "0") + "m";
    }

    component Value: Label {
        mono: true
        font.pixelSize: Theme.fontSizeSmall + 1
        horizontalAlignment: Text.AlignRight
        Layout.minimumWidth: 58
    }

    component StatRow: RowLayout {
        property string icon
        property string label
        property real value: -1
        property string valueText
        property color tint: value > 0.85 ? Theme.error : value > 0.65 ? Theme.warning : Theme.accent
        Layout.fillWidth: true
        spacing: 10

        Icon { name: parent.icon; size: 16; color: Theme.overlay1 }
        Label { Layout.preferredWidth: 64; caps: true; color: Theme.overlay1; text: parent.label }
        Meter {
            Layout.fillWidth: true
            visible: parent.value >= 0
            implicitHeight: 8
            value: Math.max(0, parent.value)
            fillColor: parent.tint
        }
        Item { Layout.fillWidth: true; visible: parent.value < 0 }
        Value { text: parent.valueText }
    }

    PanelHeader {
        icon: "cpu"
        title: Tr.t("System")
        HeaderButton {
            icon: "terminal"
            onClicked: { Panels.systemOpen = false; Quickshell.execDetached(["vyntaris-monitor"]); }
        }
        Label { caps: true; color: Theme.overlay1; text: Tr.t("Up") }
        Label { mono: true; font.pixelSize: Theme.fontSizeSmall + 1; text: root.uptimeText(root.s.uptime) }
    }

    PanelBody {
        id: content
        spacing: 10

        StatRow {
            icon: "cpu"
            label: Tr.t("CPU")
            value: root.s.cpu
            valueText: Math.round(root.s.cpu * 100) + "%"
        }

        StatRow {
            icon: "memory"
            label: Tr.t("Memory")
            value: root.s.memory
            valueText: root.s.formatBytes(root.s.memUsed) + " / " + root.s.formatBytes(root.s.memTotal, 0)
        }

        StatRow {
            icon: "disk"
            label: Tr.t("Disk")
            value: root.s.disk
            valueText: root.s.formatBytes(root.s.diskUsed, 0) + " / " + root.s.formatBytes(root.s.diskTotal, 0)
        }

        StatRow {
            visible: root.s.temperature >= 0
            icon: "thermometer"
            label: Tr.t("Temp")
            value: Math.min(1, root.s.temperature / 100)
            tint: root.s.temperature > 85 ? Theme.error : root.s.temperature > 70 ? Theme.warning : Theme.accent
            valueText: Math.round(root.s.temperature) + " °C"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Icon { name: "wifi"; size: 16; color: Theme.overlay1 }
            Label { Layout.preferredWidth: 64; caps: true; color: Theme.overlay1; text: Tr.t("Network") }
            Item { Layout.fillWidth: true }
            Icon { name: "arrow-down"; size: 13; color: Theme.accent }
            Label {
                mono: true
                font.pixelSize: Theme.fontSizeSmall + 1
                Layout.minimumWidth: 72
                text: root.s.formatBytes(root.s.rxRate) + "/s"
            }
            Icon { name: "arrow-up"; size: 13; color: Theme.overlay1 }
            Label {
                mono: true
                font.pixelSize: Theme.fontSizeSmall + 1
                Layout.minimumWidth: 72
                horizontalAlignment: Text.AlignRight
                text: root.s.formatBytes(root.s.txRate) + "/s"
            }
        }
    }
}
