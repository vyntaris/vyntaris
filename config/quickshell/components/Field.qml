import QtQuick
import qs.config

PanelSurface {
    id: root
    property alias text: input.text
    property string placeholder: ""
    property bool mono: false
    property bool secret: false
    property bool canReveal: false
    property bool invalid: false
    property bool revealed: false
    readonly property alias input: input
    signal committed(string text)

    implicitWidth: 220
    implicitHeight: Theme.controlHeight
    radius: Theme.r(height / 2)
    fill: Theme.alpha(Theme.text, input.activeFocus ? 0.09 : 0.05)
    edgeWidth: input.activeFocus ? 2 : 1
    edge: invalid ? Theme.error : input.activeFocus ? Theme.accent : Theme.alpha(Theme.text, 0.16)
    Behavior on fill { ColorAnim {} }
    Behavior on edge { ColorAnim {} }

    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 16; rightMargin: root.canReveal ? 44 : 16 }
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        selectionColor: Theme.accent
        selectedTextColor: Theme.textOnAccent
        font.family: root.mono ? Theme.monoFamily : Theme.fontFamily
        font.pixelSize: Theme.fontSize
        clip: true
        echoMode: root.secret && !root.revealed ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        onEditingFinished: root.committed(text)

        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text
            color: Theme.overlay1
            text: root.placeholder
        }
    }

    IconButton {
        visible: root.canReveal
        anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
        size: 30
        icon: root.revealed ? "eye-off" : "eye"
        on: root.revealed
        onClicked: { root.revealed = !root.revealed; input.forceActiveFocus(); }
    }
}
