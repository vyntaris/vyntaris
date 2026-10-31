import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 440
    readonly property real hang: content.implicitHeight + 26

    width: fullWidth
    height: Theme.barHeight + hang

    component Row_: RowLayout {
        property alias text: name.text
        Layout.fillWidth: true
        Layout.minimumHeight: 32
        spacing: Theme.space12
        Label { id: name; Layout.fillWidth: true; font.weight: Font.DemiBold }
    }

    PanelHeader {
        icon: "sunset"
        title: Tr.t("Night light")
        Label {
            visible: NightLight.active
            overline: true
            color: Theme.overlay1
            text: Config.nightLight.temperature + Tr.t(" K")
        }
    }

    PanelBody {
        id: content

        Row_ {
            text: Tr.t("Right now")
            Switch { checked: ShellState.nightLight; onToggled: ShellState.toggle("nightlight") }
        }
        Row_ {
            text: Tr.t("On a schedule")
            Switch { checked: Config.nightLight.automatic; onToggled: on => { Config.nightLight.automatic = on; Config.saveSoon(); } }
        }
        Row_ {
            visible: Config.nightLight.automatic
            text: Tr.t("From")
            Field { implicitWidth: 90; mono: true; text: Config.nightLight.start; onCommitted: t => { Config.nightLight.start = t.trim(); Config.saveSoon(); } }
            Label { text: Tr.t("until") ; color: Theme.subtext0 }
            Field { implicitWidth: 90; mono: true; text: Config.nightLight.end; onCommitted: t => { Config.nightLight.end = t.trim(); Config.saveSoon(); } }
        }
        Row_ {
            text: Tr.t("Warmth")
            Slider {
                label: Tr.t("Warmth")
                implicitWidth: 170
                value: (6500 - Config.nightLight.temperature) / 4000
                onMoved: v => { Config.nightLight.temperature = Math.round((6500 - v * 4000) / 100) * 100; Config.saveSoon(); }
            }
            Label { mono: true; Layout.preferredWidth: 56; horizontalAlignment: Text.AlignRight; text: Config.nightLight.temperature + Tr.t(" K") }
        }
    }
}
