pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    FileView {
        id: file
        path: Quickshell.shellPath("greeter.json")
        blockLoading: true
    }
    readonly property var cfg: { try { return JSON.parse(file.text()); } catch (e) { return {}; } }

    readonly property QtObject theme: QtObject {
        readonly property string flavor: root.cfg.flavor || "mocha"
        readonly property string accent: root.cfg.accent || "blue"
        readonly property string accentLight: root.cfg.accentLight || "sky"
        readonly property string fontFamily: root.cfg.font || "Inter"
        readonly property string monoFamily: root.cfg.monoFont || "JetBrains Mono"
        readonly property int fontSize: root.cfg.fontSize || 13
        readonly property real animationSpeed: root.cfg.animationSpeed ?? 1
        readonly property string animationStyle: root.cfg.animationStyle || "snappy"
    }
    readonly property QtObject bar: QtObject {
        readonly property int height: root.cfg.barHeight || 28
        readonly property int endCurve: root.cfg.endCurve ?? 16
        readonly property string clockFormat: root.cfg.clockFormat || "HH:mm"
        readonly property string corners: root.cfg.corners || "round"
        readonly property string notchStyle: root.cfg.notchStyle || "classic"
        readonly property bool flatIsland: root.cfg.flatIsland ?? false
        readonly property bool endCorners: root.cfg.endCorners ?? true
        readonly property string inside: root.cfg.inside || "rounded"
    }
    readonly property QtObject accessibility: QtObject {
        readonly property bool highContrast: root.cfg.highContrast ?? false
    }
}
