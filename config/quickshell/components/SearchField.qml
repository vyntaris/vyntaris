import QtQuick
import qs.config

PanelSurface {
    id: root
    property alias text: field.text
    property string placeholder: Tr.t("Search…")
    readonly property alias input: field
    signal accepted()

    implicitWidth: 240
    implicitHeight: Theme.controlHeight
    radius: Theme.r(height / 2)
    fill: Theme.alpha(Theme.crust, 0.45)
    edgeWidth: field.activeFocus ? 2 : 1; edge: field.activeFocus ? Theme.accentInk : Theme.controlEdge
    Behavior on edge { ColorAnim {} }

    Rectangle {
        id: disc
        anchors { left: parent.left; leftMargin: Theme.space6; verticalCenter: parent.verticalCenter }
        width: parent.height - 10
        height: width
        radius: width / 2
        color: Theme.accent
        Icon { anchors.centerIn: parent; name: "search"; size: 16; color: Theme.textOnAccent }
    }
    TextInput {
        id: field
        activeFocusOnTab: true
        Accessible.role: Accessible.EditableText
        Accessible.name: root.placeholder
        anchors { left: disc.right; leftMargin: Theme.space12; right: parent.right; rightMargin: Theme.space16; verticalCenter: parent.verticalCenter }
        color: Theme.text
        selectionColor: Theme.accent
        selectedTextColor: Theme.textOnAccent
        font { family: Theme.fontFamily; pixelSize: Theme.fontSizeMedium }
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
