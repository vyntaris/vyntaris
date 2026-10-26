import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import qs.config
import "Icons.js" as Icons

Image {
    id: root
    property string name: ""
    property color color: Theme.text
    property color dimColor: Theme.surface2
    property real size: 16
    property real stroke: 1.8
    property int level: -1
    property bool filled: {
        for (let p = parent; p; p = p.parent)
            if (p.solidIcons === true) return true;
        return false;
    }

    width: size
    height: size
    Layout.preferredWidth: size
    Layout.preferredHeight: size
    readonly property int px: Math.ceil(size * Screen.devicePixelRatio)
    sourceSize: Qt.size(px, px)
    source: name ? Icons.svg(name, color.toString(), dimColor.toString(), stroke, level, px, filled) : ""
    smooth: true
    cache: true
}
