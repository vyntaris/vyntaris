import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// The calendar: a week by the hour. A click on an empty hour adds an event there, a click on one changes it.
Scope {
    id: root

    readonly property date today: { const n = clock.now; return new Date(n.getFullYear(), n.getMonth(), n.getDate()); }
    QtObject { id: clock; property date now: new Date() }
    Timer { running: Panels.calendarOpen; repeat: true; interval: 30000; onTriggered: clock.now = new Date() }

    // Monday of the week shown.
    property date week: monday(today)
    function monday(d) { const m = new Date(d.getFullYear(), d.getMonth(), d.getDate()); m.setDate(m.getDate() - (m.getDay() + 6) % 7); return m; }
    function addDays(d, n) { const x = new Date(d); x.setDate(x.getDate() + n); return x; }
    function show(iso) { const p = iso.split("-").map(Number); week = monday(new Date(p[0], p[1] - 1, p[2])); }
    readonly property var days: [0, 1, 2, 3, 4, 5, 6].map(i => addDays(week, i))
    readonly property int hourHeight: 52

    Connections {
        target: Panels
        function onCalendarOpenChanged() { if (Panels.calendarOpen) { Calendar.refresh(); Calendar.sync(); scrollLater.restart(); } }
    }
    Timer { id: scrollLater; interval: 80; onTriggered: grid.contentY = Math.max(0, Math.min(grid.contentHeight - grid.height, (clock.now.getHours() - 1) * root.hourHeight)) }

    // The event being added or changed: null, or {id?, title, day, start "HH:MM", end, allDay, remind}.
    property var editing: null
    function pad(n) { return String(n).padStart(2, "0"); }
    function edit(ev) {
        if (ev.id) {
            editing = { id: ev.id, title: ev.title, day: new Date(ev.start.slice(0, 10) + "T00:00"),
                        start: ev.start.slice(11, 16), end: ev.end.slice(11, 16), allDay: ev.allDay, remind: ev.remind };
        } else {
            editing = ev;
        }
        title.text = editing.title;
        startField.text = editing.start;
        endField.text = editing.end;
        focusTitle.restart();
    }
    Timer { id: focusTitle; interval: 40; onTriggered: title.input.forceActiveFocus() }
    function save() {
        const e = editing, t = title.text.trim();
        if (!e || !t) return;
        const ok = s => /^\d{1,2}:\d{2}$/.test(s);
        const day = Calendar.key(e.day);
        const s = ok(startField.text) ? startField.text.padStart(5, "0") : "09:00";
        const en = ok(endField.text) ? endField.text.padStart(5, "0") : s;
        Calendar.save({ id: e.id, title: t, allDay: e.allDay, remind: e.remind,
                        start: day + "T" + (e.allDay ? "00:00" : s), end: day + "T" + (e.allDay ? "00:00" : en) });
        editing = null;
    }

    FloatingWindow {
        id: win
        visible: Panels.calendarOpen
        title: Tr.t("Calendar")
        implicitWidth: 1100
        implicitHeight: 760
        minimumSize: Qt.size(760, 520)
        color: Theme.base
        onVisibleChanged: if (!visible) Panels.calendarOpen = false

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.editing ? root.editing = null : Panels.calendarOpen = false
            Keys.onLeftPressed: root.week = root.addDays(root.week, -7)
            Keys.onRightPressed: root.week = root.addDays(root.week, 7)
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // The month, today, and the Google account.
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 290
                color: Theme.mantle
                ColumnLayout {
                    anchors { fill: parent; margins: Theme.space20 }
                    spacing: Theme.space16
                    RowLayout {
                        spacing: Theme.space10
                        Icon { name: "calendar"; size: 20; color: Theme.accentInk }
                        Label { font.pixelSize: Theme.fontSizeLarge; font.weight: Font.DemiBold; text: Tr.t("Calendar") }
                    }
                    Button {
                        Layout.fillWidth: true
                        primary: true
                        icon: "plus"
                        text: Tr.t("New event")
                        onClicked: {
                            const h = Math.min(22, clock.now.getHours() + 1);
                            const d = root.days.some(x => Calendar.key(x) === Calendar.key(root.today)) ? root.today : root.week;
                            root.edit({ title: "", day: d, start: root.pad(h) + ":00", end: root.pad(h + 1) + ":00", allDay: false, remind: 15 });
                        }
                    }
                    MonthCalendar {
                        id: month
                        Layout.fillWidth: true
                        marked: d => Calendar.on(d).length > 0
                        onPickedChanged: root.week = root.monday(picked)
                    }
                    Item { Layout.fillHeight: true }
                    // Google: who's signed in, or how to.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space6
                        Caption { text: "Google" }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Calendar.google ? Theme.text : Theme.subtext0
                            font.pixelSize: Theme.fontSizeSmall
                            text: Calendar.google ? (Calendar.failed ? Tr.f("{0} · couldn't sync", Calendar.google) : Calendar.google)
                                : Tr.t("Not connected: events stay on this computer.")
                        }
                        RowLayout {
                            spacing: Theme.space6
                            Button {
                                text: Calendar.google ? Tr.t("Accounts") : Tr.t("Connect Google")
                                icon: "users"
                                onClicked: Calendar.connectGoogle()
                            }
                            IconButton {
                                visible: Calendar.google !== ""
                                icon: "refresh"
                                label: Tr.t("Sync now")
                                active: !Calendar.syncing
                                onClicked: Calendar.sync()
                            }
                        }
                    }
                }
            }

            // The week.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: Theme.space16
                    spacing: Theme.space8
                    Label {
                        Layout.fillWidth: true
                        font.pixelSize: Theme.fontSizeHeading
                        font.weight: Font.DemiBold
                        text: Tr.dates.toString(root.addDays(root.week, 3), "MMMM yyyy")
                    }
                    Button { text: Tr.t("Today"); onClicked: { root.week = root.monday(root.today); scrollLater.restart(); } }
                    IconButton { icon: "chevron-left"; label: Tr.t("Previous week"); onClicked: root.week = root.addDays(root.week, -7) }
                    IconButton { icon: "chevron-right"; label: Tr.t("Next week"); onClicked: root.week = root.addDays(root.week, 7) }
                }

                // Day names, and the all-day events.
                RowLayout {
                    id: heads
                    Layout.fillWidth: true
                    Layout.rightMargin: Theme.space16
                    spacing: 0
                    Item { Layout.preferredWidth: 56 }
                    Repeater {
                        model: root.days
                        ColumnLayout {
                            id: head
                            required property var modelData
                            readonly property bool isToday: Calendar.key(modelData) === Calendar.key(root.today)
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            spacing: Theme.space4
                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: Theme.fontSizeSmall
                                color: head.isToday ? Theme.accentInk : Theme.subtext0
                                text: Tr.dates.toString(head.modelData, "ddd").toUpperCase()
                            }
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 34; implicitHeight: 34; radius: 17
                                color: head.isToday ? Theme.accent : "transparent"
                                Label {
                                    anchors.centerIn: parent
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.DemiBold
                                    color: head.isToday ? Theme.textOnAccent : Theme.text
                                    text: head.modelData.getDate()
                                }
                            }
                            Repeater {
                                model: Calendar.on(head.modelData).filter(e => e.allDay)
                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 2; Layout.rightMargin: 2
                                    implicitHeight: 22
                                    radius: Theme.r(6)
                                    color: Theme.accent
                                    Label {
                                        anchors { fill: parent; leftMargin: 6; rightMargin: 4 }
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.textOnAccent
                                        text: parent.modelData.title
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.edit(parent.modelData) }
                                }
                            }
                            // An all-day event: a click under the date.
                            MouseArea {
                                Layout.fillWidth: true
                                implicitHeight: 10
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.edit({ title: "", day: head.modelData, start: "", end: "", allDay: true, remind: 0 })
                            }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface0 }

                // Hours.
                Flickable {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: 24 * root.hourHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Item {
                        width: grid.width - Theme.space16
                        height: grid.contentHeight

                        Repeater {
                            model: 24
                            Item {
                                required property int index
                                y: index * root.hourHeight
                                width: parent.width
                                height: root.hourHeight
                                Label {
                                    x: 0; y: -height / 2
                                    width: 48
                                    visible: parent.index > 0
                                    horizontalAlignment: Text.AlignRight
                                    mono: true
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.overlay1
                                    text: root.pad(parent.index) + ":00"
                                }
                                Rectangle { x: 56; width: parent.width - 56; height: 1; color: Theme.surface0 }
                            }
                        }

                        Row {
                            x: 56
                            width: parent.width - 56
                            height: parent.height
                            Repeater {
                                model: root.days
                                Item {
                                    id: column
                                    required property var modelData
                                    width: parent.width / 7
                                    height: parent.height
                                    Rectangle { width: 1; height: parent.height; color: Theme.surface0 }

                                    // An empty hour: a new event there.
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mouse => {
                                            const h = Math.floor(mouse.y / root.hourHeight);
                                            root.edit({ title: "", day: column.modelData, start: root.pad(h) + ":00",
                                                        end: root.pad(Math.min(23, h + 1)) + ":" + (h >= 23 ? "59" : "00"), allDay: false, remind: 15 });
                                        }
                                    }

                                    Repeater {
                                        model: Calendar.on(column.modelData).filter(e => !e.allDay)
                                        Rectangle {
                                            id: block
                                            required property var modelData
                                            readonly property real from: { const s = new Date(modelData.start); return Calendar.key(s) === Calendar.key(column.modelData) ? s.getHours() + s.getMinutes() / 60 : 0; }
                                            readonly property real to: { const e = new Date(modelData.end); return Calendar.key(e) === Calendar.key(column.modelData) ? e.getHours() + e.getMinutes() / 60 : 24; }
                                            x: 3
                                            y: from * root.hourHeight + 1
                                            width: column.width - 6
                                            height: Math.max(22, (to - from) * root.hourHeight - 2)
                                            radius: Theme.r(8)
                                            color: blockArea.containsMouse ? Qt.lighter(Theme.accent, 1.06) : Theme.accent
                                            Column {
                                                anchors { fill: parent; margins: 6 }
                                                clip: true
                                                Label {
                                                    width: parent.width
                                                    elide: Text.ElideRight
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.weight: Font.DemiBold
                                                    color: Theme.textOnAccent
                                                    text: block.modelData.title
                                                }
                                                Label {
                                                    visible: block.height > 38
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.textOnAccent
                                                    opacity: 0.8
                                                    text: block.modelData.start.slice(11, 16) + " – " + block.modelData.end.slice(11, 16)
                                                }
                                            }
                                            MouseArea { id: blockArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.edit(block.modelData) }
                                        }
                                    }

                                    // Now.
                                    Rectangle {
                                        visible: Calendar.key(column.modelData) === Calendar.key(root.today)
                                        y: (clock.now.getHours() + clock.now.getMinutes() / 60) * root.hourHeight
                                        width: parent.width; height: 2
                                        color: Theme.red
                                        Rectangle { x: -4; y: -3; width: 8; height: 8; radius: 4; color: Theme.red }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Adding or changing an event.
        Rectangle {
            anchors.fill: parent
            visible: root.editing !== null
            color: Qt.rgba(0, 0, 0, 0.35)
            MouseArea { anchors.fill: parent; onClicked: root.editing = null }

            Rectangle {
                anchors.centerIn: parent
                width: 440
                height: form.implicitHeight + 2 * Theme.space20
                radius: Theme.r(18)
                color: Theme.mantle
                border { width: 1; color: Theme.surface0 }
                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: form
                    anchors { fill: parent; margins: Theme.space20 }
                    spacing: Theme.space10
                    Keys.onEscapePressed: root.editing = null

                    Label {
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.DemiBold
                        text: root.editing?.id ? Tr.t("Change event") : Tr.t("New event")
                    }
                    Caption { text: root.editing ? Tr.dates.toString(root.editing.day, "dddd, d MMMM yyyy") : "" }
                    Field {
                        id: title
                        Layout.fillWidth: true
                        placeholder: Tr.t("Title")
                        input.Keys.onReturnPressed: root.save()
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        Switch {
                            checked: root.editing?.allDay ?? false
                            onToggled: on => root.editing = Object.assign({}, root.editing, { allDay: on, remind: on ? 0 : 15 })
                        }
                        Label { text: Tr.t("All day") }
                        Item { Layout.fillWidth: true }
                        Field {
                            id: startField
                            visible: !(root.editing?.allDay ?? false)
                            implicitWidth: 92
                            mono: true
                            placeholder: "09:00"
                            input.Keys.onReturnPressed: root.save()
                        }
                        Label { visible: startField.visible; text: "–" }
                        Field {
                            id: endField
                            visible: startField.visible
                            implicitWidth: 92
                            mono: true
                            placeholder: "10:00"
                            input.Keys.onReturnPressed: root.save()
                        }
                    }
                    Caption { text: Tr.t("Reminder") }
                    Choice {
                        Layout.fillWidth: true
                        stretch: true
                        options: (root.editing?.allDay ?? false)
                            ? [{ value: -1, label: Tr.t("None") }, { value: 0, label: Tr.t("At 9:00") }]
                            : [{ value: -1, label: Tr.t("None") }, { value: 0, label: Tr.t("At start") }, { value: 15, label: "15 min" },
                               { value: 60, label: "1 h" }, { value: 1440, label: Tr.t("1 day") }]
                        current: root.editing?.remind ?? -1
                        onPicked: v => root.editing = Object.assign({}, root.editing, { remind: v })
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.space6
                        spacing: Theme.space6
                        Button {
                            visible: !!root.editing?.id
                            danger: true
                            icon: "trash"
                            text: Tr.t("Delete")
                            onClicked: { Calendar.remove(root.editing.id); root.editing = null; }
                        }
                        Item { Layout.fillWidth: true }
                        Button { text: Tr.t("Cancel"); onClicked: root.editing = null }
                        Button {
                            primary: true
                            icon: "check"
                            active: title.text.trim() !== ""
                            text: Tr.t("Save")
                            onClicked: root.save()
                        }
                    }
                }
            }
        }
    }
}
