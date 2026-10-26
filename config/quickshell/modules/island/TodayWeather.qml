import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root
    spacing: 0
    property real titleY: 0
    property real datesBaseline: 0
    Layout.alignment: Qt.AlignTop
    Layout.fillHeight: false
    Layout.preferredHeight: Math.max(implicitHeight, datesBaseline + city.height - city.baselineOffset)

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var en: Tr.dates
    function week(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        return Math.ceil(((t - new Date(Date.UTC(t.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7);
    }
    readonly property var w: Weather.known ? Weather.describe(Weather.now.code, Weather.now.day) : null

    Label {
        Layout.topMargin: root.titleY
        caps: true
        color: Theme.accent
        font.pixelSize: Theme.fontSizeSmall - 1
        text: root.en.toString(clock.date, "dddd")
    }
    Label {
        font.pixelSize: Math.round(Theme.fontSize * 2.9)
        font.weight: Font.Light
        mono: true
        text: clock.date.getDate()
    }
    Caption { text: root.en.toString(clock.date, "MMMM") + Tr.t(" · Week ") + root.week(clock.date) }

    readonly property date born: /^\d{4}-\d{2}-\d{2}$/.test(Config.life.birthday) ? new Date(Config.life.birthday + "T00:00:00") : new Date(NaN)
    readonly property bool mori: !isNaN(born.getTime())
    readonly property date end: mori ? new Date(born.getFullYear() + Config.life.years, born.getMonth(), born.getDate()) : new Date(NaN)
    readonly property int weeksLeft: mori ? Math.max(0, Math.floor((end - clock.date) / 604800000)) : 0
    readonly property real lived: mori ? Math.max(0, Math.min(1, (clock.date - born) / (end - born))) : 0
    ColumnLayout {
        visible: root.mori
        Layout.topMargin: 4
        Layout.fillWidth: true
        spacing: 3
        Meter {
            Layout.fillWidth: true
            Layout.rightMargin: 8
            implicitHeight: Math.round(Theme.fontSizeSmall / 2)
            count: 16
            value: root.lived
        }
        Label { mono: true; color: Theme.subtext0; font.pixelSize: Theme.fontSizeSmall - 1; text: root.weeksLeft.toLocaleString(Qt.locale("en_US"), "f", 0) + Tr.t(" weeks left") }
    }

    Item { Layout.fillHeight: true }

    RowLayout {
        visible: root.w !== null
        spacing: 8
        Icon { name: root.w?.icon ?? "sun"; size: Theme.fontSize + 9; stroke: 1.6; color: Theme.accent }
        Label { font.pixelSize: Theme.fontSize + 5; font.weight: Font.Light; mono: true; text: (Weather.now?.temp ?? "") + "°" }
    }
    Label {
        visible: root.w !== null
        Layout.fillWidth: true
        elide: Text.ElideRight
        font.weight: Font.DemiBold
        font.pixelSize: Theme.fontSizeSmall + 1
        text: root.w?.text ?? ""
    }
    Caption {
        visible: root.w !== null
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: "↑" + (Weather.now?.max ?? "") + "°  ↓" + (Weather.now?.min ?? "") + "°"
    }
    Caption {
        id: city
        visible: root.w !== null
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: Weather.city
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Panels.controlOpen = false; Panels.settingsRow("time", "Weather for"); } }
    }
}
