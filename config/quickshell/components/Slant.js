.pragma library

function lean(hang) {
    return Math.min(hang * 1.2, 26 + hang * 0.05);
}

function path(w, h, r, e) {
    const pts = [[-e.lt, 0], [w + e.rt, 0], [w + e.rb, h], [-e.lb, h]];
    const n = pts.length, f = v => v.toFixed(2);
    let p = "";
    for (let i = 0; i < n; i++) {
        const [cx, cy] = pts[i], [px, py] = pts[(i + n - 1) % n], [nx, ny] = pts[(i + 1) % n];
        const dp = Math.hypot(px - cx, py - cy) || 1, dn = Math.hypot(nx - cx, ny - cy) || 1;
        const k = Math.max(0, Math.min(r, dp / 2, dn / 2));
        const a = [cx + (px - cx) / dp * k, cy + (py - cy) / dp * k], b = [cx + (nx - cx) / dn * k, cy + (ny - cy) / dn * k];
        p += (i === 0 ? `M ${f(a[0])} ${f(a[1])}` : ` L ${f(a[0])} ${f(a[1])}`) + ` Q ${f(cx)} ${f(cy)} ${f(b[0])} ${f(b[1])}`;
    }
    return p + " Z";
}

function out(height, barHeight, y) {
    const drop = height - barHeight;
    return drop > 1 ? Math.max(0, lean(drop) * (height - y) / drop) : 0;
}
