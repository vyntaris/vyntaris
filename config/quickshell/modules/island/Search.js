.pragma library

function fuzzy(query, text) {
    var q = query.toLowerCase(), t = text.toLowerCase();
    if (!q) return { score: 0, positions: [] };

    var at = t.indexOf(q);
    if (at >= 0) {
        var pos = [];
        for (var k = 0; k < q.length; k++) pos.push(at + k);
        var wordStart = at === 0 || /[\s\-_.]/.test(t[at - 1]);
        return { score: 100 + q.length * 10 - at + (wordStart ? 40 : 0), positions: pos };
    }

    var positions = [], score = 0, ti = 0, prev = -2;
    for (var qi = 0; qi < q.length; qi++) {
        var found = t.indexOf(q[qi], ti);
        if (found < 0) return null;
        positions.push(found);
        if (found === prev + 1) score += 8;
        if (found === 0 || /[\s\-_.]/.test(t[found - 1])) score += 10;
        score -= Math.min(found - ti, 6);
        prev = found;
        ti = found + 1;
    }
    return { score: score, positions: positions };
}

function escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function highlight(text, positions, color) {
    if (!positions || positions.length === 0) return escape(text);
    var set = {};
    positions.forEach(function (p) { set[p] = true; });
    var out = "", open = false;
    for (var i = 0; i < text.length; i++) {
        if (set[i] && !open) { out += '<font color="' + color + '"><b>'; open = true; }
        if (!set[i] && open) { out += "</b></font>"; open = false; }
        out += escape(text[i]);
    }
    if (open) out += "</b></font>";
    return out;
}

var mathNames = {
    sqrt: "Math.sqrt", cbrt: "Math.cbrt", sin: "Math.sin", cos: "Math.cos", tan: "Math.tan",
    asin: "Math.asin", acos: "Math.acos", atan: "Math.atan", log: "Math.log10", ln: "Math.log",
    abs: "Math.abs", round: "Math.round", floor: "Math.floor", ceil: "Math.ceil", exp: "Math.exp",
    pi: "Math.PI", e: "Math.E",
};

function calculate(query) {
    var expr = query.trim().toLowerCase().replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/").replace(/π/g, "pi");
    if (!expr || !/\d|pi/.test(expr)) return null;
    var words = expr.match(/[a-z]+/g) || [];
    for (var i = 0; i < words.length; i++)
        if (!mathNames.hasOwnProperty(words[i])) return null;
    if (!/^[\d\s+\-*/().%^a-z]+$/.test(expr)) return null;
    if (words.length === 0 && !/[+\-*/%^]/.test(expr.replace(/^-/, ""))) return null;
    var js = expr.replace(/\^/g, "**").replace(/[a-z]+/g, function (w) { return mathNames[w]; });
    try {
        var value = Function('"use strict"; return (' + js + ");")();
        if (typeof value !== "number" || !isFinite(value)) return null;
        return Math.round(value * 1e10) / 1e10;
    } catch (e) {
        return null;
    }
}

