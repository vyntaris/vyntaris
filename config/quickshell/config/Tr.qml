pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string chosen: ""
    readonly property string locale: chosen || Quickshell.env("VYNTARIS_LANG") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "en"
    readonly property string lang: locale.split(/[_.@]/)[0].toLowerCase() || "en"
    property var dict: ({})
    onLangChanged: dict = ({})
    readonly property var dates: lang === "en" ? Qt.locale("en_US") : lang === "sr" ? Qt.locale("sr_Latn_RS")
        : Qt.locale(locale.split(".")[0].replace(/@.*/, ""))

    function t(s) {
        return dict[s] ?? s;
    }
    function f(s, ...args) {
        return t(s).replace(/\{(\d+)\}/g, (m, i) => String(args[Number(i)] ?? m));
    }

    FileView {
        path: root.lang === "en" ? "" : Quickshell.shellPath("i18n/" + root.lang + ".json")
        onLoaded: {
            try { root.dict = JSON.parse(text()); } catch (e) { root.dict = {}; }
        }
    }
}
