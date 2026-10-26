import QtQuick
import QtQuick.Window
import QtQuick.Effects
import qs.config
import "LogoShape.js" as LogoShape
import "LogoArt.js" as LogoArt

Item {
    id: root
    property real size: 84
    property bool animated: false
    property var colors: Theme.palette
    property string accentName: Theme.accentName
    property color accent: LogoArt.accent(colors, accentName)
    property color partner: LogoArt.partner(colors, accentName)
    property color base: colors.base

    implicitWidth: size
    implicitHeight: size

    readonly property var shape: LogoShape.shape
    readonly property var orbit: shape.orbit
    readonly property bool small: size < 40
    readonly property real k: size / 24
    readonly property real dpr: Screen.devicePixelRatio || 1

    function hex(c) {
        return Qt.rgba(c.r, c.g, c.b, 1).toString();
    }
    function uri(viewBox, body, px) {
        return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(LogoArt.svg(viewBox, body, px));
    }
    readonly property string defs: LogoArt.defs(hex(accent), hex(partner), hex(base))
    readonly property string planetBody: LogoArt.planet(hex(accent))

    component Art: Image {
        property string body
        property bool load: visible
        readonly property int px: Math.ceil(28 * root.k * root.dpr)
        x: -2 * root.k
        y: -2 * root.k
        width: 28 * root.k
        height: 28 * root.k
        sourceSize: Qt.size(px, px)
        source: load && body ? root.uri("-2 -2 28 28", body, px) : ""
    }
    component Planet: Image {
        property real scaled: 1
        readonly property real full: 4.8 * root.orbit.planet.r * root.k
        readonly property int px: Math.ceil(full * 1.18 * root.dpr)
        width: full * scaled
        height: width
        sourceSize: Qt.size(px, px)
        source: visible ? root.uri("-2.4 -2.4 4.8 4.8", root.planetBody, px) : ""
    }

    Icon {
        visible: root.small
        name: "vyntaris"
        size: root.size
        color: root.accent
    }

    Art {
        visible: !root.small && !root.animated
        source: visible ? "data:image/svg+xml;charset=utf-8," + encodeURIComponent(LogoArt.full(root.hex(root.accent), root.hex(root.partner), root.hex(root.base), px)) : ""
    }

    Item {
        id: stage
        anchors.fill: parent
        visible: !root.small && root.animated

        property real t: 0
        FrameAnimation {
            running: stage.visible
            onTriggered: stage.t = (stage.t + frameTime * 3.2 * (1 + 0.45 * Math.sin(stage.t))) % (2 * Math.PI)
        }
        function spot(at) {
            const o = root.orbit, tilt = o.tilt * Math.PI / 180, ex = o.rx * Math.cos(at), ey = o.ry * Math.sin(at);
            return Qt.point((o.cx + ex * Math.cos(tilt) - ey * Math.sin(tilt)) * root.k,
                            (o.cy + ex * Math.sin(tilt) + ey * Math.cos(tilt)) * root.k);
        }
        function band(at) {
            const w = root.orbit.width;
            return (w[0] + (w[1] - w[0]) * Math.pow((1 - Math.cos(at)) / 2, 0.9)) * root.k;
        }
        readonly property string dot: root.uri("-1 -1 2 2", '<defs><radialGradient id="d" r="1" cx="0" cy="0" gradientUnits="userSpaceOnUse">'
            + '<stop offset="0" stop-color="' + LogoArt.mix(root.hex(root.accent), "#ffffff", 0.7) + '"/>'
            + '<stop offset="0.45" stop-color="' + LogoArt.mix(root.hex(root.accent), "#ffffff", 0.5) + '" stop-opacity="0.85"/>'
            + '<stop offset="1" stop-color="' + root.hex(root.accent) + '" stop-opacity="0"/></radialGradient></defs><circle r="1" fill="url(#d)"/>', 32)

        component Tail: Repeater {
            id: tail
            property bool front
            model: 40
            Image {
                required property int index
                readonly property real fall: 1 - index / 40
                readonly property real at: stage.t - 1.9 * index / 40
                readonly property point p: stage.spot(at)
                visible: (Math.sin(at) > 0) === tail.front
                width: 4 * stage.band(at) * (1 + 0.18 * Math.sin(at)) * (0.3 + 0.7 * fall)
                height: width
                x: p.x - width / 2
                y: p.y - height / 2
                source: stage.dot
                sourceSize: Qt.size(32, 32)
                opacity: 0.55 * Math.pow(fall, 1.6) * (tail.front ? 1 : 0.7)
            }
        }
        component Body: Planet {
            property bool front
            readonly property point p: stage.spot(stage.t)
            visible: (Math.sin(stage.t) > 0) === front
            scaled: 1 + 0.18 * Math.sin(stage.t)
            x: p.x - width / 2
            y: p.y - height / 2
            opacity: front ? 1 : 0.8
        }

        Item {
            x: -2 * root.k
            y: -2 * root.k
            width: 28 * root.k
            height: 28 * root.k
            layer.enabled: stage.visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskInverted: true
                maskSource: hide
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Item {
                x: 2 * root.k
                y: 2 * root.k
                Art { body: root.defs + LogoArt.layers("ring", ["back"]) }
                Tail { front: false }
                Body { front: false }
            }
        }
        Art {
            id: hide
            visible: false
            load: stage.visible
            layer.enabled: true
            body: '<path fill="#000" d="' + root.shape.ring.hide + '"/>'
        }

        Art { body: root.defs + LogoArt.layers("ring", ["v", "front"]) }
        Tail { front: true }
        Body { front: true }
    }
}
