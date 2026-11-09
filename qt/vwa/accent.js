// WhatsApp in the theme's colours, changed in its own stylesheets: greys become the theme's shades, greens the accent.
(() => {
    let accent = window.__vyntarisAccent, ramp = [], hues = [];
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

    const rgba = (c, a) => `rgba(${c.r}, ${c.g}, ${c.b}, ${a})`;
    const green = c => c.h >= 135 && c.h <= 185 && c.s > 0.25;

    // The theme's colours (red, yellow, pink, teal, blue, mauve) by hue.
    function colours(list) {
        hues = (list || []).map(parse).filter(Boolean).map(c => ({ c, h: hsl(c).h }));
    }
    const apart = (a, b) => Math.min(Math.abs(a - b), 360 - Math.abs(a - b));

    // Greys: the theme's shades. Dark colours (behind coloured text): a dark shade. Greens: the accent.
    // Other colours: the theme's colour nearest in hue.
    function theme(c, h) {
        if (h.s < 0.35 || h.l < 0.3) return neutral(c, h);
        if (green(h)) return rgba(parse(accent), c.a);
        if (!hues.length) return null;
        return rgba(hues.reduce((best, t) => apart(t.h, h.h) < apart(best.h, h.h) ? t : best).c, c.a);
    }

    // The theme's shades, darkest to lightest.
    function shades(list) {
        ramp = (list || []).map(parse).filter(Boolean).map(c => ({ c, l: hsl(c).l })).sort((a, b) => a.l - b.l);
    }

    // A grey becomes the theme's shade at the same place between darkest and lightest.
    function neutral(c, h) {
        if (ramp.length < 2) return null;
        const t = ramp[0].l + (ramp[ramp.length - 1].l - ramp[0].l) * h.l;
        const near = ramp.reduce((best, s) => Math.abs(s.l - t) < Math.abs(best.l - t) ? s : best);
        return rgba(near.c, c.a);
    }

    // Own messages in the accent, their text in the theme's darkest colour (lightest, on a dark accent).
    const sheet = new CSSStyleSheet();
    let bubbleRules = "";
    function bubbles() {
        const A = parse(accent);
        if (!A || ramp.length < 2) return sheet.replaceSync("");
        const light = hsl(A).l > 0.6;
        const ink = rgba(light ? ramp[0].c : ramp[ramp.length - 1].c, 1);
        const soft = rgba(light ? ramp[Math.min(4, ramp.length - 1)].c : ramp[ramp.length - 2].c, 1);
        // Whatever draws the outgoing bubble, found in WhatsApp's styles so new class names don't matter.
        // and the loading screen's shine and pulse, which Chromium draws here as dark boxes over the logo.
        const found = new Set(), shine = new Set(), pulse = new Set();
        for (const sh of document.styleSheets) {
            try {
                for (const r of sh.cssRules) {
                    if (!r.style) continue;
                    if (/bubble-surface-outgoing\)/.test(r.style.getPropertyValue("background-color"))) found.add(r.selectorText);
                    if (/startup-background-rgb/i.test(r.style.getPropertyValue("background-image") + r.style.getPropertyValue("background"))) shine.add(r.selectorText);
                    if (/startup/.test(r.style.getPropertyValue("animation-name") + r.style.getPropertyValue("animation"))) pulse.add(r.selectorText);
                }
            } catch (e) {}
        }
        const inside = [...found].join(", ");
        const rules = (shine.size ? `${[...shine].join(", ")} { display: none !important; }\n` : "")
            + (pulse.size ? `${[...pulse].join(", ")} { animation: none !important; will-change: auto !important; }\n` : "") + `* { --WDS-systems-bubble-surface-outgoing: ${rgba(A, 1)} !important;
                --WDS-systems-bubble-surface-outgoing-RGB: ${A.r}, ${A.g}, ${A.b} !important; --outgoing-background: ${rgba(A, 1)} !important; }`
            + (inside ? `${inside} { color: ${ink} !important; --WDS-content-default: ${ink} !important; --primary: ${ink} !important;
                --primary-strong: ${ink} !important; --primary-stronger: ${ink} !important; --message-primary: ${ink} !important;
                --WDS-content-deemphasized: ${soft} !important; --secondary: ${soft} !important; --secondary-stronger: ${soft} !important;
                --WDS-systems-bubble-content-deemphasized: ${soft} !important; --bubble-meta: ${soft} !important;
                --bubble-meta-icon: ${soft} !important; --icon-ack: ${ink} !important; }` : "");
        if (rules !== bubbleRules) sheet.replaceSync(bubbleRules = rules);
        if (!document.adoptedStyleSheets.includes(sheet)) document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
    }

    function recolour(style) {
        let own = mine.get(style);
        if (!own) mine.set(style, own = new Map());
        for (let i = 0; i < style.length; i++) {
            const p = style[i], v = style.getPropertyValue(p);
            if (own.get(p) === v) continue;
            // Colours kept as bare "r, g, b" for rgba(var(...), a) are changed the same way.
            const bare = v.match(/^\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*$/);
            const c = bare ? { r: +bare[1], g: +bare[2], b: +bare[3], a: 1 } : parse(v);
            if (!c) continue;
            let out = theme(c, hsl(c));
            if (!out) continue;
            if (bare) out = out.replace(/^rgba\((\d+), (\d+), (\d+), [\d.]+\)$/, "$1, $2, $3");
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
        bubbles();
    }

    window.__vyntarisRecolour = (hex, isDark, list, others) => {
        colours(others);
        for (const [style, p, v, priority] of changed.splice(0).reverse()) style.setProperty(p, v, priority);
        accent = hex;
        shades(list);
        done = new WeakSet();
        mine = new WeakMap();
        scan(true);
    };

    // From the first moment, so the loading screen is in the theme too: new styles are recoloured as they come.
    let queued = false;
    const soon = () => {
        if (queued) return;
        queued = true;
        requestAnimationFrame(() => { queued = false; scan(false); });
    };
    new MutationObserver(soon).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["style"] });
    shades(window.__vyntarisShades);
    colours(window.__vyntarisHues);
    scan(true);
    setInterval(() => scan(false), 1500);
})();
