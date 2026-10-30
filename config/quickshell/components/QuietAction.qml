import QtQuick
import QtQuick.Layouts
import qs.config

// A round button that says what it does when the pointer is on it.
Rectangle {
    id: root
    property string icon
    property string text
    property int iconLevel: -1
    property color fill: Theme.alpha(Theme.text, 0.07)
    property color ink: Theme.subtext0
    property color hoverFill: Theme.error
    property color hoverInk: Theme.textOnAccent
    signal clicked()

    readonly property real wide: label.implicitWidth + 44
    implicitWidth: area.containsMouse ? wide : 32
    implicitHeight: 32
    Layout.alignment: Qt.AlignVCenter
    radius: Theme.r(16)
    clip: true
    color: area.containsMouse ? hoverFill : fill
    Behavior on color { ColorAnim {} }
    Behavior on implicitWidth { Anim { duration: Theme.durationFast } }

    Icon {
        id: glyph
        x: 9
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        level: root.iconLevel
        size: 14
        color: area.containsMouse ? root.hoverInk : root.ink
    }
    Label {
        id: label
        x: 31
        anchors.verticalCenter: parent.verticalCenter
        opacity: area.containsMouse ? 1 : 0
        font.pixelSize: Theme.fontSizeSmall + 1
        font.weight: Font.DemiBold
        color: root.hoverInk
        text: root.text
        Behavior on opacity { Anim { duration: Theme.durationFast } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
