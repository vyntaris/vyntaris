import QtQuick
import qs.config

Text {
    property bool mono: false
    property bool caps: false

    color: Theme.text
    font.family: mono ? Theme.monoFamily : Theme.fontFamily
    font.pixelSize: caps ? Theme.fontSizeSmall : Theme.fontSize
    font.capitalization: caps ? Font.AllUppercase : Font.MixedCase
    font.letterSpacing: caps ? Theme.capsSpacing : 0
    font.weight: caps ? Font.DemiBold : Font.Normal
    font.features: mono ? { "tnum": 1 } : {}

    Behavior on color { ColorAnim {} }
}
