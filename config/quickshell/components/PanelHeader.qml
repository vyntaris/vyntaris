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
    // On whole pixels: the slant's flare is fractional, and an icon between two pixels comes out blurred.
    x: Math.round(inset - flare)
    width: parent.width - 2 * inset + 2 * flare
    height: Theme.barHeight
    spacing: Theme.space8

    Item {
        visible: root.icon !== ""
        Layout.preferredWidth: 14
        Layout.fillHeight: true
        Icon { y: Math.round((parent.height - size) / 2); name: root.icon; size: 14; color: Theme.ink(root.tint) }
    }
    Label { overline: true; color: Theme.ink(root.tint); text: root.title }
    Item { Layout.fillWidth: true }
    RowLayout { id: trail; spacing: Theme.space6 }
}
