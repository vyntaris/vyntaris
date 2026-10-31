import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import ".."

SettingsPage {
    id: page
    pageId: "time"

    onVisibleChanged: if (visible) { TimeZone.refresh(); Language.refresh(); } else open = ""

    property string open: ""
    function toggle(which) { open = open === which ? "" : which; }

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: page.visible; onTriggered: page.now = new Date() }

    component Picker: ColumnLayout {
        id: picker
        property string which
        property string placeholder
        property string current
        property var results: []
        property string empty: ""
        readonly property alias query: search.text
        signal picked(string value)
        Layout.fillWidth: true
        visible: page.open === which
        spacing: Theme.space8
        onVisibleChanged: if (visible) { search.text = ""; search.input.forceActiveFocus(); }
        SearchField {
            id: search
            Layout.fillWidth: true
            placeholder: picker.placeholder
            input.Keys.onEscapePressed: page.open = ""
            onAccepted: if (picker.results.length) picker.picked(picker.results[0].value)
        }
        PickList {
            current: picker.current
            model: picker.results
            onPicked: v => picker.picked(v)
        }
        Label {
            visible: picker.results.length === 0 && picker.empty !== ""
            leftPadding: 14
            color: Theme.overlay1
            text: picker.empty
        }
    }
    function languageRows(text) {
        return Language.search(text).map(l => ({ value: l.code, title: l.name, caption: l.english }));
    }

    Label {
        visible: Language.failure !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.error
        text: Language.failure
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space2
        Label {
            mono: true
            font.pixelSize: Theme.fontSizeDisplay
            font.weight: Font.DemiBold
            text: Qt.formatTime(page.now, Config.bar.clockFormat)
        }
        Caption { text: page.now.toLocaleDateString(Qt.locale(Language.formats || "en_US"), Locale.LongFormat) }
    }

    SettingsSection { text: Tr.t("Time") }
    SettingsRow {
        title: Tr.t("Set the time automatically")
        Switch { checked: Language.autoTime; onToggled: on => Language.setAutoTime(on) }
    }
    SettingsRow {
        title: Tr.t("Time zone")
        Button {
            icon: "earth"
            text: TimeZone.current ? TimeZone.city(TimeZone.current) + " · " + TimeZone.country(TimeZone.current) : "…"
            onClicked: page.toggle("zone")
        }
    }
    Picker {
        which: "zone"
        placeholder: Tr.t("A city or a country…")
        current: TimeZone.current
        results: TimeZone.search(query, 30).map(z => ({ value: z, title: TimeZone.city(z), caption: TimeZone.country(z) }))
        empty: query.trim() ? Tr.t("Nothing by that name") : ""
        onPicked: z => { TimeZone.set(z); page.open = ""; }
    }
    SettingsRow {
        title: Tr.t("Time format")
        Choice {
            options: [{ value: "HH:mm", label: "24-hour" }, { value: "h:mm AP", label: "12-hour" }, { value: "HH:mm:ss", label: Tr.t("Seconds") }]
            current: Config.bar.clockFormat
            onPicked: v => { Config.bar.clockFormat = v; Config.saveSoon(); }
        }
    }

    SettingsRow {
        title: Tr.t("Weather in the control center")
        Switch { checked: Config.weather.enabled; onToggled: on => { Config.weather.enabled = on; Config.saveSoon(); } }
    }
    SettingsRow {
        visible: Config.weather.enabled
        title: Tr.t("Weather for")
        Button {
            icon: "earth"
            text: Config.weather.city || (TimeZone.current ? TimeZone.city(TimeZone.current) + Tr.t(" (time zone)") : Tr.t("The time zone's city"))
            onClicked: page.toggle("weather")
        }
    }
    CityPicker {
        Layout.fillWidth: true
        visible: page.open === "weather"
        onChosen: page.open = ""
    }

    SettingsRow {
        title: Tr.t("Birthday")
        Field {
            implicitWidth: 140
            mono: true
            placeholder: Tr.t("DD.MM.YYYY")
            text: Config.lifeText()
            onCommitted: t => Config.setBirthday(t)
        }
    }

    SettingsSection { text: Tr.t("Language") }
    SettingsRow {
        title: Tr.t("Language")
        Button {
            icon: "translate"
            active: !Language.busy
            text: Language.nameOf(Language.language)
            onClicked: page.toggle("language")
        }
    }
    Picker {
        which: "language"
        placeholder: Tr.t("Find a language…")
        current: Language.language
        results: page.languageRows(query)
        empty: Tr.t("Nothing by that name")
        onPicked: code => {
            page.open = "";
            if (code !== Language.language)
                Language.setLanguage(code, Language.formats === Language.language ? code : Language.formats);
        }
    }
    SettingsRow {
        title: Tr.t("Formats")
        Button {
            icon: "calendar"
            active: !Language.busy
            text: Language.nameOf(Language.formats)
            onClicked: page.toggle("formats")
        }
    }
    Picker {
        which: "formats"
        placeholder: Tr.t("Find a language…")
        current: Language.formats
        results: page.languageRows(query)
        empty: Tr.t("Nothing by that name")
        onPicked: code => { page.open = ""; if (code !== Language.formats) Language.setLanguage(Language.language, code); }
    }
    Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.overlay1
        font.pixelSize: Theme.fontSizeLabel
        text: Language.busy ? Tr.t("Setting it up…") : Tr.t("Formats: how dates, numbers and money are written. Both show fully at the next login.")
    }
}
