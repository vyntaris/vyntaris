import QtQuick
import "../../config/quickshell/modules/island/Search.js" as Search
import "../../config/quickshell/modules/settings/SettingsIndex.js" as Index

QtObject {
    property int fails: 0
    function check(what, ok) {
        console.log((ok ? "   ok    " : "   FAIL  ") + what);
        if (!ok) fails++;
    }
    function cmd(q) { return Search.command(q, Index.pages); }
    function is(q, action, value) {
        const c = cmd(q);
        check(`"${q}" → ${action}${value === undefined ? "" : " " + value}` + (c ? "" : " (nothing)"),
              c !== null && c.action === action && (value === undefined || c.value === value));
    }
    function none(q) { check(`"${q}" isn't a command`, cmd(q) === null); }
    function isIn(lang, q, action, value) {
        const c = Search.command(q, Index.pages, null, lang);
        check(`${lang} "${q}" → ${action}${value === undefined ? "" : " " + value}` + (c ? "" : " (nothing)"),
              c !== null && c.action === action && (value === undefined || c.value === value));
    }

    Component.onCompleted: {
        console.log(":: switches");
        is("turn bluetooth off", "bluetooth", false);
        is("Turn Bluetooth off", "bluetooth", false);
        is("wifi on", "wifi", true);
        is("wi-fi on", "wifi", true);
        is("bluetooth", "bluetooth", null);
        is("night light on", "nightlight", true);
        is("night light", "nightlight", null);
        is("do not disturb on", "dnd", true);
        is("turn notifications off", "dnd", true);
        is("notifications on", "dnd", false);
        is("dark mode", "dark", true);
        is("dark mode off", "dark", false);
        is("light mode", "dark", false);
        is("game mode on", "gamemode", true);
        is("mic off", "mic", false);
        console.log(":: one-shots");
        is("lock", "lock");
        is("lock the screen", "lock");
        is("restart", "reboot");
        is("shut down", "shutdown");
        is("log out", "logout");
        is("screenshot", "screenshot");
        is("screenshot of an area", "screenshot-region");
        is("update the system", "updates");
        is("check my system", "health");
        is("fix my computer", "health");
        is("empty the trash", "trash");
        is("mute", "mute", true);
        is("undo the last update", "undo-update");
        is("find my phone", "phone-ring");
        is("where's my phone", "phone-ring");
        is("send clipboard to phone", "phone-clipboard");
        is("kde connect", "phone");
        console.log(":: other languages");
        isIn("sr", "isključi bluetooth", "bluetooth", false);
        isIn("sr", "iskljuci bluetooth", "bluetooth", false);
        isIn("sr", "uključi noćno svetlo", "nightlight", true);
        isIn("sr", "jačina 40", "volume", 0.4);
        isIn("sr", "postavi jačinu na 40", "volume", 0.4);
        isIn("sr", "osvetljenost 70", "brightness", 0.7);
        isIn("sr", "zaključaj ekran", "lock");
        isIn("sr", "ugasi računar", "shutdown");
        isIn("sr", "tamni režim", "dark", true);
        isIn("sr", "wifi on", "wifi", true);
        isIn("de", "bluetooth ausschalten", "bluetooth", false);
        isIn("de", "lautstärke 40", "volume", 0.4);
        isIn("de", "nachtlicht an", "nightlight", true);
        isIn("de", "bildschirm sperren", "lock");
        isIn("de", "herunterfahren", "shutdown");
        isIn("fr", "désactiver le bluetooth", "bluetooth", false);
        isIn("fr", "verrouiller l'écran", "lock");
        isIn("fr", "luminosité 70", "brightness", 0.7);
        isIn("es", "apagar el wifi", "wifi", false);
        isIn("es", "volumen 40", "volume", 0.4);
        isIn("es", "bloquear la pantalla", "lock");
        isIn("it", "spegni il bluetooth", "bluetooth", false);
        isIn("it", "riavvia", "reboot");
        isIn("pt", "desligar o wifi", "wifi", false);
        isIn("pt", "brilho 70", "brightness", 0.7);
        isIn("pl", "wyłącz bluetooth", "bluetooth", false);
        isIn("pl", "głośność 40", "volume", 0.4);
        isIn("pl", "zablokuj ekran", "lock");
        check("an unknown language is English only", Search.command("isključi bluetooth", Index.pages, null, "xx") === null);
        console.log(":: apps listed");
        check("an app is listed", Search.listed({ id: "firefox", noDisplay: false }));
        check("one hidden by its entry isn't", !Search.listed({ id: "foo", noDisplay: true }));
        check("KDE Connect's windows aren't (the shell is the phone's face)",
              !Search.listed({ id: "org.kde.kdeconnect.app", noDisplay: false }) && !Search.listed({ id: "org.kde.kdeconnect-settings", noDisplay: false }));
        console.log(":: values");
        is("volume 40", "volume", 0.4);
        is("set the volume to 75%", "volume", 0.75);
        is("brightness 70", "brightness", 0.7);
        is("volume 400", "volume", 1);
        console.log(":: settings by name");
        is("display settings", "settings", "displays");
        is("sound", "sound");
        is("set up games", "games-setup");
        is("install steam", "games-setup");
        is("audio devices", "sound");
        is("headphones", "sound");
        is("open sound settings", "settings", "notifications");
        is("settings for printers", "settings", "printers");
        is("printer settings", "settings", "printers");
        console.log(":: no Serbian: those stay searches");
        none("iskljuci bluetooth");
        none("podesavanja ekrana");
        none("ugasi racunar");
        console.log(":: not commands: apps and searches stay theirs");
        none("firefox");
        none("bluetooth headphones manual");
        none("off");
        none("visual studio code");
        none("wifi password for home");

        console.log(":: money");
        const rates = { base: "EUR", date: "2026-10-13", rates: { EUR: 1, USD: 1.1, RSD: 117.1, GBP: 0.85 } };
        const m = (q) => Search.money(q, rates);
        check("100 eur to rsd", m("100 eur to rsd")?.value === "11 710 RSD");
        check("100€ in din", m("100€ in din")?.value === "11 710 RSD");
        check("50 dollars to euros", m("50 dollars to euros")?.value === "45.45 EUR");
        check("$20 in gbp", m("$20 in gbp")?.value === "15.45 GBP");
        check("1 rsd to eur: small amounts keep digits", m("1 rsd to eur")?.value === "0.0085 EUR");
        check("2 500 rsd to eur: spaces in the amount", m("2 500 rsd to eur")?.value === "21.35 EUR");
        check("no Serbian: 100 eur u din isn't", Search.moneyQuery("100 evra u dinare") === null);
        check("units aren't money: 100 m to ft", Search.moneyQuery("100 m to ft") === null);
        check("an unknown code isn't", m("100 eur to xyz") === null);
        check("without rates: asks, says nothing", Search.money("100 eur to rsd", null) === null && Search.moneyQuery("100 eur to rsd") !== null);

        console.log(fails === 0 ? "\nsearch: all checks passed" : `\nsearch: ${fails} failed`);
        Qt.exit(fails === 0 ? 0 : 1);
    }
}
