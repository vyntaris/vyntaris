import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import qs.config
import qs.services

Item {
    id: root
    anchors.fill: parent
    z: 10

    readonly property Item volumeZone: volume
    readonly property Item brightnessZone: brightness
    readonly property Item cornerZone: corner

    readonly property var sink: Pipewire.defaultAudioSink?.audio ?? null
    PwObjectTracker { objects: [ Pipewire.defaultAudioSink ] }

    function setVolume(v) {
        if (!sink) return;
        sink.muted = false;
        sink.volume = Math.max(0, Math.min(1, v)) * Config.maxVolume;
    }

    component Strip: MouseArea {
        id: strip
        property bool on: true
        property bool atLeft: false
        property real value: 0
        signal changed(real value)

        x: atLeft ? 0 : root.width - width
        y: Theme.barHeight + Theme.notchDepth + 40
        width: on ? 2 : 0
        height: on ? Math.max(0, root.height - y - 40) : 0

        property real startY: 0
        property real startValue: 0
        onPressed: mouse => { startY = mouse.y; startValue = strip.value; }
        onPositionChanged: mouse => {
            if (pressed) strip.changed(startValue + (startY - mouse.y) / 400);
        }
        onWheel: wheel => {
            const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y / 120 : wheel.pixelDelta.y / 40;
            strip.changed(strip.value + d * 0.03);
        }
    }

    Strip {
        id: volume
        on: Config.edges.volume
        atLeft: false
        value: (root.sink?.volume ?? 0) / Config.maxVolume
        onChanged: v => root.setVolume(v)
    }

    Strip {
        id: brightness
        on: Config.edges.brightness && Brightness.available
        atLeft: true
        value: Brightness.value
        onChanged: v => Brightness.set(v)
    }

    MouseArea {
        id: corner
        readonly property string where: Config.edges.corner
        readonly property bool on: where !== "off" && where !== ""
        x: where.endsWith("right") ? root.width - width : 0
        y: where.startsWith("bottom") ? root.height - height : 0
        width: on ? 3 : 0
        height: on ? 3 : 0
        hoverEnabled: true

        property bool fired: false
        onContainsMouseChanged: {
            if (containsMouse) dwell.restart();
            else { dwell.stop(); fired = false; }
        }
        onClicked: Panels.overviewOpen = !Panels.overviewOpen
        Timer {
            id: dwell
            interval: 120
            onTriggered: {
                if (corner.fired) return;
                corner.fired = true;
                Panels.overviewOpen = !Panels.overviewOpen;
            }
        }
    }
}
