import QtQuick
import qs.config

Text {
    property bool mono: false
    property bool overline: false

    color: Theme.text
    font.family: mono ? Theme.monoFamily : Theme.fontFamily
    font.pixelSize: overline ? Theme.fontSizeSmall : Theme.fontSize
    font.weight: overline ? Font.DemiBold : Font.Normal
    font.features: mono ? { "tnum": 1 } : {}

    Behavior on color { ColorAnim {} }
}
