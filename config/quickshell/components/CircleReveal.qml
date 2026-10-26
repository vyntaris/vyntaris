import QtQuick
import QtQuick.Effects
import qs.config

Item {
    id: root
    default property alias content: holder.data
    property real progress: 1
    property int duration: Theme.duration(950)

    function run() {
        elapsed = 0;
        lastTick = 0;
        if (duration <= 0) { ticker.stop(); progress = 1; return; }
        progress = 0;
        ticker.restart();
    }

    property real elapsed: 0
    property real lastTick: 0
    FrameAnimation {
        id: ticker
        onTriggered: {
            const now = Date.now();
            if (root.lastTick > 0) root.elapsed += Math.min(now - root.lastTick, 50);
            root.lastTick = now;
            const t = Math.min(1, root.elapsed / root.duration);
            root.progress = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(2 - 2 * t, 3) / 2;
            if (t >= 1) stop();
        }
    }

    Item {
        id: holder
        anchors.fill: parent
        layer.enabled: root.progress < 1
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.25
        }
    }

    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        readonly property real full: Math.sqrt(width * width + height * height) / 2 + 40
        Rectangle {
            readonly property real r: Math.max(0.01, mask.full * root.progress)
            width: r * 2
            height: r * 2
            radius: r
            x: mask.width / 2 - r
            y: mask.height / 2 - r
            color: "white"
        }
    }
}
