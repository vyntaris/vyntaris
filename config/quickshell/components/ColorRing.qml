import QtQuick
import qs.config
import "../config/Palettes.js" as Palettes

// Hue around, saturation across, at the eight accents' lightness. A colour typed as a hex code is used as it is.
Item {
    id: root
    property string color: ""
    property bool interactive: true
    signal picked(string color)
    // Where the pointer is while it's held; the colour is picked on letting go.
    property string draft: ""
    readonly property string shown: draft || color

    property real size: 132
    readonly property real outer: size / 2
    readonly property real inner: size * 0.3
    readonly property real minS: 0.6
    readonly property real maxS: 0.92
    readonly property real light: 0.77

    implicitWidth: size
    implicitHeight: size

    function at(h, s) { return Palettes.fromHsl(h, s, light); }
    readonly property var hs: {
        if (!Palettes.isCustom(shown)) return null;
        const c = Palettes.hsl(shown);
        return { h: c.h, s: Math.min(maxS, Math.max(minS, c.s)) };
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onAvailableChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const c = width / 2, bands = root.size > 60 ? 8 : 1, step = 3, band = (root.outer - root.inner) / bands;
            for (let b = 0; b < bands; b++) {
                const s = bands === 1 ? 0.8 : root.minS + (root.maxS - root.minS) * (b + 0.5) / bands;
                const r0 = root.inner + b * band, r1 = r0 + band + 0.6;
                for (let h = 0; h < 360; h += step) {
                    // Overlapping a little, so no seams show between the wedges.
                    const a0 = (h - 90 - 0.6) * Math.PI / 180, a1 = (h - 90 + step + 0.6) * Math.PI / 180;
                    ctx.beginPath();
                    ctx.arc(c, c, Math.min(r1, root.outer), a0, a1, false);
                    ctx.arc(c, c, r0, a1, a0, true);
                    ctx.closePath();
                    ctx.fillStyle = root.at(h + step / 2, s);
                    ctx.fill();
                }
            }
        }
    }

    // What it comes to in the theme.
    Rectangle {
        visible: root.hs !== null && root.interactive
        anchors.centerIn: parent
        width: root.inner * 1.3; height: width; radius: width / 2
        color: root.hs ? Palettes.settled(root.shown) : "transparent"
    }
    Rectangle {
        visible: root.hs !== null && root.interactive
        readonly property real r: root.inner + (root.outer - root.inner) * ((root.hs?.s ?? 0) - root.minS) / (root.maxS - root.minS)
        readonly property real a: ((root.hs?.h ?? 0) - 90) * Math.PI / 180
        x: root.outer + r * Math.cos(a) - width / 2
        y: root.outer + r * Math.sin(a) - height / 2
        width: 16; height: 16; radius: 8
        color: root.hs ? root.at(root.hs.h, root.hs.s) : "transparent"
        border { width: 2; color: Theme.isDark ? "#ffffff" : Theme.text }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: Qt.CrossCursor
        function pick(mouse) {
            const dx = mouse.x - root.outer, dy = mouse.y - root.outer, r = Math.sqrt(dx * dx + dy * dy);
            const t = Math.min(1, Math.max(0, (r - root.inner) / (root.outer - root.inner)));
            const h = (Math.atan2(dy, dx) * 180 / Math.PI + 450) % 360;
            root.draft = root.at(h, root.minS + (root.maxS - root.minS) * t);
        }
        onPressed: mouse => {
            const dx = mouse.x - root.outer, dy = mouse.y - root.outer, r = Math.sqrt(dx * dx + dy * dy);
            if (r > root.outer + 4 || r < root.inner - 4) { mouse.accepted = false; return; }
            pick(mouse);
        }
        onPositionChanged: mouse => { if (pressed) pick(mouse); }
        onReleased: { if (root.draft) root.picked(root.draft); root.draft = ""; }
        onCanceled: root.draft = ""
    }

    Accessible.role: Accessible.Dial
    Accessible.name: Tr.t("Custom color")
}
