import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 460
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
        icon: "gamepad"
        title: Tr.t("Game mode")
        Label {
            overline: true
            color: Theme.overlay1
            text: GameMode.active ? Tr.t("On") : Config.gameMode.auto ? Tr.t("Starts with games") : Tr.t("Off")
        }
    }

    PanelBody {
        id: content

        Row_ {
            text: Tr.t("Game mode")
            Switch { checked: ShellState.gameMode; onToggled: ShellState.toggle("gamemode") }
        }
        Row_ {
            text: Tr.t("Start by itself")
            Switch { checked: Config.gameMode.auto; onToggled: on => { Config.gameMode.auto = on; Config.saveSoon(); } }
        }
        Row_ {
            text: Tr.t("Silence notifications")
            Switch { checked: Config.gameMode.silence; onToggled: on => { Config.gameMode.silence = on; Config.saveSoon(); } }
        }
        Row_ {
            text: Tr.t("FPS and temperatures in the island")
            Switch { checked: Config.gameMode.stats; onToggled: on => { Config.gameMode.stats = on; Config.saveSoon(); } }
        }
        Row_ {
            text: Tr.t("Performance mode")
            Switch { checked: Config.gameMode.performance; onToggled: on => { Config.gameMode.performance = on; Config.saveSoon(); } }
        }
    }
}
