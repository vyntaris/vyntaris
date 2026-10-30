.pragma library
.import "LogoShape.js" as LogoShape
.import "../config/Palettes.js" as Palettes

var shape = LogoShape.shape;

function accent(palette, accentName) {
    return Palettes.accent(palette, accentName);
}

function partner(palette, accentName) {
    return mix(Palettes.accent(palette, accentName), "#000000", 0.28);
}

function mix(a, b, t) {
    var out = "#";
    for (var i = 1; i < 7; i += 2) {
        var x = parseInt(a.substr(i, 2), 16), y = parseInt(b.substr(i, 2), 16);
        out += ("0" + Math.round(x + (y - x) * t).toString(16)).slice(-2);
    }
    return out;
}

function svg(viewBox, body, px) {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="' + px + '" height="' + px + '" viewBox="' + viewBox + '">'
        + body + '</svg>';
}

function defs(accent, partnerColor, base) {
    var p = shape.orbit.planet, x0 = shape.orbit.cx - shape.orbit.rx, w = "#ffffff";
    return '<defs>'
        + '<linearGradient id="v" x1="2" y1="3" x2="20" y2="21" gradientUnits="userSpaceOnUse">'
        + '<stop offset="0" stop-color="' + mix(accent, w, 0.2) + '"/><stop offset="1" stop-color="' + partnerColor + '"/></linearGradient>'
        + '<linearGradient id="f" x1="' + x0 + '" y1="0" x2="' + p.x + '" y2="0" gradientUnits="userSpaceOnUse">'
        + '<stop offset="0" stop-color="' + mix(partnerColor, base, 0.2) + '"/><stop offset="0.55" stop-color="' + accent + '"/>'
        + '<stop offset="1" stop-color="' + mix(accent, w, 0.5) + '"/></linearGradient>'
        + '<linearGradient id="b" x1="' + x0 + '" y1="0" x2="' + p.x + '" y2="0" gradientUnits="userSpaceOnUse">'
        + '<stop offset="0" stop-color="' + mix(partnerColor, base, 0.2) + '"/><stop offset="1" stop-color="' + mix(accent, base, 0.5) + '"/></linearGradient>'
        + '</defs>';
}

function planet(accent, glow) {
    return '<defs><radialGradient id="g" r="2.4" cx="0" cy="0" gradientUnits="userSpaceOnUse">'
        + '<stop offset="0.3" stop-color="' + accent + '" stop-opacity="0.45"/><stop offset="0.55" stop-color="' + accent + '" stop-opacity="0.13"/>'
        + '<stop offset="1" stop-color="' + accent + '" stop-opacity="0"/></radialGradient>'
        + '<radialGradient id="p" cx="-0.35" cy="-0.4" r="1.35" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ffffff"/>'
        + '<stop offset="0.35" stop-color="' + mix(accent, "#ffffff", 0.5) + '"/><stop offset="1" stop-color="' + accent + '"/></radialGradient>'
        + '</defs>' + (glow === false ? '' : '<circle r="2.4" fill="url(#g)"/>') + '<circle r="1" fill="url(#p)"/>';
}

function layers(set, names) {
    var d = shape[set], out = "";
    for (var i = 0; i < names.length; i++) {
        var n = names[i];
        out += '<path fill="url(#' + (n === "back" ? "b" : n === "front" ? "f" : "v") + ')" d="' + d[n] + '"/>';
    }
    return out;
}

function full(accent, partnerColor, base, px, glow) {
    var p = shape.orbit.planet;
    return svg("-2 -2 28 28", defs(accent, partnerColor, base) + layers("full", ["back", "v", "front"])
        + '<g transform="translate(' + p.x + ' ' + p.y + ') scale(' + p.r + ')">' + planet(accent, glow) + '</g>', px);
}
