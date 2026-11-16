import QtQuick
import qs.config

Text {
    property bool mono: false
    property bool overline: false

    // Text from outside (a notification, a Wi-Fi name, a window title) is shown as it is, never as HTML: rich
    // text could load pictures from anywhere. Places that want markup say so, and escape what goes in.
    textFormat: Text.PlainText
    color: Theme.text
    font.family: mono ? Theme.monoFamily : Theme.fontFamily
    font.pixelSize: overline ? Theme.fontSizeSmall : Theme.fontSize
    font.weight: overline ? Font.DemiBold : Font.Normal
    font.features: mono ? { "tnum": 1 } : {}

    Behavior on color { ColorAnim {} }
}