var units = {
    length: { mm: 0.001, cm: 0.01, m: 1, km: 1000, "in": 0.0254, ft: 0.3048, yd: 0.9144, mi: 1609.344, nmi: 1852 },
    mass: { mg: 1e-6, g: 0.001, kg: 1, t: 1000, oz: 0.028349523125, lb: 0.45359237, st: 6.35029318 },
    data: { b: 1, kb: 1e3, mb: 1e6, gb: 1e9, tb: 1e12, kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776 },
    time: { ms: 0.001, s: 1, min: 60, h: 3600, d: 86400, wk: 604800, y: 31557600 },
    speed: { "m/s": 1, "km/h": 1 / 3.6, mph: 0.44704, kn: 0.514444 },
    volume: { ml: 0.001, cl: 0.01, dl: 0.1, l: 1, "m3": 1000, gal: 3.785411784, qt: 0.946352946, pt: 0.473176473, cup: 0.2365882365, floz: 0.0295735295625 },
    area: { "m2": 1, "km2": 1e6, ha: 1e4, "cm2": 1e-4, "ft2": 0.09290304, acre: 4046.8564224, "mi2": 2589988.110336 },
};
var aliases = {
    meter: "m", meters: "m", kilometer: "km", kilometers: "km",
    inch: "in", inches: "in", "\"": "in", foot: "ft", feet: "ft", yard: "yd", yards: "yd", mile: "mi", miles: "mi",
    gram: "g", grams: "g", kilo: "kg", kilos: "kg", kilogram: "kg", ton: "t", tons: "t",
    ounce: "oz", ounces: "oz", pound: "lb", pounds: "lb", lbs: "lb",
    byte: "b", bytes: "b", sec: "s", second: "s", seconds: "s", minute: "min", minutes: "min", mins: "min",
    hour: "h", hours: "h", hr: "h", day: "d", days: "d", week: "wk", weeks: "wk", year: "y", years: "y",
    kmh: "km/h", kph: "km/h", ms: "ms", knots: "kn", liter: "l", liters: "l", litre: "l", gallon: "gal", gallons: "gal",
    c: "°c", "°c": "°c", celsius: "°c", f: "°f", "°f": "°f", fahrenheit: "°f", k: "k", kelvin: "k",
};

function unitOf(name) {
    var n = name.toLowerCase();
    n = aliases[n] || n;
    if (n === "°c" || n === "°f" || n === "k") return { kind: "temp", key: n };
    for (var kind in units)
        if (units[kind].hasOwnProperty(n)) return { kind: kind, key: n };
    return null;
}

function toKelvin(v, u) { return u === "°c" ? v + 273.15 : u === "°f" ? (v - 32) * 5 / 9 + 273.15 : v; }
function fromKelvin(v, u) { return u === "°c" ? v - 273.15 : u === "°f" ? (v - 273.15) * 9 / 5 + 32 : v; }

function tidy(v) {
    var a = Math.abs(v);
    if (a !== 0 && (a < 1e-4 || a >= 1e12)) return v.toExponential(4);
    return String(Math.round(v * 1e4) / 1e4);
}

var display = {
    "°c": "°C", "°f": "°F", k: "K", b: "B", kb: "kB", mb: "MB", gb: "GB", tb: "TB",
    kib: "KiB", mib: "MiB", gib: "GiB", tib: "TiB", l: "L", ml: "mL", cl: "cL", dl: "dL",
    m3: "m³", m2: "m²", km2: "km²", cm2: "cm²", ft2: "ft²", mi2: "mi²",
};

function convert(query) {
    var m = query.trim().replace(/,/g, ".").match(/^(-?\d*\.?\d+)\s*([a-zA-Z°"\/0-9]+?)\s+(?:to|in|=|->|→)\s+([a-zA-Z°"\/0-9]+)$/i);
    if (!m) return null;
    var value = parseFloat(m[1]);
    var from = unitOf(m[2]), to = unitOf(m[3]);
    if (!from || !to || from.kind !== to.kind) return null;
    var result = from.kind === "temp"
        ? fromKelvin(toKelvin(value, from.key), to.key)
        : value * units[from.kind][from.key] / units[to.kind][to.key];
    var label = function (u) { return display[u] || u; };
    return { value: tidy(result) + " " + label(to.key), label: m[1] + " " + label(from.key) + " = " };
}

var shellsOwn = /^org\.kde\.kdeconnect[.-]/;
function listed(app) {
    return !app.noDisplay && !shellsOwn.test(app.id || "");
}

var categoryNames = {
    Development: "Development", Graphics: "Graphics", Network: "Internet", Office: "Office",
    AudioVideo: "Media", Audio: "Media", Video: "Media", Game: "Games",
    System: "System", Settings: "System", Utility: "Utility",
};
function category(app) {
    var cats = app.categories || [];
    for (var i = 0; i < cats.length; i++)
        if (categoryNames[cats[i]]) return categoryNames[cats[i]];
    return "";
}

