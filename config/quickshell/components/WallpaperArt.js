.pragma library
.import "LogoArt.js" as LogoArt

function rng(seed) {
    var s = seed >>> 0;
    return function () {
        s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
        return s / 4294967296;
    };
}

function f(x) {
    return (Math.round(x * 100) / 100).toString();
}

var styles = [
    { id: "minimal", title: "Vyntaris Minimal" },
    { id: "terrain", title: "Vyntaris Terrain" },
];

function scene(style, w, h, c) {
    return style === "terrain" ? terrain(w, h, c) : minimal(w, h, c);
}

function nebula(id, x, y, radius, color, opacity) {
    return '<radialGradient id="' + id + '" cx="' + f(x) + '" cy="' + f(y) + '" r="' + f(radius) + '" gradientUnits="userSpaceOnUse">'
        + '<stop offset="0" stop-color="' + color + '" stop-opacity="' + opacity + '"/>'
        + '<stop offset="0.5" stop-color="' + color + '" stop-opacity="' + f(opacity * 0.35) + '"/>'
        + '<stop offset="1" stop-color="' + color + '" stop-opacity="0"/></radialGradient>';
}

function open(w, h) {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + ' ' + h + '">';
}

function rect(w, h, fill) {
    return '<rect width="' + w + '" height="' + h + '" fill="' + fill + '"/>';
}

function mark(c, x, y, size, glow, glowOpacity) {
    var out = '';
    if (glow > 0)
        out += '<defs>' + nebula("mglow", x, y, glow, c.accent, glowOpacity) + '</defs>'
            + '<circle cx="' + f(x) + '" cy="' + f(y) + '" r="' + f(glow) + '" fill="url(#mglow)"/>';
    return out + LogoArt.full(c.accent, c.partner, c.base, size, true)
        .replace("<svg ", '<svg x="' + f(x - size / 2) + '" y="' + f(y - size / 2) + '" ');
}

function minimal(w, h, c) {
    var u = Math.min(w, h) / 1080, mix = LogoArt.mix, dark = c.dark !== false;
    var cx = w / 2, cy = h / 2, step = 30 * u;
    var out = open(w, h) + '<defs>'
        + '<pattern id="mdots" width="' + f(step) + '" height="' + f(step) + '" patternUnits="userSpaceOnUse">'
        + '<circle cx="' + f(step / 2) + '" cy="' + f(step / 2) + '" r="' + f(1.3 * u) + '" fill="' + c.text + '" fill-opacity="' + (dark ? 0.09 : 0.12) + '"/></pattern>'
        + nebula("mhaze", cx, cy, 0.42 * w, c.accent, dark ? 0.14 : 0.12)
        + '<radialGradient id="mfade" cx="' + f(cx) + '" cy="' + f(cy) + '" r="' + f(Math.hypot(cx, cy)) + '" gradientUnits="userSpaceOnUse">'
        + '<stop offset="0.35" stop-color="' + c.mantle + '" stop-opacity="0"/><stop offset="1" stop-color="' + c.mantle + '" stop-opacity="1"/></radialGradient>'
        + '</defs>' + rect(w, h, c.mantle) + rect(w, h, "url(#mdots)") + rect(w, h, "url(#mfade)") + rect(w, h, "url(#mhaze)");
    out += '<circle cx="' + f(cx) + '" cy="' + f(cy) + '" r="' + f(290 * u) + '" fill="none" stroke="' + c.accent + '" stroke-opacity="' + (dark ? 0.28 : 0.32) + '" stroke-width="' + f(1.5 * u) + '"/>'
        + '<circle cx="' + f(cx) + '" cy="' + f(cy) + '" r="' + f(306 * u) + '" fill="none" stroke="' + mix(c.accent, c.partner, 0.5) + '" stroke-opacity="0.12" stroke-width="' + f(1 * u) + '"/>';
    out += mark(c, cx, cy, 380 * u, 0, 0);
    return out + '</svg>';
}

