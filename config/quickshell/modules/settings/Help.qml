import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    Connections {
        target: Panels
        function onHelpOpenChanged() { if (Panels.helpOpen) root.opened(); }
    }
    Component.onCompleted: if (Panels.helpOpen) opened()
    function opened() {
        Shortcuts.refresh();
        side.search.text = "";
        focusLater.restart();
    }
    Timer { id: focusLater; interval: 60; onTriggered: side.search.input.forceActiveFocus() }

    // The shortcut taking new keys, by the keys it comes with; the keys pressed, when they're another one's.
    property string editing: ""
    property string pending: ""
    property var conflict: null
    readonly property var pendingKeys: pending ? Shortcuts.display(pending) : []
    function edit(entry) {
        editing = entry.default;
        pending = "";
        conflict = null;
        Shortcuts.record(true);
        catcher.forceActiveFocus();
    }
    function stop() {
        asking = false;
        editing = "";
        pending = "";
        conflict = null;
        Shortcuts.record(false);
    }
    function apply(entry, combo) {
        Shortcuts.set(entry, combo);
        stop();
    }
    // Its own keys back, unless another shortcut has them now: then that's said.
    property bool asking: false
    function reset(entry) {
        const other = Shortcuts.takenBy(entry.default, entry.default);
        if (!other) { Shortcuts.set(entry, entry.default); return; }
        stop();
        asking = true;
        editing = entry.default;
        pending = entry.default;
        conflict = other;
    }
    function pressed(event) {
        const entry = Shortcuts.list.find(b => b.default === editing);
        const combo = Shortcuts.comboOf(event);
        if (!entry || !combo) return;
        if (combo === "Escape") { stop(); return; }
        if (combo === "BackSpace") { apply(entry, ""); return; }
        const other = Shortcuts.takenBy(combo, entry.default);
        if (!other) { apply(entry, combo); return; }
        // Said, and other keys can be pressed straight away.
        pending = combo;
        conflict = other;
        Shortcuts.record(true);
    }
    Connections {
        target: Shortcuts
        function onRecordingChanged() { if (!Shortcuts.recording && !root.asking) root.stop(); }
    }

    // Shortcuts change only once Edit is pressed, so a click while reading changes nothing.
    property bool editMode: false
    onEditModeChanged: if (!editMode) stop()

    property string page: "all"
    property string query: ""
    readonly property var pages: [{ id: "all", label: Tr.t("All shortcuts"), icon: "keyboard" }].concat(Shortcuts.groups)

    readonly property var shown: {
        const words = query.trim().toLowerCase().split(/\s+/).filter(w => w);
        if (words.length > 0)
            return Shortcuts.list.filter(b => words.every(w => (b.what + " " + b.keys.join(" ")).toLowerCase().includes(w)));
        return Shortcuts.list.filter(b => page === "all" || b.group === page);
    }
    readonly property var sections: pages.slice(1)
        .map(g => ({ id: g.id, label: g.label, items: shown.filter(b => b.group === g.id) }))
        .filter(g => g.items.length > 0)

    FloatingWindow {
        id: win
        visible: Panels.helpOpen
        title: Tr.t("Help")
        implicitWidth: 866
        implicitHeight: Math.min(Math.max(side.needed, 640), (screen?.height ?? 1080) * 0.9)
        minimumSize: Qt.size(700, 480)
        color: Theme.base

        onVisibleChanged: if (!visible) { Panels.helpOpen = false; root.editMode = false; root.stop(); }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Panels.helpOpen = false
        }
        // Takes the keys while a shortcut is getting new ones.
        Item {
            id: catcher
            Keys.onPressed: event => { event.accepted = true; root.pressed(event); }
            onActiveFocusChanged: if (!activeFocus && root.editing && root.pending === "") root.stop()
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            SideNav {
                id: side
                icon: "keyboard"
                title: Tr.t("Shortcuts")
                subtitle: Distro.name
                searchHint: Tr.t("Search shortcuts")
                pages: root.pages
                current: root.query.trim() !== "" ? "" : root.page
                onPicked: id => { side.search.text = ""; root.page = id; flick.contentY = 0; }
                Connections {
                    target: side.search.input
                    function onTextChanged() { root.query = side.search.text; flick.contentY = 0; }
                }
                Keys.onEscapePressed: Panels.helpOpen = false
                Shortcut {
                    sequence: "Ctrl+F"
                    onActivated: side.search.input.forceActiveFocus()
                }
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: column.implicitHeight + 48
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: column
                    x: 30
                    y: 24
                    width: parent.width - 60
                    spacing: Theme.space12

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            font.pixelSize: Theme.fontSizeHeading
                            font.weight: Font.Bold
                            text: root.query.trim() !== "" ? Tr.t("Search") : Tr.t(root.pages.find(p => p.id === root.page)?.label ?? "")
                        }
                        Button {
                            visible: Shortcuts.list.some(b => b.editable)
                            icon: root.editMode ? "check" : "edit"
                            text: root.editMode ? Tr.t("Done") : Tr.t("Edit")
                            primary: root.editMode
                            onClicked: root.editMode = !root.editMode
                        }
                    }
                    Label {
                        visible: root.editMode
                        color: Theme.overlay1
                        font.pixelSize: Theme.fontSizeSmall
                        text: Tr.t("Click a shortcut's keys, then press the new ones.")
                    }
                    Label {
                        visible: root.shown.length === 0
                        Layout.topMargin: Theme.space10
                        color: Theme.overlay1
                        text: root.query.trim() !== "" ? Tr.f("No shortcut matches “{0}”", root.query.trim()) : Tr.t("No shortcuts here")
                    }

                    Repeater {
                        model: root.sections
                        ColumnLayout {
                            id: section
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: Theme.space12
                            Label {
                                visible: root.sections.length > 1
                                Layout.topMargin: section.index > 0 ? 10 : 0
                                overline: true
                                color: Theme.accentInk
                                text: Tr.t(section.modelData.label)
                            }
                            Repeater {
                                model: section.modelData.items
                                ColumnLayout {
                                    id: row
                                    required property var modelData
                                    readonly property bool editing: root.editing === modelData.default && modelData.editable
                                    Layout.fillWidth: true
                                    spacing: Theme.space8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.space16
                                        Label { Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.DemiBold; text: row.modelData.what }
                                        IconButton {
                                            visible: root.editMode && row.modelData.changed && !row.editing
                                            icon: "refresh"
                                            size: 28
                                            label: Tr.t("Back to its own keys")
                                            onClicked: root.reset(row.modelData)
                                        }
                                        Rectangle {
                                            id: keysBox
                                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                            implicitWidth: keysRow.implicitWidth + (row.modelData.editable ? 8 : 0)
                                            implicitHeight: 34
                                            radius: Theme.r(12)
                                            color: row.editing ? Theme.alpha(Theme.accent, 0.14) : keysArea.containsMouse ? Theme.tint(parent, Theme.text, 0.06) : "transparent"
                                            border { width: row.editing ? 2 : 0; color: Theme.accentInk }
                                            Row {
                                                id: keysRow
                                                anchors.centerIn: parent
                                                spacing: Theme.space6
                                                Label {
                                                    visible: (row.editing && Shortcuts.recording) || (!row.editing && row.modelData.keys.length === 0)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    leftPadding: Theme.space8; rightPadding: Theme.space8
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: row.editing ? Theme.accentInk : Theme.overlay1
                                                    text: row.editing ? Tr.t("Press the new keys") : Tr.t("Off")
                                                }
                                                Repeater {
                                                    model: row.editing ? (Shortcuts.recording ? [] : root.pendingKeys) : row.modelData.keys
                                                    Rectangle {
                                                        required property string modelData
                                                        width: Math.max(30, key.implicitWidth + 18)
                                                        height: 30
                                                        radius: Theme.r(10)
                                                        color: Theme.tint(parent, Theme.text, 0.04)
                                                        border { width: 1; color: Theme.rimOn(parent) }
                                                        Label {
                                                            id: key
                                                            anchors.centerIn: parent
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            font.weight: Font.DemiBold
                                                            color: Theme.subtext0
                                                            text: modelData
                                                        }
                                                    }
                                                }
                                            }
                                            PressArea {
                                                id: keysArea
                                                anchors.fill: parent
                                                enabled: root.editMode && row.modelData.editable
                                                label: Tr.f("Change the keys for {0}", row.modelData.what)
                                                onClicked: row.editing ? root.stop() : root.edit(row.modelData)
                                            }
                                        }
                                    }
                                    Label {
                                        visible: row.editing && Shortcuts.recording
                                        Layout.alignment: Qt.AlignRight
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.overlay1
                                        text: Tr.t("Esc cancels, Backspace turns it off")
                                    }
                                    // The keys already do something else: that one changes first, these stay.
                                    RowLayout {
                                        visible: row.editing && root.conflict !== null
                                        Layout.alignment: Qt.AlignRight
                                        spacing: Theme.space8
                                        Icon { name: "alert"; size: 14; color: Theme.warning }
                                        Label {
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.warning
                                            text: root.conflict ? Tr.f("{0} is taken by {1}. Change that one first.", root.pendingKeys.join(" + "), root.conflict.what) : ""
                                        }
                                        ChipButton { visible: !Shortcuts.recording; text: Tr.t("OK"); onClicked: root.stop() }
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
