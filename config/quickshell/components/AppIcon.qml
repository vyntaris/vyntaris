import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.config

IconImage {
    id: root
    property bool themed: false
    property color tint: Theme.accent

    layer.enabled: themed
    layer.effect: MultiEffect {
        colorization: 1.0
        colorizationColor: root.tint
        brightness: 0.08
    }
}
