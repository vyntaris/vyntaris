import QtQuick
import QtQuick.Shapes
import qs.config
import "Slant.js" as Slant

Shape {
    id: root
    property color fill
    property color stroke
    property real strokeWidth: 1
    property real radius: 0
    readonly property Item surface: parent
    readonly property Item view: {
        let v = null;
        for (let p = surface ? surface.parent : null; p; p = p.parent)
            if (p.hang !== undefined && p.fullWidth !== undefined) v = p;
        return v;
    }
    readonly property Item body: {
        for (let p = surface ? surface.parent : null; p && p !== view; p = p.parent)
            if (p.widest !== undefined && typeof p.blockOf === "function") return p;
        return null;
    }
    readonly property Item block: body ? (void body.blocks, body.blockOf(surface)) : null
    readonly property var edges: {
        if (!Theme.slanted || !view || !surface || !surface.visible) return null;
        void [surface.x, surface.y, surface.width, surface.height, surface.parent?.x, surface.parent?.y,
              surface.parent?.parent?.x, surface.parent?.parent?.y, surface.parent?.parent?.parent?.y,
              block?.x, block?.y, block?.width, view.width, view.height];
        const drop = view.height - Theme.barHeight;
        if (drop <= 1) return null;
        const inset = Theme.panelInset, lean = Slant.lean(drop), out = y => Math.max(0, lean * (view.height - y) / drop);
        const at = surface.mapToItem(view, 0, 0), w = surface.width, h = surface.height;
        let left, right;
        if (block || body) {
            const onLine = Math.abs(at.x - (inset - out(at.y + h))) < 1.5;
            const onLineR = Math.abs(view.width - inset + out(at.y + h) - (at.x + w)) < 1.5;
            const b = block ? block.mapToItem(view, 0, 0) : null;
            left = onLine || (b !== null && Math.abs(at.x - b.x) < 1.5);
            right = onLineR || (b !== null && Math.abs(at.x + w - (b.x + block.width)) < 1.5);
            if (!left && !right) return null;
        } else {
            left = at.x >= -1 && at.x <= 24; right = view.width - at.x - w >= -1 && view.width - at.x - w <= 24;
        }
        const l = body ? (y => Math.max(0, at.x - (inset - out(y)))) : (y => Math.max(0, out(y) - out(at.y + h)));
        const r = body ? (y => Math.max(0, view.width - inset + out(y) - (at.x + w))) : (y => Math.max(0, out(y) - out(at.y + h)));
        return { lt: left ? l(at.y) : 0, lb: left ? l(at.y + h) : 0, rt: right ? r(at.y) : 0, rb: right ? r(at.y + h) : 0 };
    }
    readonly property bool on: edges !== null && (edges.lt > 0.5 || edges.rt > 0.5)

    visible: on
    z: -1
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: root.fill
        strokeColor: root.stroke
        strokeWidth: root.strokeWidth
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: root.on ? Slant.path(root.surface.width, root.surface.height, root.radius, root.edges) : "" }
    }
}