function plain(text) {
    return text.toLowerCase().replace(/[?!.,]+$/g, "").replace(/\s+/g, " ").trim();
}

var switches = [
    { re: /\b(bluetooth|bt)\b/, action: "bluetooth", name: "Bluetooth", icon: "bluetooth" },
    { re: /\b(wi-?fi|wireless|wlan)\b/, action: "wifi", name: "Wi-Fi", icon: "wifi" },
    { re: /\b(do not disturb|dnd)\b/, action: "dnd", name: "Do not disturb", icon: "bell-off" },
    { re: /\b(notifications?)\b/, action: "dnd", name: "Do not disturb", icon: "bell-off", invert: true },
    { re: /\b(night ?light|blue light)\b/, action: "nightlight", name: "Night light", icon: "sunset" },
    { re: /\b(game ?mode)\b/, action: "gamemode", name: "Game mode", icon: "gamepad" },
    { re: /\b(keep awake|caffeine)\b/, action: "awake", name: "Keep awake", icon: "coffee" },
    { re: /\b(mic|microphone)\b/, action: "mic", name: "Microphone", icon: "mic" },
    { re: /\b(dark (mode|theme)|dark)\b/, action: "dark", name: "Dark mode", icon: "moon" },
];
var onWords = /\b(on|enable|start|turn on|switch on)\b/;
var offWords = /\b(off|disable|stop|turn off|switch off)\b/;

