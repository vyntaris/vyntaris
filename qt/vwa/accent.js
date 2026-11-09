// WhatsApp in the theme's colours, changed in its own stylesheets: greys along the theme's shades, greens in the accent.
(() => {
    let accent = window.__vyntarisAccent, dark = window.__vyntarisDark, ramp = [];
    let done = new WeakSet(), mine = new WeakMap(), total = -1;
    const changed = [];

    function parse(v) {
        v = v.trim();
        let m = v.match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);
        if (m) {
            const x = m[1].length === 3 ? m[1].replace(/./g, c => c + c) : m[1];
            return { r: parseInt(x.slice(0, 2), 16), g: parseInt(x.slice(2, 4), 16), b: parseInt(x.slice(4, 6), 16), a: 1 };
        }
        m = v.match(/^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:\s*[,/]\s*([\d.]+)(%?))?\s*\)$/i);
        if (!m) return null;
        return { r: +m[1], g: +m[2], b: +m[3], a: m[4] === undefined ? 1 : m[5] ? m[4] / 100 : +m[4] };
    }

    function hsl({ r, g, b }) {
        r /= 255; g /= 255; b /= 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
        if (d === 0) return { h: 0, s: 0, l };
        const s = d / (1 - Math.abs(2 * l - 1));
        const h = max === r ? 60 * (((g - b) / d) % 6) : max === g ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4);
        return { h: (h + 360) % 360, s, l };
    }

    function css(h, s, l, a) {
        const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = l - c / 2;
        const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x]
            : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
        const v = n => Math.round((n + m) * 255);
        return `rgba(${v(r)}, ${v(g)}, ${v(b)}, ${a})`;
    }

    const green = c => c.h >= 135 && c.h <= 185 && c.s > 0.25;

    // Buttons, icons, ticks: the accent (darker on light pages). Bubbles and tints keep their lightness.
    function shade(c) {
        const A = hsl(parse(accent)), h = hsl(c);
        const mid = h.l > 0.25 && h.l < 0.65;
        return mid ? css(A.h, A.s, dark ? A.l : Math.min(A.l, 0.42), c.a) : css(A.h, Math.min(A.s, h.s), h.l, c.a);
    }

    // The theme's shades, darkest to lightest.
    function shades(list) {
        ramp = (list || []).map(parse).filter(Boolean).map(c => ({ c, l: hsl(c).l })).sort((a, b) => a.l - b.l);
    }

    // A grey's lightness, from black to white, picks the same place along the theme's shades.
    function neutral(c, h) {
        if (ramp.length < 2) return null;
        const t = ramp[0].l + (ramp[ramp.length - 1].l - ramp[0].l) * h.l;
        let i = 0;
        while (i < ramp.length - 2 && ramp[i + 1].l < t) i++;
        const a = ramp[i], b = ramp[i + 1], f = b.l === a.l ? 0 : Math.min(1, Math.max(0, (t - a.l) / (b.l - a.l)));
        const mix = k => Math.round(a.c[k] + (b.c[k] - a.c[k]) * f);
        return `rgba(${mix("r")}, ${mix("g")}, ${mix("b")}, ${c.a})`;
    }

    function recolour(style) {
        let own = mine.get(style);
        if (!own) mine.set(style, own = new Map());
        for (let i = 0; i < style.length; i++) {
            const p = style[i], v = style.getPropertyValue(p);
            if (own.get(p) === v) continue;
            const c = parse(v);
            if (!c) continue;
            const h = hsl(c), out = green(h) ? shade(c) : h.s < 0.35 ? neutral(c, h) : null;
            if (!out) continue;
            const priority = style.getPropertyPriority(p);
            changed.push([style, p, v, priority]);
            style.setProperty(p, out, priority);
            own.set(p, style.getPropertyValue(p));
        }
    }

    function walk(rules) {
        for (const r of rules) {
            if (r.cssRules) walk(r.cssRules);
            if (!r.style || done.has(r)) continue;
            done.add(r);
            recolour(r.style);
        }
    }

    // WhatsApp keeps adding rules as it goes.
    function scan(force) {
        if (!accent || !parse(accent)) return;
        for (const el of [document.documentElement, document.body]) if (el) recolour(el.style);
        const sheets = [...document.styleSheets];
        let n = 0;
        for (const sh of sheets) { try { n += sh.cssRules.length; } catch (e) {} }
        if (!force && n === total) return;
        total = n;
        for (const sh of sheets) { try { walk(sh.cssRules); } catch (e) {} }
    }

    window.__vyntarisRecolour = (hex, isDark, list) => {
        for (const [style, p, v, priority] of changed.splice(0).reverse()) style.setProperty(p, v, priority);
        accent = hex;
        dark = isDark;
        shades(list);
        done = new WeakSet();
        mine = new WeakMap();
        scan(true);
    };

    shades(window.__vyntarisShades);
    scan(true);
    setInterval(() => scan(false), 1500);
})();
