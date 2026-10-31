import QtQuick
import qs.config

Label {
    property var keys: []
    overline: true
    font.pixelSize: Theme.fontSizeSmall
    color: Theme.overlay0
    text: keys.map(k => k[0] + "  " + k[1]).join("     ")
}
