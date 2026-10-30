.pragma library

var periods = ["morning", "day", "evening", "night"];
var nearest = {
    morning: ["morning", "day", "evening", "night"],
    day: ["day", "morning", "evening", "night"],
    evening: ["evening", "night", "day", "morning"],
    night: ["night", "evening", "morning", "day"],
};

function isTimes(path) {
    return (path || "").indexOf("times:") === 0;
}

function isDynamic(path) {
    return isTimes(path) || (path || "").indexOf("heic:") === 0;
}

function periodAt(minute) {
    return minute >= 360 && minute < 540 ? "morning"
        : minute >= 540 && minute < 1080 ? "day"
        : minute >= 1080 && minute < 1230 ? "evening"
        : "night";
}

function fileAt(path, minute) {
    if (!isTimes(path)) return path;
    var rest = path.slice(6), cut = rest.indexOf(":");
    var have = rest.slice(0, cut).split(","), pattern = rest.slice(cut + 1);
    var order = nearest[periodAt(minute)];
    for (var i = 0; i < order.length; i++)
        if (have.indexOf(order[i]) >= 0) return pattern.replace("{t}", order[i]);
    return "";
}

function timeSets(paths) {
    var sets = {}, rest = [];
    for (var i = 0; i < paths.length; i++) {
        var m = paths[i].match(/^(.*[_-])(morning|day|evening|night)(\.[A-Za-z0-9]+)$/);
        if (!m) { rest.push(paths[i]); continue; }
        var key = m[1] + "{t}" + m[3];
        (sets[key] = sets[key] || { have: [], paths: [] }).have.push(m[2]);
        sets[key].paths.push(paths[i]);
    }
    var out = [];
    for (var k in sets) {
        if (sets[k].have.length < 2) { rest = rest.concat(sets[k].paths); continue; }
        var have = periods.filter(function (p) { return sets[k].have.indexOf(p) >= 0; });
        out.push({
            path: "times:" + have.join(",") + ":" + k,
            title: k.replace(/^.*\//, "").replace(/[_-]\{t\}.*$/, ""),
        });
    }
    return { sets: out, rest: rest };
}

function base(path) {
    return (path || "").replace(/-light(\.[A-Za-z0-9]+)$/, "$1");
}

function isLight(path) {
    return /-light\.[A-Za-z0-9]+$/.test(path || "");
}

function same(a, b) {
    return !!a && !!b && base(a) === base(b);
}

function group(paths, dark) {
    var split = timeSets(paths), byBase = {}, out = split.sets;
    paths = split.rest;
    for (var i = 0; i < paths.length; i++) {
        var p = paths[i], b = base(p), e = byBase[b];
        if (/\.hei[cf]$/i.test(p)) {
            out.push({ path: "heic:" + p, title: p.replace(/^.*\//, "").replace(/\.[A-Za-z0-9]+$/, "").trim() });
            continue;
        }
        if (!e) {
            e = byBase[b] = { path: p, title: b.replace(/^.*\//, "").replace(/\.[A-Za-z0-9]+$/, "") };
            out.push(e);
        } else if (isLight(p) === !dark) {
            e.path = p;
        }
    }
    return out;
}
