pragma Singleton
import Quickshell
import QtQuick

Singleton {
    readonly property QtObject theme: QtObject {
        readonly property string flavor: "mocha"
        readonly property string accent: "blue"
        readonly property string accentLight: "sky"
        readonly property real panelOpacity: 0.55
        readonly property string fontFamily: "Inter"
        readonly property string monoFamily: "JetBrains Mono"
        readonly property int fontSize: 13
        readonly property real animationSpeed: 1
        readonly property string animationStyle: "snappy"
        readonly property bool wallpaperTint: false
    }
    readonly property QtObject bar: QtObject {
        readonly property int height: 32
        readonly property int endCurve: 16
        readonly property string corners: "round"
        readonly property string notchStyle: "classic"
        readonly property string inside: "rounded"
        readonly property string clockFormat: "HH:mm"
    }
    readonly property QtObject accessibility: QtObject {
        readonly property bool highContrast: false
    }
}
