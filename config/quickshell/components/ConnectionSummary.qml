import QtQuick
import QtQuick.Layouts
import qs.config

ColumnLayout {
    id: root
    property bool connected: false
    property string name
    property string icon
    property real level: -1
    property string detailIcon
    property string details
    property bool showDetails: true
    property bool canDisconnect: true
    signal disconnect()

    readonly property bool hasLevel: level >= 0
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label {
                caps: true
                color: root.connected ? Theme.accent : Theme.overlay1
                font.pixelSize: Theme.fontSizeSmall - 1
                text: root.connected ? Tr.t("Connected") : Tr.t("Not connected")
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSize + 6
                font.weight: Font.DemiBold
                color: root.connected ? Theme.text : Theme.subtext0
                text: root.name
            }
        }
        Icon {
            visible: !root.hasLevel
            name: root.icon
            size: 26
            stroke: 1.6
            color: root.connected ? Theme.accent : Theme.overlay0
        }
        Label {
            visible: root.hasLevel
            mono: true
            font.pixelSize: Theme.fontSize + 6
            font.weight: Font.Light
            color: Theme.accent
            text: Math.round(root.level * 100) + "%"
        }
    }

    Meter {
        Layout.fillWidth: true
        visible: root.hasLevel
        implicitHeight: 12
        count: 24
        value: Math.max(0, root.level)
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.showDetails
        spacing: 8
        Icon { visible: root.detailIcon !== ""; name: root.detailIcon; size: 13; color: Theme.overlay1 }
        Caption {
            Layout.fillWidth: true
            text: root.details
        }
        ChipButton { visible: root.connected && root.canDisconnect; danger: true; text: Tr.t("Disconnect"); onClicked: root.disconnect() }
    }
}