function terrain(w, h, c) {
    var u = Math.min(w, h) / 1080, mix = LogoArt.mix, dark = c.dark !== false;

    var r = rng(20261021), lattice = [];
    for (var i = 0; i < 4096; i++) lattice.push(r());
    function at(ix, iy) { return lattice[((ix * 73856093) ^ (iy * 19349663)) & 4095]; }
    function noise(x, y) {
        var ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
        var sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
        var a = at(ix, iy), b = at(ix + 1, iy), d = at(ix, iy + 1), e = at(ix + 1, iy + 1);
        return a + (b - a) * sx + (d - a) * sy + (a - b - d + e) * sx * sy;
    }
    function layers(x, y, n) {
        var sum = 0, amp = 1, norm = 0;
        for (var k = 0; k < n; k++) {
            sum += amp * noise(x, y); norm += amp;
            amp *= 0.42; x = x * 2.03 + 17.1; y = y * 2.03 + 9.7;
        }
        return sum / norm;
    }
    function land(x, y) {
        var qx = layers(x * 0.8 + 3.2, y * 0.8 + 1.7, 2), qy = layers(x * 0.8 + 8.4, y * 0.8 + 5.3, 2);
        return layers(x * 0.95 + 1.1 * qx, y * 0.95 + 1.1 * qy, 4);
    }

    var cell = 7 * u, cols = Math.ceil(w / cell) + 1, rows = Math.ceil(h / cell) + 1, z = [], lo = 1, hi = 0;
    for (var y = 0; y < rows; y++) {
        var row = [];
        for (var x = 0; x < cols; x++) {
            var v = land(x * cell / h, y * cell / h);
            row.push(v); if (v < lo) lo = v; if (v > hi) hi = v;
        }
        z.push(row);
    }
    for (y = 0; y < rows; y++) for (x = 0; x < cols; x++) z[y][x] = (z[y][x] - lo) / (hi - lo);

    var levels = 40, paths = [];
    for (var l = 0; l < levels; l++) paths.push("");
    function cross(ax, ay, za, bx, by, zb, t) {
        var k = (t - za) / (zb - za);
        return f(ax + (bx - ax) * k) + " " + f(ay + (by - ay) * k);
    }
    for (y = 0; y < rows - 1; y++) {
        for (x = 0; x < cols - 1; x++) {
            var a = z[y][x], b = z[y][x + 1], e = z[y + 1][x + 1], d = z[y + 1][x];
            var mn = Math.min(a, b, e, d), mx = Math.max(a, b, e, d);
            var x0 = x * cell, y0 = y * cell, x1 = x0 + cell, y1 = y0 + cell;
            for (l = Math.ceil(mn * levels); l <= Math.floor(mx * levels) && l < levels; l++) {
                var t = l / levels;
                if (t <= mn || t >= mx) continue;
                var pts = [];
                if ((a < t) !== (b < t)) pts.push(cross(x0, y0, a, x1, y0, b, t));
                if ((b < t) !== (e < t)) pts.push(cross(x1, y0, b, x1, y1, e, t));
                if ((e < t) !== (d < t)) pts.push(cross(x1, y1, e, x0, y1, d, t));
                if ((d < t) !== (a < t)) pts.push(cross(x0, y1, d, x0, y0, a, t));
                if (pts.length === 2) paths[l] += "M" + pts[0] + "L" + pts[1];
                else if (pts.length === 4) {
                    var centre = (a + b + e + d) / 4;
                    if ((centre < t) === (a < t)) paths[l] += "M" + pts[0] + "L" + pts[1] + "M" + pts[2] + "L" + pts[3];
                    else paths[l] += "M" + pts[0] + "L" + pts[3] + "M" + pts[1] + "L" + pts[2];
                }
            }
        }
    }

    var fine = mix(c.text, c.accent, 0.45), bright = c.accent;
    var out = open(w, h) + '<defs>'
        + '<linearGradient id="tbg" x1="0" y1="0" x2="' + w + '" y2="' + h + '" gradientUnits="userSpaceOnUse">'
        + '<stop offset="0" stop-color="' + mix(c.base, c.accent, dark ? 0.04 : 0.03) + '"/>'
        + '<stop offset="0.55" stop-color="' + c.mantle + '"/>'
        + '<stop offset="1" stop-color="' + (dark ? c.crust : c.mantle) + '"/></linearGradient>'
        + nebula("tglow1", 0.27 * w, 0.32 * h, 0.5 * h, c.accent, dark ? 0.12 : 0.08)
        + nebula("tglow2", 0.74 * w, 0.66 * h, 0.55 * h, c.partner, dark ? 0.09 : 0.06)
        + '<filter id="tblur" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="' + f(3 * u) + '"/></filter>'
        + '<radialGradient id="tvig" cx="' + f(w / 2) + '" cy="' + f(h / 2) + '" r="' + f(Math.hypot(w, h) / 2) + '" gradientUnits="userSpaceOnUse">'
        + '<stop offset="0.55" stop-color="' + c.crust + '" stop-opacity="0"/>'
        + '<stop offset="1" stop-color="' + c.crust + '" stop-opacity="' + (dark ? 0.6 : 0.1) + '"/></radialGradient>'
        + '</defs>' + rect(w, h, "url(#tbg)") + rect(w, h, "url(#tglow1)") + rect(w, h, "url(#tglow2)");

    var index = '', minor = '';
    for (l = 1; l < levels; l++) {
        if (!paths[l]) continue;
        var lift = l / levels;
        if (l % 5 === 0) index += '<path d="' + paths[l] + '" stroke-opacity="' + f((dark ? 0.5 : 0.6) + 0.4 * lift) + '"/>';
        else minor += '<path d="' + paths[l] + '" stroke-opacity="' + f((dark ? 0.1 : 0.14) + 0.14 * lift) + '"/>';
    }
    out += '<g fill="none" stroke="' + fine + '" stroke-width="' + f(0.9 * u) + '" stroke-linecap="round">' + minor + '</g>';
    out += '<g fill="none" stroke="' + c.accent + '" stroke-width="' + f(4 * u) + '" stroke-linecap="round" filter="url(#tblur)" opacity="' + (dark ? 0.35 : 0.2) + '">' + index + '</g>';
    out += '<g fill="none" stroke="' + bright + '" stroke-width="' + f(1.6 * u) + '" stroke-linecap="round">' + index + '</g>';
    out += rect(w, h, "url(#tvig)");
    return out + '</svg>';
}
