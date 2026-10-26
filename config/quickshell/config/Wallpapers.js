.pragma library

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
    var byBase = {}, out = [];
    for (var i = 0; i < paths.length; i++) {
        var p = paths[i], b = base(p), e = byBase[b];
        if (!e) {
            e = byBase[b] = { path: p, title: b.replace(/^.*\//, "").replace(/\.[A-Za-z0-9]+$/, "") };
            out.push(e);
        } else if (isLight(p) === !dark) {
            e.path = p;
        }
    }
    return out;
}
