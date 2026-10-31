import QtQuick
import QtQuick.Layouts
import qs.config
import "Slant.js" as Slant

RowLayout {
    id: root
    property string icon
    property string title
    property color tint: Theme.accent
    default property alias trailing: trail.data

    property real inset: 22
    readonly property real flare: Theme.slanted && parent ? Slant.out(parent.height, Theme.barHeight, Theme.barHeight) : 0
    x: inset - flare
    width: parent.width - 2 * inset + 2 * flare
    height: Theme.barHeight
    spacing: Theme.space8

    Icon { visible: root.icon !== ""; name: root.icon; size: 14; color: Theme.ink(root.tint) }
    Label { overline: true; color: Theme.ink(root.tint); text: root.title }
    Item { Layout.fillWidth: true }
    RowLayout { id: trail; spacing: Theme.space6 }
}