var oneShots = [
    { re: /^(lock|lock (the )?screen)$/, action: "lock", title: "Lock the screen", icon: "lock" },
    { re: /^(sleep|suspend)$/, action: "suspend", title: "Sleep", icon: "moon" },
    { re: /^(restart|reboot)$/, action: "reboot", title: "Restart", icon: "restart" },
    { re: /^(shut ?down|power off|turn off (the )?(computer|pc))$/, action: "shutdown", title: "Shut down", icon: "power" },
    { re: /^(log ?out|sign out)$/, action: "logout", title: "Log out", icon: "logout" },
    { re: /^(screenshot|take a screenshot)$/, action: "screenshot", title: "Take a screenshot", icon: "camera" },
    { re: /^(screenshot (of )?(an? )?(area|region|part))$/, action: "screenshot-region", title: "Screenshot of an area", icon: "camera" },
    { re: /^(record (the )?screen|screen recording)$/, action: "record", title: "Record the screen", icon: "record" },
    { re: /^(updates?|update (the )?(system|everything|computer)|check for updates)$/, action: "updates", title: "Updates", icon: "package-update" },
    { re: /^(doctor|dr\.? ?help|system health|check (my |the )?(system|computer|pc)|fix (my |the )?(system|computer|pc)|what'?s wrong( with my (computer|pc))?)$/, action: "health", title: "Open Dr. Help", icon: "health" },
    { re: /^((install )?drivers)$/, action: "drivers", title: "Drivers", icon: "cpu" },
    { re: /^(set ?up (for )?(games|gaming)|gaming set ?up|install steam|(install|get) (games|steam and lutris))$/, action: "games-setup", title: "Set up for games: Steam, Lutris, Proton", icon: "gamepad" },
    { re: /^(sound|audio|speakers?|headphones|sound (settings|devices|output|input)|audio (settings|devices|output|input)|(output|input) devices?)$/, action: "sound", title: "Sound", icon: "volume" },
    { re: /^(empty (the )?(trash|bin))$/, action: "trash", title: "Empty the trash", icon: "trash" },
    { re: /^(mute|mute (the )?(sound|audio))$/, action: "mute", value: true, title: "Mute the sound", icon: "volume-x" },
    { re: /^(unmute|unmute (the )?(sound|audio))$/, action: "mute", value: false, title: "Unmute the sound", icon: "volume" },
    { re: /^(find (my )?phone|ring (my )?phone|where'?s my phone|lost (my )?phone)$/, action: "phone-ring", title: "Find my phone", icon: "phone-ring" },
    { re: /^((send )?clipboard to (my )?phone|copy to (my )?phone)$/, action: "phone-clipboard", title: "Send the clipboard to the phone", icon: "clipboard" },
    { re: /^((my )?phone|kde ?connect|phone link|pair (a |my )?phone)$/, action: "phone", title: "Phone", icon: "smartphone" },
    { re: /^(undo (the )?(last )?update)$/, action: "undo-update", title: "Undo the last update", icon: "history" },
];

function understand(query, pages, tr) {
    var q = plain(query);
    if (q.length < 2) return null;
    var i, m;
    for (i = 0; i < oneShots.length; i++)
        if (oneShots[i].re.test(q))
            return { action: oneShots[i].action, value: oneShots[i].value, title: tr(oneShots[i].title), icon: oneShots[i].icon };

    m = q.match(/^(?:set (?:the )?)?(volume|sound|brightness)(?: to)? (\d{1,3}) ?%?$/);
    if (m) {
        var n = Math.min(100, parseInt(m[2]));
        var vol = m[1] !== "brightness";
        return { action: vol ? "volume" : "brightness", value: n / 100, icon: vol ? "volume" : "sun",
                 title: (vol ? tr("Volume") : tr("Brightness")) + " " + n + " %" };
    }

    if (/^(light (mode|theme))$/.test(q))
        return { action: "dark", value: false, title: tr("Turn {0} off").replace("{0}", tr("Dark mode")), icon: "sun" };

    var on = onWords.test(q), off = offWords.test(q);
    for (i = 0; i < switches.length; i++) {
        var s = switches[i];
        if (!s.re.test(q)) continue;
        var rest = q.replace(s.re, "").replace(onWords, "").replace(offWords, "").replace(/\b(the|turn|switch|please)\b/g, "").trim();
        if (rest.length > 0 && !(s.action === "dark" && /^(mode|theme)$/.test(rest))) continue;
        if (on === off && s.action !== "dark") return { action: s.action, value: null, title: tr("Toggle {0}").replace("{0}", tr(s.name)), icon: s.icon };
        var want = s.action === "dark" && on === off ? true : on;
        if (s.invert) want = !want;
        return { action: s.action, value: want, title: (want ? tr("Turn {0} on") : tr("Turn {0} off")).replace("{0}", tr(s.name)), icon: s.icon };
    }

    m = q.match(/^(?:open )?(?:(.+?) (?:settings|preferences)|settings (?:for )?(.+))$/);
    if (m && pages) {
        var what = m[1] || m[2];
        for (i = 0; i < pages.length; i++) {
            var p = pages[i];
            var words = plain(p.label + " " + p.keywords).split(" ");
            if (plain(p.label) === what || words.indexOf(what) >= 0 || words.some(function (w) {
                return w.length > 3 && (w.indexOf(what) === 0 || what === w + "s");
            }))
                return { action: "settings", value: p.id, title: tr("Open {0} settings").replace("{0}", tr(p.label)), icon: p.icon };
        }
    }
    return null;
}

function command(query, pages, tr, lang) {
    tr = tr || function (s) { return s; };
    var c = understand(query, pages, tr);
    if (c || !lang || !phrasebooks[lang]) return c;
    var q = fold(plain(query));
    var book = phrasebooks[lang];
    for (var i = 0; i < book.length; i++)
        q = q.replace(new RegExp("(^|\\s)(?:" + book[i][0] + ")(?=\\s|$)", "g"), "$1" + book[i][1]);
    return understand(q.replace(/\s+/g, " ").trim(), pages, tr);
}

function fold(text) {
    return text.normalize("NFD").replace(/[̀-ͯ]/g, "")
        .replace(/đ/g, "dj").replace(/ł/g, "l").replace(/ß/g, "ss").replace(/[’']/g, " ");
}

var phrasebooks = {
    sr: [
        ["ugasi racunar|iskljuci racunar|ugasi kompjuter|iskljuci kompjuter", "shut down"],
        ["ponovo pokreni|restartuj|restart racunara", "restart"],
        ["odjavi se|odjava", "log out"],
        ["zakljucaj ekran|zakljucaj", "lock"],
        ["uspavaj|spavanje|stanje spavanja", "sleep"],
        ["snimak dela ekrana|slikaj deo ekrana", "screenshot of an area"],
        ["snimak ekrana|slikaj ekran|skrinsot", "screenshot"],
        ["snimaj ekran|snimi ekran|snimanje ekrana", "record the screen"],
        ["ponisti azuriranje|ponisti poslednje azuriranje|vrati azuriranje", "undo the last update"],
        ["azuriraj sistem|azuriraj|azuriranja|proveri azuriranja", "updates"],
        ["proveri sistem|proveri racunar|popravi sistem|popravi racunar|sta nije u redu", "check my system"],
        ["instaliraj drajvere|drajveri", "drivers"],
        ["isprazni korpu|isprazni kantu|isprazni otpad", "empty the trash"],
        ["vrati zvuk|ukljuci zvuk", "unmute"],
        ["utisaj|utisaj zvuk|iskljuci zvuk", "mute"],
        ["nadji telefon|pronadji telefon|gde mi je telefon|zazvoni telefon", "find my phone"],
        ["posalji na telefon|posalji privremenu memoriju na telefon", "send clipboard to phone"],
        ["telefon", "phone"],
        ["nocno svetlo|nocno svetlo", "night light"],
        ["ne uznemiravaj", "do not disturb"],
        ["obavestenja|obavestenje", "notifications"],
        ["rezim za igre|rezim igre", "game mode"],
        ["drzi budnim|ne spavaj", "keep awake"],
        ["mikrofon", "microphone"],
        ["tamni rezim|tamna tema|tamno", "dark mode"],
        ["svetli rezim|svetla tema|svetlo", "light mode"],
        ["jacin\\w*|glasnoc\\w*", "volume"],
        ["osvetljenost\\w*|svetlin\\w*", "brightness"],
        ["zvuk", "sound"],
        ["podesi|postavi|stavi", "set"],
        ["na", "to"],
        ["ukljuci|upali|pokreni|aktiviraj", "on"],
        ["iskljuci|ugasi|zaustavi|deaktiviraj", "off"],
    ],
    de: [
        ["computer ausschalten|herunterfahren|pc ausschalten", "shut down"],
        ["neu starten|neustarten|neustart", "restart"],
        ["abmelden", "log out"],
        ["bildschirm sperren|sperren", "lock"],
        ["bereitschaft|schlafen|energie sparen", "sleep"],
        ["bildschirmfoto eines bereichs|bereich aufnehmen", "screenshot of an area"],
        ["bildschirmfoto|screenshot", "screenshot"],
        ["bildschirm aufnehmen|bildschirmaufnahme", "record the screen"],
        ["update ruckgangig machen|letztes update ruckgangig machen", "undo the last update"],
        ["system aktualisieren|aktualisieren|updates", "updates"],
        ["system prufen|computer prufen|was ist los", "check my system"],
        ["treiber installieren|treiber", "drivers"],
        ["papierkorb leeren", "empty the trash"],
        ["ton an|stummschaltung aufheben", "unmute"],
        ["stummschalten|stumm|ton aus", "mute"],
        ["handy finden|telefon finden|wo ist mein handy", "find my phone"],
        ["handy|telefon", "phone"],
        ["nachtlicht", "night light"],
        ["nicht storen", "do not disturb"],
        ["benachrichtigungen", "notifications"],
        ["spielmodus", "game mode"],
        ["wach halten", "keep awake"],
        ["mikrofon", "microphone"],
        ["dunkelmodus|dunkles design|dunkel", "dark mode"],
        ["heller modus|helles design|hell", "light mode"],
        ["lautstarke", "volume"],
        ["helligkeit", "brightness"],
        ["ton", "sound"],
        ["stelle|setze", "set"],
        ["auf", "to"],
        ["einschalten|anschalten|aktivieren|an|ein", "on"],
        ["ausschalten|deaktivieren|aus", "off"],
    ],
    fr: [
        ["eteindre l ordinateur|eteindre le pc|arreter l ordinateur", "shut down"],
        ["redemarrer", "restart"],
        ["se deconnecter|deconnexion", "log out"],
        ["verrouiller l ecran|verrouiller", "lock"],
        ["mettre en veille|veille", "sleep"],
        ["capture d une zone|capture de zone", "screenshot of an area"],
        ["capture d ecran|capture", "screenshot"],
        ["enregistrer l ecran|enregistrement d ecran", "record the screen"],
        ["annuler la mise a jour|annuler la derniere mise a jour", "undo the last update"],
        ["mettre a jour|mises a jour|mise a jour", "updates"],
        ["verifier le systeme|verifier l ordinateur|reparer l ordinateur", "check my system"],
        ["installer les pilotes|pilotes", "drivers"],
        ["vider la corbeille", "empty the trash"],
        ["remettre le son|reactiver le son", "unmute"],
        ["couper le son|muet", "mute"],
        ["trouver mon telephone|ou est mon telephone", "find my phone"],
        ["telephone", "phone"],
        ["eclairage nocturne|lumiere nocturne", "night light"],
        ["ne pas deranger", "do not disturb"],
        ["notifications", "notifications"],
        ["mode jeu", "game mode"],
        ["garder eveille", "keep awake"],
        ["microphone|micro", "microphone"],
        ["mode sombre|theme sombre|sombre", "dark mode"],
        ["mode clair|theme clair|clair", "light mode"],
        ["volume", "volume"],
        ["luminosite", "brightness"],
        ["son", "sound"],
        ["regler|mettre", "set"],
        ["a", "to"],
        ["activer|allumer", "on"],
        ["desactiver|eteindre|couper", "off"],
        ["le|la|les|l", ""],
    ],
    es: [
        ["apagar el equipo|apagar el ordenador|apagar la computadora|apagar el pc", "shut down"],
        ["reiniciar", "restart"],
        ["cerrar sesion", "log out"],
        ["bloquear la pantalla|bloquear", "lock"],
        ["suspender", "sleep"],
        ["captura de una zona|captura de area", "screenshot of an area"],
        ["captura de pantalla|captura", "screenshot"],
        ["grabar la pantalla|grabar pantalla", "record the screen"],
        ["deshacer la actualizacion|deshacer la ultima actualizacion", "undo the last update"],
        ["actualizar el sistema|actualizar|actualizaciones", "updates"],
        ["revisar el sistema|revisar el equipo|arreglar el equipo", "check my system"],
        ["instalar controladores|controladores", "drivers"],
        ["vaciar la papelera", "empty the trash"],
        ["activar el sonido|quitar silencio", "unmute"],
        ["silenciar|silencio", "mute"],
        ["encontrar mi telefono|donde esta mi telefono", "find my phone"],
        ["telefono|movil", "phone"],
        ["luz nocturna", "night light"],
        ["no molestar", "do not disturb"],
        ["notificaciones", "notifications"],
        ["modo juego", "game mode"],
        ["mantener despierto", "keep awake"],
        ["microfono", "microphone"],
        ["modo oscuro|tema oscuro|oscuro", "dark mode"],
        ["modo claro|tema claro|claro", "light mode"],
        ["volumen", "volume"],
        ["brillo", "brightness"],
        ["sonido", "sound"],
        ["poner|ajustar|subir|bajar", "set"],
        ["a|al", "to"],
        ["activar|encender|enciende|activa", "on"],
        ["desactivar|apagar|apaga|desactiva", "off"],
        ["el|la|los|las", ""],
    ],
    it: [
        ["spegni il computer|spegni il pc|arresta il sistema", "shut down"],
        ["riavvia", "restart"],
        ["esci|disconnettiti", "log out"],
        ["blocca lo schermo|blocca", "lock"],
        ["sospendi", "sleep"],
        ["screenshot di un area|cattura di un area", "screenshot of an area"],
        ["screenshot|cattura schermo", "screenshot"],
        ["registra lo schermo|registra schermo", "record the screen"],
        ["annulla l aggiornamento|annulla l ultimo aggiornamento", "undo the last update"],
        ["aggiorna il sistema|aggiorna|aggiornamenti", "updates"],
        ["controlla il sistema|controlla il computer|ripara il computer", "check my system"],
        ["installa i driver|driver", "drivers"],
        ["svuota il cestino", "empty the trash"],
        ["riattiva l audio|riattiva audio", "unmute"],
        ["silenzia|muto", "mute"],
        ["trova il telefono|dov e il mio telefono", "find my phone"],
        ["telefono", "phone"],
        ["luce notturna", "night light"],
        ["non disturbare", "do not disturb"],
        ["notifiche", "notifications"],
        ["modalita gioco", "game mode"],
        ["mantieni attivo", "keep awake"],
        ["microfono", "microphone"],
        ["modalita scura|tema scuro|scuro", "dark mode"],
        ["modalita chiara|tema chiaro|chiaro", "light mode"],
        ["volume", "volume"],
        ["luminosita", "brightness"],
        ["audio", "sound"],
        ["imposta|metti", "set"],
        ["a|al", "to"],
        ["attiva|accendi", "on"],
        ["disattiva|spegni", "off"],
        ["il|lo|la|i|gli|le|l", ""],
    ],
    pt: [
        ["desligar o computador|desligar o pc|desligar o sistema", "shut down"],
        ["reiniciar", "restart"],
        ["sair|encerrar sessao", "log out"],
        ["bloquear a tela|bloquear", "lock"],
        ["suspender", "sleep"],
        ["captura de uma area|captura de area", "screenshot of an area"],
        ["captura de tela|print", "screenshot"],
        ["gravar a tela|gravar tela", "record the screen"],
        ["desfazer a atualizacao|desfazer a ultima atualizacao", "undo the last update"],
        ["atualizar o sistema|atualizar|atualizacoes", "updates"],
        ["verificar o sistema|verificar o computador|consertar o computador", "check my system"],
        ["instalar drivers|drivers", "drivers"],
        ["esvaziar a lixeira", "empty the trash"],
        ["ativar o som|tirar o mudo", "unmute"],
        ["silenciar|mudo", "mute"],
        ["encontrar meu celular|onde esta meu celular|achar meu celular", "find my phone"],
        ["celular|telefone", "phone"],
        ["luz noturna", "night light"],
        ["nao perturbe|nao perturbar", "do not disturb"],
        ["notificacoes", "notifications"],
        ["modo de jogo|modo jogo", "game mode"],
        ["manter acordado", "keep awake"],
        ["microfone", "microphone"],
        ["modo escuro|tema escuro|escuro", "dark mode"],
        ["modo claro|tema claro|claro", "light mode"],
        ["volume", "volume"],
        ["brilho", "brightness"],
        ["som", "sound"],
        ["colocar|ajustar|definir", "set"],
        ["em|para", "to"],
        ["ativar|ligar|liga|ativa", "on"],
        ["desativar|desligar|desliga|desativa", "off"],
        ["o|a|os|as", ""],
    ],
    pl: [
        ["wylacz komputer|zamknij system", "shut down"],
        ["uruchom ponownie|restartuj|restart", "restart"],
        ["wyloguj sie|wyloguj", "log out"],
        ["zablokuj ekran|zablokuj", "lock"],
        ["uspij|usypianie", "sleep"],
        ["zrzut fragmentu ekranu|zrzut obszaru", "screenshot of an area"],
        ["zrzut ekranu", "screenshot"],
        ["nagraj ekran|nagrywanie ekranu", "record the screen"],
        ["cofnij aktualizacje|cofnij ostatnia aktualizacje", "undo the last update"],
        ["zaktualizuj system|aktualizuj|aktualizacje", "updates"],
        ["sprawdz system|sprawdz komputer|napraw komputer", "check my system"],
        ["zainstaluj sterowniki|sterowniki", "drivers"],
        ["oproznij kosz", "empty the trash"],
        ["wlacz dzwiek", "unmute"],
        ["wycisz", "mute"],
        ["znajdz telefon|gdzie jest moj telefon", "find my phone"],
        ["telefon", "phone"],
        ["swiatlo nocne", "night light"],
        ["nie przeszkadzac", "do not disturb"],
        ["powiadomienia", "notifications"],
        ["tryb gry", "game mode"],
        ["nie usypiaj", "keep awake"],
        ["mikrofon", "microphone"],
        ["tryb ciemny|ciemny motyw|ciemny", "dark mode"],
        ["tryb jasny|jasny motyw|jasny", "light mode"],
        ["glosnosc", "volume"],
        ["jasnosc", "brightness"],
        ["dzwiek", "sound"],
        ["ustaw", "set"],
        ["na", "to"],
        ["wlacz|uruchom", "on"],
        ["wylacz|zatrzymaj", "off"],
    ],
};

var currencyNames = {
    "€": "EUR", euro: "EUR", euros: "EUR", "$": "USD", dollar: "USD", dollars: "USD",
    "£": "GBP", pound: "GBP", pounds: "GBP", "¥": "JPY", yen: "JPY", din: "RSD", dinar: "RSD", dinars: "RSD",
    franc: "CHF", francs: "CHF", "₺": "TRY", "₽": "RUB",
};

function currencyOf(word, rates) {
    var w = word.toLowerCase();
    if (currencyNames.hasOwnProperty(w)) return currencyNames[w];
    var up = word.toUpperCase();
    return /^[A-Z]{3}$/.test(up) && (!rates || rates.rates.hasOwnProperty(up)) ? up : null;
}

function moneyQuery(query) {
    var m = plain(query).replace(/(\d)\s*([€$£¥₺₽])/g, "$1 $2").replace(/([€$£¥₺₽])\s*(\d[\d.,]*)/g, "$2 $1")
        .match(/^(\d[\d ]*(?:[.,]\d+)?)\s*(\S+)\s+(?:to|in|into|=|->|→)?\s*(\S+)$/);
    if (!m) return null;
    var from = currencyOf(m[2], null), to = currencyOf(m[3], null);
    if (!from || !to || from === to) return null;
    return { amount: parseFloat(m[1].replace(/ /g, "").replace(",", ".")), from: from, to: to };
}

function grouped(v) {
    var s = Math.abs(v) < 1 ? v.toFixed(4) : v.toFixed(2).replace(/\.00$/, "");
    var parts = s.split(".");
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ");
    return parts.join(".");
}

function money(query, rates) {
    var q = moneyQuery(query);
    if (!q || !rates || !rates.rates) return null;
    var r = rates.rates, base = rates.base;
    var per = function (c) { return c === base ? 1 : r[c]; };
    if (!per(q.from) || !per(q.to)) return null;
    var value = q.amount / per(q.from) * per(q.to);
    return { value: grouped(value) + " " + q.to, label: grouped(q.amount) + " " + q.from + " = ", date: rates.date || "" };
}
