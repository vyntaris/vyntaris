import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root
    property int maxListHeight: 260
    spacing: 10

    SystemClock { id: clock; precision: SystemClock.Minutes }
    function ago(t) {
        const s = Math.max(0, (clock.date - t) / 1000);
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m";
        if (s < 86400) return Math.floor(s / 3600) + "h";
        return Qt.locale("en_US").toString(t, "d MMM");
    }

    readonly property var groups: {
        const out = [], at = {};
        Notifications.history.forEach((e, i) => {
            const app = e.appName || Tr.t("System");
            if (!(app in at)) { at[app] = out.length; out.push({ app, items: [] }); }
            out[at[app]].items.push(i);
        });
        return out;
    }
    property var opened: ({})
    function toggle(app) {
        const next = Object.assign({}, opened);
        next[app] = !next[app];
        opened = next;
    }
    readonly property int count: Notifications.history.length

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label { caps: true; color: Theme.overlay1; text: Tr.t("Notifications") }
        Rectangle {
            visible: root.count > 0
            implicitWidth: countText.implicitWidth + 14
            implicitHeight: 18
            radius: Theme.r(9)
            color: Theme.alpha(Theme.accent, 0.18)
            Label { id: countText; anchors.centerIn: parent; mono: true; font.pixelSize: Theme.fontSizeSmall - 2; color: Theme.accent; text: root.count }
        }
        Item { Layout.fillWidth: true }
        Label {
            visible: root.count > 0
            caps: true
            font.pixelSize: Theme.fontSizeSmall - 1
            color: clearArea.containsMouse ? Theme.error : Theme.overlay0
            text: Tr.t("Clear all")
            MouseArea { id: clearArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifications.clearHistory() }
        }
        Rectangle {
            implicitWidth: 28
            implicitHeight: 28
            radius: 14
            color: Notifications.dnd ? Theme.accent : silentArea.containsMouse ? Theme.alpha(Theme.accent, 0.16) : Theme.alpha(Theme.text, 0.06)
            border { width: 1; color: Notifications.dnd ? Theme.accent : Theme.glassRim }
            Behavior on color { ColorAnim {} }
            Icon { anchors.centerIn: parent; name: Notifications.dnd ? "bell-off" : "bell"; size: 14; color: Notifications.dnd ? Theme.textOnAccent : Theme.subtext0 }
            MouseArea { id: silentArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifications.dnd = !Notifications.dnd }
        }
    }

    readonly property Item body: {
        for (let p = parent; p; p = p.parent)
            if (typeof p.lane === "function" && p.widest !== undefined) return p;
        return null;
    }

    ListView {
        id: list
        Layout.fillWidth: true
        implicitHeight: Math.min(contentHeight, root.maxListHeight)
        visible: root.count > 0
        clip: true
        spacing: 8
        model: root.groups
        boundsBehavior: Flickable.StopAtBounds

        delegate: ColumnLayout {
            id: group
            required property var modelData
            readonly property var items: modelData.items
            readonly property bool many: items.length > 1
            readonly property bool open: many && (root.opened[modelData.app] ?? false)
            width: list.width
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: group.open
                spacing: 8
                Label { caps: true; font.pixelSize: Theme.fontSizeSmall - 1; color: Theme.subtext0; text: group.modelData.app }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall - 1; color: Theme.overlay0; text: group.items.length }
                Item { Layout.fillWidth: true }
                Label {
                    caps: true
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: lessArea.containsMouse ? Theme.accentBright : Theme.accent
                    text: Tr.t("Show less")
                    MouseArea { id: lessArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggle(group.modelData.app) }
                }
                Label {
                    caps: true
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: groupClear.containsMouse ? Theme.error : Theme.overlay0
                    text: Tr.t("Clear")
                    MouseArea { id: groupClear; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifications.removeIndexes(group.items) }
                }
            }

            Repeater {
                model: group.open ? group.items : [group.items[0]]
                NotificationCard {
                    id: noteCard
                    readonly property real lane: root.body ? root.body.lane({ y: group.y + y, height: height }, list) : 0
                    Layout.leftMargin: lane
                    Layout.rightMargin: lane
                    required property int modelData
                    Layout.fillWidth: true
                    entry: Notifications.history[modelData] ?? ({})
                    ago: root.ago(entry.time)
                    stacked: group.many && !group.open ? Math.min(2, group.items.length - 1) : 0
                    more: group.many && !group.open ? group.items.length - 1 : 0
                    onClicked: if (group.many && !group.open) root.toggle(group.modelData.app)
                    onDismissed: group.many && !group.open ? Notifications.removeIndexes(group.items) : Notifications.removeAt(modelData)
                }
            }
        }
    }
}
