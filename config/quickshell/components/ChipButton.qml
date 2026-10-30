import QtQuick
import QtQuick.Layouts
import qs.config

Rectangle {
    id: root
    property string text
    property string icon
    property bool danger: false
    property bool on: false
    signal clicked()
    readonly property color fill: danger ? Theme.error : Theme.accent

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 24
    radius: Theme.r(12)
    color: area.containsMouse ? fill : on ? Theme.accent : Theme.alpha(Theme.text, 0.06)
    border { width: 1; color: area.containsMouse ? fill : on ? Theme.accent : Theme.glassRim }
    Behavior on color { ColorAnim {} }

    readonly property color ink: area.containsMouse || on ? Theme.textOnAccent : Theme.subtext0
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon { visible: root.icon !== ""; name: root.icon; size: 12; color: root.ink }
        Label { caps: true; font.pixelSize: Theme.fontSizeSmall - 1; color: root.ink; text: root.text }
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
