pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    readonly property string tool: Quickshell.env("VYNTARIS_SETTINGS_ADMIN") || "/usr/lib/vyntaris/settings-admin"

    readonly property var languages: [
        { code: "en_US", name: "English (United States)", english: "English, US" },
        { code: "en_GB", name: "English (United Kingdom)", english: "English, UK" },
        { code: "sr_RS@latin", name: "Srpski (latinica)", english: "Serbian, Latin" },
        { code: "sr_RS", name: "Српски (ћирилица)", english: "Serbian, Cyrillic" },
        { code: "hr_HR", name: "Hrvatski", english: "Croatian" },
        { code: "bs_BA", name: "Bosanski", english: "Bosnian" },
        { code: "sl_SI", name: "Slovenščina", english: "Slovenian" },
        { code: "mk_MK", name: "Македонски", english: "Macedonian" },
        { code: "de_DE", name: "Deutsch", english: "German" },
        { code: "fr_FR", name: "Français", english: "French" },
        { code: "es_ES", name: "Español", english: "Spanish" },
        { code: "it_IT", name: "Italiano", english: "Italian" },
        { code: "pt_BR", name: "Português (Brasil)", english: "Portuguese, Brazil" },
        { code: "nl_NL", name: "Nederlands", english: "Dutch" },
        { code: "pl_PL", name: "Polski", english: "Polish" },
        { code: "cs_CZ", name: "Čeština", english: "Czech" },
        { code: "hu_HU", name: "Magyar", english: "Hungarian" },
        { code: "ro_RO", name: "Română", english: "Romanian" },
        { code: "el_GR", name: "Ελληνικά", english: "Greek" },
        { code: "tr_TR", name: "Türkçe", english: "Turkish" },
        { code: "ru_RU", name: "Русский", english: "Russian" },
        { code: "uk_UA", name: "Українська", english: "Ukrainian" },
        { code: "zh_CN", name: "中文 (简体)", english: "Chinese, Simplified" },
        { code: "ja_JP", name: "日本語", english: "Japanese" },
    ]
    function nameOf(code) { return languages.find(l => l.code === code)?.name ?? code; }
    function search(text) {
        const q = text.trim().toLowerCase();
        return languages.filter(l => !q || l.name.toLowerCase().includes(q) || l.english.toLowerCase().includes(q) || l.code.toLowerCase().startsWith(q));
    }

    property string language: ""
    property string formats: ""
    property bool autoTime: true
    property bool busy: false
    property string failure: ""

    function code(locale) { return (locale ?? "").replace(/\.UTF-8/i, "").replace(/\.utf8/i, ""); }

    function refresh() { status.running = true; ntp.running = true; }
    Process {
        id: status
        command: ["localectl", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lang = /LANG=(\S+)/.exec(text), time = /LC_TIME=(\S+)/.exec(text);
                root.language = root.code(lang?.[1] ?? "en_US");
                root.formats = time ? root.code(time[1]) : root.language;
            }
        }
    }
    Process {
        id: ntp
        command: ["timedatectl", "show", "-p", "NTP", "--value"]
        stdout: StdioCollector { onStreamFinished: root.autoTime = text.trim() === "yes" }
    }

    function setLanguage(lang, form) {
        if (busy) return;
        busy = true;
        failure = "";
        setter.command = ["pkexec", tool, "locale", lang].concat(form && form !== lang ? [form] : []);
        setter.running = true;
    }
    Process {
        id: setter
        stderr: StdioCollector { id: setErr }
        onExited: code => {
            root.busy = false;
            if (code !== 0 && code !== 126 && code !== 127)
                root.failure = setErr.text.trim().split("\n").pop() || Tr.t("The language couldn't be changed");
            root.refresh();
        }
    }

    function setAutoTime(on) {
        autoSetter.command = ["timedatectl", "set-ntp", on ? "true" : "false"];
        autoSetter.running = true;
    }
    Process { id: autoSetter; onExited: ntp.running = true }

    Component.onCompleted: refresh()
}
