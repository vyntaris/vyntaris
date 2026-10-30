import QtQuick
import qs.config

PanelSurface {
    id: root
    property alias text: field.text
    property string placeholder: Tr.t("Search…")
    readonly property alias input: field
    signal accepted()

    implicitWidth: 240
    implicitHeight: 38
    radius: Theme.r(height / 2)
    fill: Theme.alpha(Theme.crust, 0.45)
    edgeWidth: 1; edge: field.activeFocus ? Theme.accent : Theme.glassRim
    Behavior on edge { ColorAnim {} }

    Rectangle {
        id: disc
        anchors { left: parent.left; leftMargin: 5; verticalCenter: parent.verticalCenter }
        width: parent.height - 10
        height: width
        radius: width / 2
        color: Theme.accent
        Icon { anchors.centerIn: parent; name: "search"; size: 16; color: Theme.textOnAccent }
    }
    TextInput {
        id: field
        anchors { left: disc.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        color: Theme.text
        selectionColor: Theme.accent
        selectedTextColor: Theme.textOnAccent
        font { family: Theme.fontFamily; pixelSize: Theme.fontSize + 1 }
        clip: true
        onAccepted: root.accepted()
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !field.text
            color: Theme.overlay0
            text: root.placeholder
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: field.forceActiveFocus(); z: -1 }
}
