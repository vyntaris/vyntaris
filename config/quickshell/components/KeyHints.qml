import QtQuick
import qs.config

Label {
    property var keys: []
    caps: true
    font.pixelSize: Theme.fontSizeSmall - 1
    color: Theme.overlay0
    text: keys.map(k => k[0] + "  " + k[1]).join("     ")
}
