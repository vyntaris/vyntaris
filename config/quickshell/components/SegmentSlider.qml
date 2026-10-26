import QtQuick
import QtQuick.Layouts
import qs.config

RowLayout {
    id: root
    property real value: 0
    property string icon
    property int iconLevel: -1
    property bool dimmed: false
    property int count: 28
    readonly property alias shown: bar.shown
    property string valueText: Math.round(shown * 100)
    signal moved(real v)
    signal iconClicked()

    spacing: 12

    Icon {
        name: root.icon
        level: root.iconLevel
        size: 16
        color: root.dimmed ? Theme.overlay0 : Theme.subtext1
        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.iconClicked() }
    }

    Slider {
        id: bar
        Layout.fillWidth: true
        value: root.value
        count: root.count
        dimmed: root.dimmed
        onMoved: v => root.moved(v)
    }

    Label {
        Layout.preferredWidth: 30
        horizontalAlignment: Text.AlignRight
        mono: true
        font.pixelSize: Theme.fontSizeSmall + 1
        color: root.dimmed ? Theme.overlay1 : Theme.text
        text: root.valueText
    }
}
