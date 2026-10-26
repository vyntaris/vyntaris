import QtQuick
import QtQuick.Shapes
import qs.config
import "Slant.js" as Slant

Shape {
    id: root

    property real barHeight: Theme.barHeight
    property real corner: Theme.screenCorner
    property real shoulder: Theme.shoulder
    property real radius: Theme.drawerRadius
    property var drawers: []
    property string style: Config.bar.notchStyle
    property bool square: Theme.squareBar
    property real notchCorner: Theme.notchCorner

    preferredRendererType: Shape.CurveRenderer

    function f(n) { return n.toFixed(2); }

    function classic(d, L, R, B, bh) {
        const shy = Math.min(shoulder, Math.max(0, d.hang - notchCorner));
        const shx = shy > 0 ? shoulder : 0;
        const r = Math.max(0, Math.min(d.radius ?? radius, d.width / 2, d.hang - shy));
        return ` L ${f(R + shx)} ${f(bh)}`
             + ` A ${f(shx)} ${f(shy)} 0 0 0 ${f(R)} ${f(bh + shy)}`
             + ` L ${f(R)} ${f(B - r)}`
             + ` A ${f(r)} ${f(r)} 0 0 1 ${f(R - r)} ${f(B)}`
             + ` L ${f(L + r)} ${f(B)}`
             + ` A ${f(r)} ${f(r)} 0 0 1 ${f(L)} ${f(B - r)}`
             + ` L ${f(L)} ${f(bh + shy)}`
             + ` A ${f(shx)} ${f(shy)} 0 0 0 ${f(L - shx)} ${f(bh)}`;
    }

    function liquid(d, L, R, B, bh) {
        const fw = Math.max(shoulder, 10) * 2.6;
        const r = Math.max(0, Math.min((d.radius ?? radius) + 4, d.width / 2, d.hang * 0.5));
        const td = Math.max(0, Math.min(d.hang - r, fw * 0.9));
        return ` L ${f(R + fw)} ${f(bh)}`
             + ` C ${f(R + fw * 0.35)} ${f(bh)} ${f(R)} ${f(bh + td * 0.3)} ${f(R)} ${f(bh + td)}`
             + ` L ${f(R)} ${f(B - r)}`
             + ` A ${f(r)} ${f(r)} 0 0 1 ${f(R - r)} ${f(B)}`
             + ` L ${f(L + r)} ${f(B)}`
             + ` A ${f(r)} ${f(r)} 0 0 1 ${f(L)} ${f(B - r)}`
             + ` L ${f(L)} ${f(bh + td)}`
             + ` C ${f(L)} ${f(bh + td * 0.3)} ${f(L - fw * 0.35)} ${f(bh)} ${f(L - fw)} ${f(bh)}`;
    }

    function slant(d, L, R, B, bh) {
        const lean = Slant.lean(d.hang);
        const sh = square ? 0 : Math.min(shoulder * 0.8, lean + 4);
        const r = Math.max(0, Math.min(d.radius ?? radius, d.width / 2, d.hang * 0.6));
        return roundedPath([
            [R + lean + sh, bh], [R + lean, bh], [R, B], [L, B], [L - lean, bh], [L - lean - sh, bh]
        ], [0, sh, r, r, sh, 0]);
    }

    function bowl(d, L, R, B, bh) {
        const shy = Math.min(shoulder, Math.max(0, d.hang - notchCorner));
        const shx = shy > 0 ? shoulder : 0;
        const r = Math.max(0, Math.min(d.radius ?? radius, d.width / 2, d.hang - shy));
        const dip = Math.min(d.hang * 0.35, 14);
        return ` L ${f(R + shx)} ${f(bh)}`
             + ` A ${f(shx)} ${f(shy)} 0 0 0 ${f(R)} ${f(bh + shy)}`
             + ` L ${f(R)} ${f(B - r)}`
             + ` A ${f(r)} ${f(r)} 0 0 1 ${f(R - r)} ${f(B)}`
             + ` Q ${f(d.center)} ${f(B + dip * 2)} ${f(L + r)} ${f(B)}`
             + ` A ${f(r)} ${f(r)} 0 0 1 ${f(L)} ${f(B - r)}`
             + ` L ${f(L)} ${f(bh + shy)}`
             + ` A ${f(shx)} ${f(shy)} 0 0 0 ${f(L - shx)} ${f(bh)}`;
    }

    function ticket(d, L, R, B, bh) {
        const shy = Math.min(shoulder, Math.max(0, d.hang - notchCorner));
        const shx = shy > 0 ? shoulder : 0;
        const k = Math.max(0, Math.min(10, d.hang * 0.4, d.width / 4));
        return ` L ${f(R + shx)} ${f(bh)}`
             + ` A ${f(shx)} ${f(shy)} 0 0 0 ${f(R)} ${f(bh + shy)}`
             + ` L ${f(R)} ${f(B - k)}`
             + ` A ${f(k)} ${f(k)} 0 0 0 ${f(R - k)} ${f(B)}`
             + ` L ${f(L + k)} ${f(B)}`
             + ` A ${f(k)} ${f(k)} 0 0 0 ${f(L)} ${f(B - k)}`
             + ` L ${f(L)} ${f(bh + shy)}`
             + ` A ${f(shx)} ${f(shy)} 0 0 0 ${f(L - shx)} ${f(bh)}`;
    }

    function box(d, L, R, B, bh) {
        return ` L ${f(R)} ${f(bh)} L ${f(R)} ${f(B)} L ${f(L)} ${f(B)} L ${f(L)} ${f(bh)}`;
    }

    function chamfer(d, L, R, B, bh) {
        const c = Math.max(0, Math.min(12, d.hang * 0.45, d.width / 4));
        return ` L ${f(R + c)} ${f(bh)} L ${f(R)} ${f(bh + c)} L ${f(R)} ${f(B - c)} L ${f(R - c)} ${f(B)}`
             + ` L ${f(L + c)} ${f(B)} L ${f(L)} ${f(B - c)} L ${f(L)} ${f(bh + c)} L ${f(L - c)} ${f(bh)}`;
    }

    function pixel(d, L, R, B, bh) {
        const s = Math.max(1, Math.min(5, d.hang / 4));
        return ` L ${f(R + 2 * s)} ${f(bh)} L ${f(R + 2 * s)} ${f(bh + s)} L ${f(R + s)} ${f(bh + s)}`
             + ` L ${f(R + s)} ${f(bh + 2 * s)} L ${f(R)} ${f(bh + 2 * s)}`
             + ` L ${f(R)} ${f(B - 2 * s)} L ${f(R - s)} ${f(B - 2 * s)} L ${f(R - s)} ${f(B - s)}`
             + ` L ${f(R - 2 * s)} ${f(B - s)} L ${f(R - 2 * s)} ${f(B)}`
             + ` L ${f(L + 2 * s)} ${f(B)} L ${f(L + 2 * s)} ${f(B - s)} L ${f(L + s)} ${f(B - s)}`
             + ` L ${f(L + s)} ${f(B - 2 * s)} L ${f(L)} ${f(B - 2 * s)}`
             + ` L ${f(L)} ${f(bh + 2 * s)} L ${f(L - s)} ${f(bh + 2 * s)} L ${f(L - s)} ${f(bh + s)}`
             + ` L ${f(L - 2 * s)} ${f(bh + s)} L ${f(L - 2 * s)} ${f(bh)}`;
    }

    function roundedPath(pts, r) {
        let p = ` L ${f(pts[0][0])} ${f(pts[0][1])}`;
        for (let i = 1; i < pts.length - 1; i++) {
            const cx = pts[i][0], cy = pts[i][1], px = pts[i - 1][0], py = pts[i - 1][1], nx = pts[i + 1][0], ny = pts[i + 1][1];
            const dp = Math.hypot(px - cx, py - cy) || 1, dn = Math.hypot(nx - cx, ny - cy) || 1;
            const k = Math.min(r[i], dp / 2, dn / 2);
            if (k <= 0.01) { p += ` L ${f(cx)} ${f(cy)}`; continue; }
            p += ` L ${f(cx + (px - cx) / dp * k)} ${f(cy + (py - cy) / dp * k)}`
               + ` Q ${f(cx)} ${f(cy)} ${f(cx + (nx - cx) / dn * k)} ${f(cy + (ny - cy) / dn * k)}`;
        }
        const last = pts[pts.length - 1];
        return p + ` L ${f(last[0])} ${f(last[1])}`;
    }

    readonly property real endLean: style === "slant" ? 1.2 : 0

    function outline(closed) {
        const W = width, bh = barHeight, c = corner, e = c * endLean;
        let p = closed ? `M 0 0 L ${f(W)} 0 L ${f(W)} ${f(bh + c)}` : `M ${f(W)} ${f(bh + c)}`;
        if (c > 0 && e > 0) p += ` L ${f(W - e)} ${f(bh)}`;
        else if (c > 0) p += ` A ${f(c)} ${f(c)} 0 0 0 ${f(W - c)} ${f(bh)}`;

        const list = drawers.filter(d => d.hang > 0.5 && d.width > 1).sort((a, b) => b.center - a.center);
        for (const d of list) {
            const R = d.center + d.width / 2, L = d.center - d.width / 2, B = bh + d.hang;
            if (style === "slant") p += slant(d, L, R, B, bh);
            else if (style === "box") p += box(d, L, R, B, bh);
            else if (style === "chamfer") p += chamfer(d, L, R, B, bh);
            else if (style === "pixel") p += pixel(d, L, R, B, bh);
            else if (square) p += classic(d, L, R, B, bh);
            else if (style === "liquid") p += liquid(d, L, R, B, bh);
            else if (style === "bowl") p += bowl(d, L, R, B, bh);
            else if (style === "ticket") p += ticket(d, L, R, B, bh);
            else p += classic(d, L, R, B, bh);
        }

        if (c > 0 && e > 0) p += ` L ${f(e)} ${f(bh)} L 0 ${f(bh + c)}`;
        else {
            p += ` L ${f(c)} ${f(bh)}`;
            if (c > 0) p += ` A ${f(c)} ${f(c)} 0 0 0 0 ${f(bh + c)}`;
        }
        return closed ? p + " Z" : p;
    }

    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: 0; y1: 0; x2: 0; y2: root.barHeight + 120
            GradientStop { position: 0; color: Theme.glassTop }
            GradientStop { position: 1; color: Theme.glass }
        }
        PathSvg { path: root.outline(true) }
    }

    ShapePath {
        fillColor: "transparent"
        strokeColor: Theme.accent
        strokeWidth: 1.5
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathSvg { path: root.outline(false) }
    }
}
