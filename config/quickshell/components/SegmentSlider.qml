import QtQuick
import QtQuick.Layouts
import qs.config

RowLayout {
    id: root
    property real value: 0
    property real maximum: 1
    property string icon
    property int iconLevel: -1
    property bool dimmed: false
    property int count: 28
    readonly property alias shown: bar.shown
    readonly property real level: bar.shown * maximum
    property string valueText: Math.round(level * 100)
    property string label
    property string iconLabel
    signal moved(real v)
    signal iconClicked()

    spacing: Theme.space12

    Icon {
        name: root.icon
        level: root.iconLevel
        size: 16
        color: root.dimmed ? Theme.overlay0 : Theme.subtext1
        PressArea { anchors.fill: parent; anchors.margins: -6; enabled: root.iconLabel !== ""; label: root.iconLabel; ringRadius: 6; onClicked: root.iconClicked() }
    }

    Slider {
        id: bar
        Layout.fillWidth: true
        value: root.value / root.maximum
        caution: 1 / root.maximum
        count: root.count
        label: root.label
        dimmed: root.dimmed
        onMoved: v => root.moved(v * root.maximum)
    }

    Label {
        Layout.preferredWidth: 30
        horizontalAlignment: Text.AlignRight
        mono: true
        font.pixelSize: Theme.fontSizeLabel
        color: root.dimmed ? Theme.overlay1 : Theme.text
        text: root.valueText
    }
}
