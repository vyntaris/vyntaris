import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import Quickshell.Io
import "../../../config/Palettes.js" as Palettes

SettingsPage {
    id: page
    pageId: "appearance"

    // Which list is open under its row ("" for none): every value here is picked, none typed.
    property string open: ""
    function toggle(which) { open = open === which ? "" : which; }
    readonly property bool customAccent: Palettes.isCustom(Theme.accentName) && !Config.theme.wallpaperAccent
    // "#abc", "abc", "#aabbcc" or "aabbcc", as "#aabbcc"; "" when it's none of those.
    function hex(v) {
        let t = String(v).trim().replace(/^#/, "").toLowerCase();
        if (/^[0-9a-f]{3}$/.test(t)) t = t.split("").map(c => c + c).join("");
        return /^[0-9a-f]{6}$/.test(t) ? "#" + t : "";
    }
    readonly property var times: {
        const out = [];
        for (let m = 0; m < 24 * 60; m += 15) out.push(String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0"));
        return out;
    }
    function timeRows(q) {
        const k = q.replace(/[^0-9]/g, "");
        return times.filter(t => !k || t.replace(":", "").includes(k)).map(t => ({ value: t, title: t }));
    }
    readonly property var fonts: Qt.fontFamilies().filter(f => !f.startsWith(".") && !/emoji|^Symbols|nerd font/i.test(f))
    property var monoFonts: []
    Process {
        running: true
        command: ["fc-list", ":spacing=mono", "family"]
        stdout: StdioCollector { onStreamFinished: page.monoFonts = [...new Set(text.split("\n").map(l => l.split(",")[0].trim()).filter(l => l && !/nerd font|^Symbols/i.test(l)))].sort((a, b) => a.localeCompare(b)) }
    }
    function fontRows(list, q) {
        const k = q.trim().toLowerCase();
        return list.filter(f => !k || f.toLowerCase().includes(k)).map(f => ({ value: f, title: f }));
    }

    SettingsSection { text: Tr.t("Style") }
    SettingsRow {
        title: Tr.t("Theme")
        Choice {
            options: [{ value: "mocha", label: Tr.t("Dark") }, { value: "latte", label: Tr.t("Light") }, { value: "auto", label: Tr.t("Auto") }]
            current: Config.theme.autoFlavor ? "auto" : Config.theme.flavor
            onPicked: v => {
                Config.theme.autoFlavor = v === "auto";
                if (v !== "auto") Config.theme.flavor = v;
                if (v === "mocha") Config.theme.darkFlavor = v;
                Config.saveSoon();
            }
        }
    }
    SettingsRow {
        visible: Config.theme.autoFlavor
        title: Tr.t("Light from")
        Button { id: lightButton; icon: "sun"; text: Config.theme.lightFrom; onClicked: page.toggle("light") }
    }
    SettingsPicker {
        anchor: lightButton
        shown: Config.theme.autoFlavor && page.open === "light"
        placeholder: Tr.t("Search…")
        current: Config.theme.lightFrom
        results: page.timeRows(query)
        onPicked: v => { Config.theme.lightFrom = v; Config.saveSoon(); page.open = ""; }
        onClosed: page.open = ""
    }
    SettingsRow {
        visible: Config.theme.autoFlavor
        title: Tr.t("Dark from")
        Button { id: darkButton; icon: "moon"; text: Config.theme.darkFrom; onClicked: page.toggle("dark") }
    }
    SettingsPicker {
        anchor: darkButton
        shown: Config.theme.autoFlavor && page.open === "dark"
        current: Config.theme.darkFrom
        results: page.timeRows(query)
        onPicked: v => { Config.theme.darkFrom = v; Config.saveSoon(); page.open = ""; }
        onClosed: page.open = ""
    }
    SettingsRow {
        title: Tr.t("Accent")
        Row {
            spacing: Theme.space12
            Caption {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.theme.wallpaperAccent ? Tr.t("From wallpaper") : Theme.accentLabel(Theme.accentName)
            }
          Grid {
            anchors.verticalCenter: parent.verticalCenter
            columns: 9
            spacing: Theme.space8
            Repeater {
                model: Palettes.accentChoices
                AccentSwatch { required property string modelData; accent: modelData; size: 24 }
            }
            // Your own colour: the ring, with it in the middle once it's picked.
            Item {
                id: customSwatch
                readonly property bool current: page.customAccent
                width: 24; height: 24
                scale: customArea.containsMouse ? 1.12 : 1
                Behavior on scale { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }
                ColorRing { anchors.fill: parent; size: 24; interactive: false }
                Rectangle {
                    anchors.centerIn: parent
                    visible: customSwatch.current
                    width: 14; height: 14; radius: 7
                    color: Theme.accent
                    border { width: 2; color: Theme.isDark ? "#ffffff" : Theme.text }
                }
                PressArea {
                    id: customArea
                    anchors.fill: parent
                    label: Tr.t("Custom color")
                    role: Accessible.RadioButton
                    checked: customSwatch.current
                    onClicked: page.toggle("accent")
                }
            }
          }
        }
    }
    // Rolls out under the accents when the ring is clicked, and back in on the next click.
    SettingsRow {
        title: Tr.t("Custom color")
        id: customRow
        readonly property bool shown: page.open === "accent"
        reveal: shown ? 1 : 0
        Behavior on reveal {
            Anim {
                duration: customRow.shown ? Theme.durationSlow : Theme.durationNormal
                easing.bezierCurve: customRow.shown ? Theme.curveStandard : Theme.curveAccelerate
            }
        }
        RowLayout {
            spacing: Theme.space16
            Field {
                id: hexField
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 120
                mono: true
                placeholder: "#89b4fa"
                text: page.customAccent ? Theme.accentName : ""
                onCommitted: v => {
                    const hex = page.hex(v);
                    invalid = v !== "" && hex === "";
                    if (hex) Config.setAccent(hex);
                }
                // Used as soon as it's a whole colour: nothing else to press.
                onTextChanged: {
                    invalid = false;
                    const hex = /^#?[0-9a-fA-F]{6}$/.test(text.trim()) ? page.hex(text) : "";
                    if (hex && hex !== Theme.accentName) Config.setAccent(hex);
                }
            }
            ColorRing {
                Layout.topMargin: Theme.space8
                Layout.bottomMargin: Theme.space8
                size: 96
                color: page.customAccent ? Theme.accentName : ""
                onPicked: c => { Config.setAccent(c); hexField.text = c; }
            }
        }
    }
    SettingsRow {
        title: Tr.t("Accent from wallpaper")
        RowLayout {
            spacing: Theme.space10
            Rectangle {
                visible: WallpaperColors.ready && WallpaperColors.chosen !== ""
                implicitWidth: 18; implicitHeight: 18; radius: 9
                color: Theme.colorOf(WallpaperColors.chosen)
                border { width: 1; color: Theme.rimOn(parent) }
            }
            Switch { checked: Config.theme.wallpaperAccent; onToggled: on => { Config.theme.wallpaperAccent = on; Config.saveSoon(); } }
        }
    }
    SettingsRow {
        title: Tr.t("Match apps to theme")
        Switch { checked: Config.theme.syncApps; onToggled: on => { Config.theme.syncApps = on; Config.saveSoon(); } }
    }
    SettingsSection { text: Tr.t("Text") }
    SettingsRow {
        title: Tr.t("Text size")
        Choice {
            options: [{ value: 12, label: Tr.t("Small") }, { value: 13, label: Tr.t("Normal") }, { value: 15, label: Tr.t("Large") }, { value: 17, label: Tr.t("Larger") }]
            current: Config.theme.fontSize
            onPicked: v => { Config.theme.fontSize = v; Config.saveSoon(); }
        }
    }
    SettingsRow {
        title: Tr.t("Font")
        Button { id: fontButton; icon: "font"; text: Config.theme.fontFamily || "Inter"; onClicked: page.toggle("font") }
    }
    SettingsPicker {
        anchor: fontButton
        shown: page.open === "font"
        current: Config.theme.fontFamily || "Inter"
        results: page.fontRows(page.fonts, query)
        onPicked: v => { Config.theme.fontFamily = v; Config.saveSoon(); page.open = ""; }
        onClosed: page.open = ""
    }
    SettingsRow {
        title: Tr.t("Monospace font")
        Button { id: monoButton; icon: "terminal"; text: Config.theme.monoFamily || "JetBrains Mono"; onClicked: page.toggle("mono") }
    }
    SettingsPicker {
        anchor: monoButton
        shown: page.open === "mono"
        current: Config.theme.monoFamily || "JetBrains Mono"
        results: page.fontRows(page.monoFonts, query)
        onPicked: v => { Config.theme.monoFamily = v; Config.saveSoon(); page.open = ""; }
        onClosed: page.open = ""
    }
    SettingsSection { text: Tr.t("Motion") }
    SettingsRow {
        title: Tr.t("Animations")
        Switch { checked: Config.theme.animationSpeed > 0; onToggled: on => { Config.theme.animationSpeed = on ? 1.5 : 0; Config.saveSoon(); } }
    }
    // Vyntaris's own three, then Motion.js's presets: each moves the windows and the shell alike.
    readonly property var styles: [
        { value: "bouncy",   title: Tr.t("Bouncy"),   caption: Tr.t("Springs open, the way Vyntaris does") },
        { value: "smooth",   title: Tr.t("Smooth"),   caption: Tr.t("Eases in and out") },
        { value: "snappy",   title: Tr.t("Snappy"),   caption: Tr.t("Quick, no bounce") },
        { value: "classic",  title: Tr.t("Classic"),  caption: Tr.t("Pops in, eases out") },
        { value: "glide",    title: Tr.t("Glide"),    caption: Tr.t("Slides in with a swing") },
        { value: "brisk",    title: Tr.t("Brisk"),    caption: Tr.t("Quick and straight") },
        { value: "material", title: Tr.t("Material"), caption: Tr.t("Slows into place, speeds away") },
        { value: "drift",    title: Tr.t("Drift"),    caption: Tr.t("Soft, with a little overshoot") },
        { value: "spring",   title: Tr.t("Spring"),   caption: Tr.t("Springs past and settles") },
        { value: "lift",     title: Tr.t("Lift"),     caption: Tr.t("Even, workspaces rise") },
        { value: "calm",     title: Tr.t("Calm"),     caption: Tr.t("One gentle curve for all") },
        { value: "tight",    title: Tr.t("Tight"),    caption: Tr.t("Short, nothing overshoots") },
    ]
    SettingsRow {
        title: Tr.t("Animation style")
        Button { id: styleButton;
            icon: "sliders"
            text: page.styles.find(st => st.value === Config.theme.animationStyle)?.title ?? Config.theme.animationStyle
            onClicked: page.toggle("style")
        }
    }
    SettingsPicker {
        anchor: styleButton
        shown: page.open === "style"
        maxRows: 7
        current: Config.theme.animationStyle
        results: { const k = query.trim().toLowerCase(); return page.styles.filter(st => !k || st.title.toLowerCase().includes(k) || st.caption.toLowerCase().includes(k)); }
        onPicked: v => {
            Config.theme.animationStyle = v;
            Config.saveSoon();
            page.open = "";
        }
        onClosed: page.open = ""
    }
    SettingsRow {
        title: Tr.t("Workspaces slide")
        Choice {
            options: [{ value: "horizontal", label: Tr.t("Sideways") }, { value: "vertical", label: Tr.t("Up and down") }]
            current: Theme.workspacesVertical ? "vertical" : "horizontal"
            onPicked: v => { Config.theme.workspaceSlide = v; Config.saveSoon(); }
        }
    }
    SettingsSection { text: Tr.t("Sound") }
    SettingsRow {
        title: Tr.t("Login sound")
        Choice {
            options: [{ value: "chime", label: Tr.t("Chime") }, { value: "bloom", label: Tr.t("Bloom") }, { value: "halo", label: Tr.t("Halo") }, { value: "off", label: Tr.t("Off") }]
            current: Config.theme.loginSound
            onPicked: v => {
                Config.theme.loginSound = v; Config.saveSoon();
                if (v !== "off") Quickshell.execDetached(["pw-play", Config.loginSoundPath(v)]);
            }
        }
    }
}
