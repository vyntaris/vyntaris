import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    id: page
    pageId: "input"

    property string layoutError: ""
    function checkLayouts(layouts, variants) {
        if (Object.keys(Keyboard.names).length === 0) return "";
        const ls = layouts.split(",").map(x => x.trim()), vs = variants.split(",").map(x => x.trim());
        for (let i = 0; i < ls.length; i++) {
            if (!ls[i] || !(ls[i] in Keyboard.names)) return "There's no keyboard layout \u201c" + ls[i] + "\u201d (layouts are codes: us, de, rs, …)";
            if (vs[i] && !((ls[i] + ":" + vs[i]) in Keyboard.names)) return Tr.t("The layout ") + ls[i] + Tr.t(" has no variant \u201c") + vs[i] + "\u201d";
        }
        return "";
    }

    SettingsRow {
        title: Tr.t("Keyboard layout")
        Field {
            mono: true
            text: Config.input.kbLayout
            onCommitted: t => {
                const v = t.trim().replace(/\s*,\s*/g, ",") || "us";
                page.layoutError = page.checkLayouts(v, Config.input.kbVariant);
                if (page.layoutError) { text = Config.input.kbLayout; return; }
                Config.input.kbLayout = v; Config.saveSoon();
            }
        }
    }
    SettingsRow {
        title: Tr.t("Layout variant")
        Field {
            mono: true
            text: Config.input.kbVariant
            onCommitted: t => {
                const v = t.trim().replace(/\s*,\s*/g, ",");
                page.layoutError = page.checkLayouts(Config.input.kbLayout, v);
                if (page.layoutError) { text = Config.input.kbVariant; return; }
                Config.input.kbVariant = v; Config.saveSoon();
            }
        }
    }
    Label {
        visible: page.layoutError !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.error
        font.pixelSize: Theme.fontSizeSmall
        text: page.layoutError
    }
    SettingsRow { title: Tr.t("Options"); Field { mono: true; text: Config.input.kbOptions; onCommitted: t => { Config.input.kbOptions = t.trim(); Config.saveSoon(); } } }
    SettingsSection { text: Tr.t("Mouse and touchpad") }
    SettingsRow {
        title: Tr.t("Pointer speed")
        RowLayout {
            spacing: 10
            Slider { implicitWidth: 180; value: (Config.input.sensitivity + 1) / 2; onMoved: v => { Config.input.sensitivity = Math.round((v * 2 - 1) * 10) / 10; Config.saveSoon(); } }
            Label { mono: true; Layout.preferredWidth: 40; text: (Config.input.sensitivity > 0 ? "+" : "") + Config.input.sensitivity.toFixed(1) }
        }
    }
    SettingsRow {
        title: Tr.t("Acceleration")
        Switch { checked: Config.input.mouseAccel; onToggled: on => { Config.input.mouseAccel = on; Config.saveSoon(); } }
    }
    SettingsRow {
        title: Tr.t("Natural scrolling")
        Switch { checked: Config.input.naturalScroll; onToggled: on => { Config.input.naturalScroll = on; Config.saveSoon(); } }
    }
    SettingsRow {
        title: Tr.t("Tap to click")
        Switch { checked: Config.input.tapToClick; onToggled: on => { Config.input.tapToClick = on; Config.saveSoon(); } }
    }

    SettingsSection { text: Tr.t("Screen edges") }
    SettingsRow {
        title: Tr.t("Volume edge")
        Switch { checked: Config.edges.volume; onToggled: on => { Config.edges.volume = on; Config.saveSoon(); } }
    }
    SettingsRow {
        title: Tr.t("Brightness edge")
        Switch { checked: Config.edges.brightness; onToggled: on => { Config.edges.brightness = on; Config.saveSoon(); } }
    }
    SettingsRow {
        title: Tr.t("Hot corner")
        Choice {
            options: [{ value: "off", label: Tr.t("Off") }, { value: "top-left", label: "↖" }, { value: "bottom-left", label: "↙" }]
            current: Config.edges.corner
            onPicked: v => { Config.edges.corner = v; Config.saveSoon(); }
        }
    }
}
