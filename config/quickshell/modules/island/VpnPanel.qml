import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 440
    readonly property real hang: content.implicitHeight + 26
    readonly property bool open: Panels.vpnOpen
    onOpenChanged: if (open) Vpn.findPlaces(); else Vpn.error = ""

    width: fullWidth
    height: Theme.barHeight + hang

    PanelHeader {
        icon: "vpn"
        title: Tr.t("VPN")
        Label {
            visible: Vpn.active !== null
            caps: true
            color: Theme.accent
            text: Vpn.active?.place || Vpn.active?.name || ""
        }
        Switch {
            checked: Vpn.active !== null
            onToggled: Vpn.quick()
        }
    }

    PanelBody {
        id: content

        Label {
            Layout.fillWidth: true
            visible: Vpn.places.length === 0 && Vpn.error === ""
            caps: true
            color: Theme.overlay1
            horizontalAlignment: Text.AlignHCenter
            text: Tr.t("Looking…")
        }
        GridLayout {
            Layout.fillWidth: true
            visible: Vpn.places.length > 0
            columns: 3
            rowSpacing: 8
            columnSpacing: 8
            Repeater {
                model: Vpn.places
                TileSurface {
                    id: tile
                    required property var modelData
                    readonly property bool on: Vpn.list.some(v => v.place === modelData.name && v.active)
                    readonly property bool busy: Vpn.busy === "riseup:" + modelData.name
                        || Vpn.list.some(v => v.place === modelData.name && Vpn.busy === v.uuid)
                    Layout.fillWidth: true
                    implicitHeight: 74
                    marked: on
                    solid: true
                    pressScale: 0.96
                    onActivated: Vpn.place(tile.modelData.name)

                    Spinner {
                        anchors { top: parent.top; right: parent.right; margins: 8 }
                        visible: tile.busy
                        size: 14
                        color: tile.on ? Theme.textOnAccent : Theme.accent
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: tile.modelData.country
                            font.pixelSize: Theme.fontSize + 4
                            font.weight: Font.DemiBold
                            color: tile.on ? Theme.textOnAccent : Theme.subtext0
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: tile.busy ? Tr.t("Connecting") : tile.modelData.name
                            font.pixelSize: Theme.fontSizeSmall
                            color: tile.on ? Theme.textOnAccent : Theme.subtext0
                        }
                    }
                }
            }
        }
        Label {
            Layout.fillWidth: true
            visible: Vpn.error !== ""
            text: Vpn.error
            wrapMode: Text.Wrap
            color: Theme.error
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
