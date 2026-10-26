.pragma library

var palettes = {
    latte: {
        rosewater: "#dc8a78",
        flamingo: "#dd7878",
        pink: "#ea76cb",
        mauve: "#8839ef",
        red: "#d20f39",
        maroon: "#e64553",
        peach: "#fe640b",
        yellow: "#df8e1d",
        green: "#40a02b",
        teal: "#179299",
        sky: "#04a5e5",
        sapphire: "#209fb5",
        blue: "#1e66f5",
        lavender: "#7287fd",
        text: "#4c4f69",
        subtext1: "#5c5f77",
        subtext0: "#6c6f85",
        overlay2: "#7c7f93",
        overlay1: "#8c8fa1",
        overlay0: "#9ca0b0",
        surface2: "#acb0be",
        surface1: "#bcc0cc",
        surface0: "#ccd0da",
        base: "#eff1f5",
        mantle: "#e6e9ef",
        crust: "#dce0e8",
    },
    frappe: {
        rosewater: "#f2d5cf",
        flamingo: "#eebebe",
        pink: "#f4b8e4",
        mauve: "#ca9ee6",
        red: "#e78284",
        maroon: "#ea999c",
        peach: "#ef9f76",
        yellow: "#e5c890",
        green: "#a6d189",
        teal: "#81c8be",
        sky: "#99d1db",
        sapphire: "#85c1dc",
        blue: "#8caaee",
        lavender: "#babbf1",
        text: "#c6d0f5",
        subtext1: "#b5bfe2",
        subtext0: "#a5adce",
        overlay2: "#949cbb",
        overlay1: "#838ba7",
        overlay0: "#737994",
        surface2: "#626880",
        surface1: "#51576d",
        surface0: "#414559",
        base: "#303446",
        mantle: "#292c3c",
        crust: "#232634",
    },
    macchiato: {
        rosewater: "#f4dbd6",
        flamingo: "#f0c6c6",
        pink: "#f5bde6",
        mauve: "#c6a0f6",
        red: "#ed8796",
        maroon: "#ee99a0",
        peach: "#f5a97f",
        yellow: "#eed49f",
        green: "#a6da95",
        teal: "#8bd5ca",
        sky: "#91d7e3",
        sapphire: "#7dc4e4",
        blue: "#8aadf4",
        lavender: "#b7bdf8",
        text: "#cad3f5",
        subtext1: "#b8c0e0",
        subtext0: "#a5adcb",
        overlay2: "#939ab7",
        overlay1: "#8087a2",
        overlay0: "#6e738d",
        surface2: "#5b6078",
        surface1: "#494d64",
        surface0: "#363a4f",
        base: "#24273a",
        mantle: "#1e2030",
        crust: "#181926",
    },
    mocha: {
        rosewater: "#f5e0dc",
        flamingo: "#f2cdcd",
        pink: "#f5c2e7",
        mauve: "#cba6f7",
        red: "#f38ba8",
        maroon: "#eba0ac",
        peach: "#fab387",
        yellow: "#f9e2af",
        green: "#a6e3a1",
        teal: "#94e2d5",
        sky: "#89dceb",
        sapphire: "#74c7ec",
        blue: "#89b4fa",
        lavender: "#b4befe",
        text: "#cdd6f4",
        subtext1: "#bac2de",
        subtext0: "#a6adc8",
        overlay2: "#9399b2",
        overlay1: "#7f849c",
        overlay0: "#6c7086",
        surface2: "#585b70",
        surface1: "#45475a",
        surface0: "#313244",
        base: "#1e1e2e",
        mantle: "#181825",
        crust: "#11111b",
    },
};

var accentNames = ["rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach",
                   "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender"];

function isCustom(name) {
    return typeof name === "string" && /^#[0-9a-fA-F]{6}$/.test(name);
}

function hsl(hex) {
    var r = parseInt(hex.substr(1, 2), 16) / 255, g = parseInt(hex.substr(3, 2), 16) / 255,
        b = parseInt(hex.substr(5, 2), 16) / 255;
    var max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
    var h = 0, s = 0;
    if (d > 0) {
        s = d / (1 - Math.abs(2 * l - 1));
        if (max === r) h = 60 * (((g - b) / d) % 6);
        else if (max === g) h = 60 * ((b - r) / d + 2);
        else h = 60 * ((r - g) / d + 4);
    }
    return { h: (h + 360) % 360, s: s, l: l };
}

function fromHsl(h, s, l) {
    h = ((h % 360) + 360) % 360;
    var c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = l - c / 2;
    var rgb = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x]
            : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
    return "#" + rgb.map(function (v) { return ("0" + Math.round((v + m) * 255).toString(16)).slice(-2); }).join("");
}

function isDark(pal) {
    return hsl(pal.base).l < 0.5;
}

function fit(color, dark) {
    var c = hsl(color);
    return dark ? fromHsl(c.h, Math.min(0.92, Math.max(0.6, c.s)), 0.77)
                : fromHsl(c.h, Math.min(0.85, Math.max(0.55, c.s)), 0.6);
}

function accent(pal, name) {
    return isCustom(name) ? fit(name, isDark(pal)) : (pal[name] || pal.blue);
}

function partnerOf(color) {
    var c = hsl(color);
    return fromHsl(c.h - 45, c.s, c.l);
}

function oklab(hex) {
    function lin(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
    var r = lin(parseInt(hex.substr(1, 2), 16) / 255), g = lin(parseInt(hex.substr(3, 2), 16) / 255),
        b = lin(parseInt(hex.substr(5, 2), 16) / 255);
    var l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    var m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    var s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
}

function nearest(pal, color) {
    if (!isCustom(color)) return color in pal ? color : "blue";
    var t = oklab(color), best = "mauve", dist = Infinity;
    for (var i = 0; i < accentNames.length; i++) {
        var p = oklab(pal[accentNames[i]]);
        var d = 0.3 * Math.pow(p[0] - t[0], 2) + Math.pow(p[1] - t[1], 2) + Math.pow(p[2] - t[2], 2);
        if (d < dist) { dist = d; best = accentNames[i]; }
    }
    return best;
}
