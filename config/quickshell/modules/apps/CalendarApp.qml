import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// Calendar, made like Settings: the side with the month and what's coming up, a week by the hour in a card.
// A click on an empty hour adds an event there, a click on one changes it.
Scope {
    id: root

    QtObject { id: clock; property date now: new Date() }
    Timer { running: Panels.calendarOpen; repeat: true; interval: 30000; onTriggered: clock.now = new Date() }
    readonly property date today: new Date(clock.now.getFullYear(), clock.now.getMonth(), clock.now.getDate())

    // Monday of the week shown.
    property date week: monday(today)
    function monday(d) { const m = new Date(d.getFullYear(), d.getMonth(), d.getDate()); m.setDate(m.getDate() - (m.getDay() + 6) % 7); return m; }
    function addDays(d, n) { const x = new Date(d); x.setDate(x.getDate() + n); return x; }
    function show(iso) { const p = iso.split("-").map(Number); go(new Date(p[0], p[1] - 1, p[2])); }
    function go(d) { week = monday(d); month.year = d.getFullYear(); month.month = d.getMonth(); month.picked = d; }
    readonly property var days: [0, 1, 2, 3, 4, 5, 6].map(i => addDays(week, i))
    readonly property int hourHeight: 52
    readonly property int gutter: 58
    readonly property color card: Theme.isDark ? Theme.surface0 : Theme.mantle
    function pad(n) { return String(n).padStart(2, "0"); }

    Connections {
        target: Panels
        function onCalendarOpenChanged() { if (Panels.calendarOpen) { Calendar.refresh(); Calendar.sync(); scrollLater.restart(); } }
    }
    Component.onCompleted: if (Panels.calendarOpen) scrollLater.restart()
    Timer { id: scrollLater; interval: 80; onTriggered: grid.contentY = Math.max(0, Math.min(grid.contentHeight - grid.height, (clock.now.getHours() - 1) * root.hourHeight)) }

    // What's next, from now.
    readonly property var coming: {
        const now = Calendar.key(clock.now) + "T" + pad(clock.now.getHours()) + ":" + pad(clock.now.getMinutes());
        return Calendar.events.filter(e => e.end > now).sort((a, b) => a.start.localeCompare(b.start)).slice(0, 6);
    }
    function when(e) {
        const d = new Date(e.start.slice(0, 10) + "T00:00");
        const day = Calendar.key(d) === Calendar.key(today) ? Tr.t("Today") : Tr.dates.toString(d, "ddd d MMM");
        return e.allDay ? day : day + " · " + e.start.slice(11, 16);
    }

    // The event being added or changed: null, or {id?, title, day, start "HH:MM", end, allDay, remind}.
    property var editing: null
    function edit(ev) {
        editing = ev.id ? { id: ev.id, title: ev.title, day: new Date(ev.start.slice(0, 10) + "T00:00"),
                            start: ev.start.slice(11, 16), end: ev.end.slice(11, 16), allDay: ev.allDay, remind: ev.remind } : ev;
        title.text = editing.title;
        startField.text = editing.start;
        endField.text = editing.end;
        focusTitle.restart();
    }
    function newAt(day, hour) {
        const h = Math.max(0, Math.min(23, hour));
        edit({ title: "", day: day, start: pad(h) + ":00", end: h >= 23 ? "23:59" : pad(h + 1) + ":00", allDay: false, remind: 15 });
    }
    Timer { id: focusTitle; interval: 40; onTriggered: title.input.forceActiveFocus() }
    function save() {
        const e = editing, t = title.text.trim();
        if (!e || !t) return;
        const ok = s => /^\d{1,2}:\d{2}$/.test(s.trim()) ? s.trim().padStart(5, "0") : "";
        const day = Calendar.key(e.day);
        const s = ok(startField.text) || "09:00";
        const en = ok(endField.text) || s;
        Calendar.save({ id: e.id, title: t, allDay: e.allDay, remind: e.remind,
                        start: day + "T" + (e.allDay ? "00:00" : s), end: day + "T" + (e.allDay ? "00:00" : en) });
        editing = null;
    }

    FloatingWindow {
        id: win
        visible: Panels.calendarOpen
        title: Tr.t("Calendar")
        implicitWidth: Math.min(1180, (screen?.width ?? 1920) * 0.85)
        implicitHeight: Math.min(820, (screen?.height ?? 1080) * 0.9)
        minimumSize: Qt.size(860, 560)
        color: Theme.base
        onVisibleChanged: if (!visible) Panels.calendarOpen = false

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.editing ? root.editing = null : Panels.calendarOpen = false
            Keys.onPressed: event => {
                if (root.editing) return;
                if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Left) root.week = root.addDays(root.week, -7);
                else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Right) root.week = root.addDays(root.week, 7);
                else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) root.newAt(root.today, clock.now.getHours() + 1);
                else return;
                event.accepted = true;
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // The side, as Settings' is: name and account, a new event, the month, what's coming up, Google.
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: Theme.navWidth + 24
                color: Theme.mantle

                ColumnLayout {
                    anchors { fill: parent; margins: Theme.navInset }
                    spacing: Theme.space4

                    RowLayout {
                        Layout.bottomMargin: Theme.space12
                        Layout.leftMargin: Theme.space6
                        spacing: Theme.space10
                        Icon { name: "calendar"; size: 22; color: Theme.accentInk }
                        ColumnLayout {
                            spacing: 0
                            Label { font.weight: Font.Bold; text: Tr.t("Calendar") }
                            Caption { text: Calendar.google || Tr.t("On this computer") }
                        }
                    }
                    Button {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Theme.space12
                        primary: true
                        icon: "plus"
                        text: Tr.t("New event")
                        onClicked: root.newAt(root.days.some(d => Calendar.key(d) === Calendar.key(root.today)) ? root.today : root.week, clock.now.getHours() + 1)
                    }
                    MonthCalendar {
                        id: month
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.space4
                        Layout.rightMargin: Theme.space4
                        marked: d => Calendar.on(d).length > 0
                        onPickedChanged: root.week = root.monday(picked)
                    }

                    SectionTitle { text: Tr.t("Coming up") }
                    Repeater {
                        model: root.coming
                        Rectangle {
                            id: next
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: Theme.navItemHeight + 8
                            radius: Theme.navRadius
                            color: nextArea.containsMouse ? Theme.hoverOn(parent) : "transparent"
                            Behavior on color { ColorAnim {} }
                            RowLayout {
                                anchors { fill: parent; leftMargin: Theme.space12; rightMargin: Theme.space12 }
                                spacing: Theme.space10
                                Rectangle { Layout.preferredWidth: 3; Layout.preferredHeight: 22; radius: 2; color: Theme.accent }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label { Layout.fillWidth: true; elide: Text.ElideRight; text: next.modelData.title }
                                    Caption { Layout.fillWidth: true; elide: Text.ElideRight; text: root.when(next.modelData) }
                                }
                            }
                            PressArea {
                                id: nextArea
                                anchors.fill: parent
                                label: next.modelData.title
                                onClicked: { root.go(new Date(next.modelData.start.slice(0, 10) + "T00:00")); root.edit(next.modelData); }
                            }
                        }
                    }
                    Caption {
                        visible: root.coming.length === 0
                        Layout.leftMargin: Theme.space12
                        text: Tr.t("Nothing coming up")
                    }

                    Item { Layout.fillHeight: true }

                    SectionTitle { text: "Google" }
                    Caption {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.space6
                        Layout.bottomMargin: Theme.space6
                        wrapMode: Text.Wrap
                        text: Calendar.google ? Tr.t("Synced with Google Calendar.")
                            : Calendar.client ? Tr.t("Not connected: events stay on this computer.")
                            : Tr.t("Google isn't set up on this computer yet.")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space6
                        Button {
                            Layout.fillWidth: true
                            icon: Calendar.google ? "logout" : "users"
                            active: !Calendar.connecting && (Calendar.client || Calendar.google !== "")
                            text: Calendar.connecting ? Tr.t("Waiting for the browser…") : Calendar.google ? Tr.t("Sign out") : Tr.t("Connect Google")
                            onClicked: Calendar.google ? Calendar.disconnect() : Calendar.connect()
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

            // The page: the month's name, the week's days and the way to others, then the week in a card.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 28
                Layout.topMargin: 24
                spacing: Theme.space16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    Label {
                        font.pixelSize: Theme.fontSizeHeading
                        font.weight: Font.Bold
                        text: Tr.dates.toString(root.addDays(root.week, 3), "MMMM yyyy")
                    }
                    Caption {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBaseline
                        text: Tr.dates.toString(root.days[0], "d MMM") + " – " + Tr.dates.toString(root.days[6], "d MMM")
                    }
                    Button { text: Tr.t("Today"); onClicked: { root.go(root.today); scrollLater.restart(); } }
                    IconButton { icon: "chevron-left"; label: Tr.t("Previous week"); onClicked: root.go(root.addDays(root.week, -7)) }
                    IconButton { icon: "chevron-right"; label: Tr.t("Next week"); onClicked: root.go(root.addDays(root.week, 7)) }
                }

                // The week, a card like Settings' rows.
                Rectangle {
                    id: weekCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.r(12)
                    color: root.card
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // Day names, dates, and the all-day events.
                        RowLayout {
                            id: headRow
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.space12
                            Layout.bottomMargin: Theme.space8
                            Layout.rightMargin: Theme.space12
                            spacing: 0
                            Item { Layout.preferredWidth: root.gutter }
                            Repeater {
                                model: root.days
                                ColumnLayout {
                                    id: head
                                    required property var modelData
                                    readonly property bool isToday: Calendar.key(modelData) === Calendar.key(root.today)
                                    // Each day as wide as its column below, whatever its events' names.
                                    readonly property real share: (weekCard.width - Theme.space12 - root.gutter) / 7
                                    Layout.preferredWidth: share
                                    Layout.maximumWidth: share
                                    Layout.minimumWidth: share
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Theme.space4
                                    Caption {
                                        Layout.alignment: Qt.AlignHCenter
                                        font.weight: Font.DemiBold
                                        color: head.isToday ? Theme.accentInk : Theme.overlay1
                                        text: Tr.dates.toString(head.modelData, "ddd").toUpperCase()
                                    }
                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitWidth: 36; implicitHeight: 36; radius: 18
                                        color: head.isToday ? Theme.accent : headArea.containsMouse ? Theme.hoverOn(parent) : "transparent"
                                        Label {
                                            anchors.centerIn: parent
                                            font.pixelSize: Theme.fontSizeLarge
                                            font.weight: Font.DemiBold
                                            color: head.isToday ? Theme.textOnAccent : Theme.text
                                            text: head.modelData.getDate()
                                        }
                                        // A new all-day event on this day.
                                        PressArea {
                                            id: headArea
                                            anchors.fill: parent
                                            label: Tr.t("New event")
                                            onClicked: root.edit({ title: "", day: head.modelData, start: "", end: "", allDay: true, remind: 0 })
                                        }
                                    }
                                    Repeater {
                                        model: Calendar.on(head.modelData).filter(e => e.allDay)
                                        Rectangle {
                                            id: chip
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 0
                                            Layout.leftMargin: 3; Layout.rightMargin: 3
                                            implicitHeight: 24
                                            radius: Theme.r(8)
                                            color: Theme.accent
                                            Label {
                                                anchors { fill: parent; leftMargin: Theme.space8; rightMargin: Theme.space6 }
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.DemiBold
                                                color: Theme.textOnAccent
                                                text: chip.modelData.title
                                            }
                                            PressArea { anchors.fill: parent; label: chip.modelData.title; onClicked: root.edit(chip.modelData) }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.base }

                        // Hours.
                        Flickable {
                            id: grid
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentHeight: 24 * root.hourHeight
                            boundsBehavior: Flickable.StopAtBounds

                            Item {
                                width: grid.width - Theme.space12
                                height: grid.contentHeight

                                Repeater {
                                    model: 24
                                    Item {
                                        required property int index
                                        y: index * root.hourHeight
                                        width: parent.width
                                        height: root.hourHeight
                                        Caption {
                                            x: 0; y: -height / 2
                                            width: root.gutter - 12
                                            visible: parent.index > 0
                                            horizontalAlignment: Text.AlignRight
                                            font.family: Theme.monoFamily
                                            text: root.pad(parent.index) + ":00"
                                        }
                                        Rectangle { x: root.gutter; width: parent.width - root.gutter; height: 1; color: Theme.base; visible: parent.index > 0 }
                                    }
                                }

                                Row {
                                    x: root.gutter
                                    width: parent.width - root.gutter
                                    height: parent.height
                                    Repeater {
                                        model: root.days
                                        Item {
                                            id: column
                                            required property var modelData
                                            width: parent.width / 7
                                            height: parent.height
                                            Rectangle { width: 1; height: parent.height; color: Theme.base }

                                            // An empty hour: a new event there.
                                            MouseArea {
                                                id: slot
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => root.newAt(column.modelData, Math.floor(mouse.y / root.hourHeight))
                                            }
                                            Rectangle {
                                                visible: slot.containsMouse && root.editing === null
                                                x: 3; width: parent.width - 6
                                                y: Math.floor(slot.mouseY / root.hourHeight) * root.hourHeight + 1
                                                height: root.hourHeight - 2
                                                radius: Theme.r(8)
                                                color: Theme.tint(root.card, Theme.text, 0.05)
                                            }

                                            Repeater {
                                                model: Calendar.on(column.modelData).filter(e => !e.allDay)
                                                Rectangle {
                                                    id: block
                                                    required property var modelData
                                                    readonly property real from: modelData.start.slice(0, 10) === Calendar.key(column.modelData) ? parseInt(modelData.start.slice(11, 13)) + parseInt(modelData.start.slice(14, 16)) / 60 : 0
                                                    readonly property real to: modelData.end.slice(0, 10) === Calendar.key(column.modelData) ? parseInt(modelData.end.slice(11, 13)) + parseInt(modelData.end.slice(14, 16)) / 60 : 24
                                                    x: 3
                                                    y: from * root.hourHeight + 1
                                                    width: column.width - 6
                                                    height: Math.max(24, (to - from) * root.hourHeight - 2)
                                                    radius: Theme.r(8)
                                                    color: blockArea.containsMouse ? Theme.accentBright : Theme.accent
                                                    Behavior on color { ColorAnim {} }
                                                    Column {
                                                        anchors { fill: parent; margins: Theme.space6; leftMargin: Theme.space8 }
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
                                                            visible: block.height > 40
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            color: Theme.textOnAccent
                                                            text: block.modelData.start.slice(11, 16) + " – " + block.modelData.end.slice(11, 16)
                                                        }
                                                    }
                                                    PressArea { id: blockArea; anchors.fill: parent; label: block.modelData.title; onClicked: root.edit(block.modelData) }
                                                }
                                            }

                                            // Now.
                                            Rectangle {
                                                visible: Calendar.key(column.modelData) === Calendar.key(root.today)
                                                y: (clock.now.getHours() + clock.now.getMinutes() / 60) * root.hourHeight - 1
                                                width: parent.width; height: 2
                                                color: Theme.accentInk
                                                Rectangle { x: -4; y: -3; width: 8; height: 8; radius: 4; color: Theme.accentInk }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Adding or changing an event: a card like Settings', over the window.
        Rectangle {
            anchors.fill: parent
            visible: root.editing !== null
            color: Qt.rgba(0, 0, 0, 0.4)
            MouseArea { anchors.fill: parent; onClicked: root.editing = null }

            Rectangle {
                anchors.centerIn: parent
                width: 460
                height: form.implicitHeight + 2 * Theme.space24
                radius: Theme.r(18)
                color: Theme.base
                border { width: 1; color: Theme.rimOn(parent) }
                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: form
                    anchors { fill: parent; margins: Theme.space24 }
                    spacing: Theme.space12
                    Keys.onEscapePressed: root.editing = null

                    ColumnLayout {
                        spacing: 0
                        Label {
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            text: root.editing?.id ? Tr.t("Change event") : Tr.t("New event")
                        }
                        Caption { text: root.editing ? Tr.dates.toString(root.editing.day, "dddd, d MMMM yyyy") : "" }
                    }
                    Field {
                        id: title
                        Layout.fillWidth: true
                        placeholder: Tr.t("Title")
                        input.Keys.onReturnPressed: root.save()
                    }

                    // The rest in a card, as Settings' rows are.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rows.implicitHeight + 2 * Theme.space12
                        radius: Theme.r(12)
                        color: root.card
                        ColumnLayout {
                            id: rows
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space16; topMargin: Theme.space12 }
                            spacing: Theme.space12
                            RowLayout {
                                Layout.fillWidth: true
                                Label { Layout.fillWidth: true; text: Tr.t("All day") }
                                Switch {
                                    checked: root.editing?.allDay ?? false
                                    onToggled: on => root.editing = Object.assign({}, root.editing, { allDay: on, remind: on ? 0 : 15 })
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: !(root.editing?.allDay ?? false)
                                spacing: Theme.space8
                                Label { Layout.fillWidth: true; text: Tr.t("Time") }
                                Field { id: startField; implicitWidth: 92; mono: true; placeholder: "09:00"; input.Keys.onReturnPressed: root.save() }
                                Label { text: "–"; color: Theme.overlay1 }
                                Field { id: endField; implicitWidth: 92; mono: true; placeholder: "10:00"; input.Keys.onReturnPressed: root.save() }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space8
                                Label { text: Tr.t("Reminder") }
                                Choice {
                                    Layout.fillWidth: true
                                    stretch: true
                                    options: (root.editing?.allDay ?? false)
                                        ? [{ value: -1, label: Tr.t("None") }, { value: 0, label: Tr.t("In the morning") }]
                                        : [{ value: -1, label: Tr.t("None") }, { value: 0, label: Tr.t("At start") }, { value: 15, label: "15 min" },
                                           { value: 60, label: "1 h" }, { value: 1440, label: Tr.t("1 day") }]
                                    current: root.editing?.remind ?? -1
                                    onPicked: v => root.editing = Object.assign({}, root.editing, { remind: v })
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.space4
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

    component SectionTitle: Label {
        Layout.topMargin: Theme.space16
        Layout.bottomMargin: Theme.space4
        Layout.leftMargin: Theme.space6
        font.weight: Font.Bold
        font.pixelSize: Theme.fontSizeLabel
    }
}
