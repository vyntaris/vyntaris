import QtQuick
import qs.config

PanelSurface {
    id: root
    property alias text: input.text
    property string placeholder: ""
    property bool mono: false
    property bool secret: false
    readonly property alias input: input
    signal committed(string text)

    implicitWidth: 220
    implicitHeight: 34
    radius: Theme.r(Theme.radius)
    fill: Theme.alpha(Theme.crust, 0.45)
    edgeWidth: 1; edge: input.activeFocus ? Theme.accent : Theme.glassRim
    Behavior on edge { ColorAnim {} }

    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        selectionColor: Theme.accent
        selectedTextColor: Theme.textOnAccent
        font.family: root.mono ? Theme.monoFamily : Theme.fontFamily
        font.pixelSize: Theme.fontSize
        clip: true
        echoMode: root.secret ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        onEditingFinished: root.committed(text)

        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text && !input.activeFocus
            color: Theme.overlay0
            text: root.placeholder
        }
    }
}
