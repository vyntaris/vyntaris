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

    readonly property var options: [
        { key: "auto",        label: Tr.t("With games"),  icon: "play" },
        { key: "silence",     label: Tr.t("Quiet"),       icon: "bell-off" },
        { key: "performance", label: Tr.t("Performance"), icon: "power-performance", hidden: !Power.hasPerformance },
        { key: "stats",       label: Tr.t("FPS"),         icon: "thermometer" },
    ].filter(o => !o.hidden)

    PanelHeader {
        icon: "gamepad"
        title: Tr.t("Game mode")
        Switch { checked: GameMode.active; onToggled: GameMode.toggle() }
    }

    PanelBody {
        id: content

        GameStatsRow {
            Layout.alignment: Qt.AlignHCenter
            visible: Games.watching && Games.known
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8

            Repeater {
                model: root.options
                TileSurface {
                    id: opt
                    required property var modelData
                    readonly property bool on: Config.gameMode[modelData.key]
                    Layout.fillWidth: true
                    implicitHeight: 74
                    marked: on
                    solid: true
                    pressScale: 0.96
                    role: Accessible.CheckBox
                    checked: on
                    label: modelData.label
                    onActivated: { Config.gameMode[opt.modelData.key] = !opt.on; Config.saveSoon(); }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.space6
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            name: opt.modelData.icon
                            size: 22
                            stroke: 1.6
                            color: opt.marked ? Theme.textOnAccent : Theme.subtext0
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            overline: true
                            font.pixelSize: Theme.fontSizeSmall
                            color: opt.marked ? Theme.textOnAccent : Theme.overlay1
                            text: opt.modelData.label
                        }
                    }
                }
            }
        }
    }
}
