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

    readonly property var modes: [
        { id: "off",     label: Tr.t("Off"),       icon: "cup" },
        { id: "display", label: Tr.t("Screen on"), icon: "coffee" },
        { id: "system",  label: Tr.t("No sleep"),  icon: "coffee-moon" },
    ]

    PanelHeader {
        icon: KeepAwake.icon
        title: Tr.t("Keep awake")
        Label {
            visible: KeepAwake.active && KeepAwake.minutes > 0
            caps: true
            color: Theme.overlay1
            text: KeepAwake.format(KeepAwake.remaining)
        }
    }

    PanelBody {
        id: content

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.modes
                TileSurface {
                    id: opt
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 74
                    marked: KeepAwake.mode === modelData.id
                    pressScale: 0.96
                    onActivated: KeepAwake.set(opt.modelData.id)

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            name: opt.modelData.icon
                            size: 24
                            stroke: 1.6
                            color: opt.marked ? Theme.accent : Theme.subtext0
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            caps: true
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: opt.marked ? Theme.text : Theme.overlay1
                            text: opt.modelData.label
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            opacity: KeepAwake.active ? 1 : 0.45
            Behavior on opacity { Anim {} }

            Label { caps: true; color: Theme.overlay1; text: Tr.t("For") }
            Item { Layout.fillWidth: true }
            Choice {
                options: [{ value: 0, label: "∞" }, { value: 60, label: "1h" }, { value: 240, label: "4h" }]
                current: KeepAwake.minutes
                onPicked: v => KeepAwake.setMinutes(v)
            }
        }

        Meter {
            Layout.fillWidth: true
            visible: KeepAwake.active && KeepAwake.minutes > 0
            value: KeepAwake.remaining / Math.max(1, KeepAwake.minutes * 60)
        }
    }
}
