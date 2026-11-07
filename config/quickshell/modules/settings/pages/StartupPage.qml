import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components

SettingsPage {
    id: startupPage
    pageId: "startup"
    spacing: Theme.space8

    function add(item) {
        const list = (Config.startup.apps ?? []).slice();
        list.push(item);
        Config.startup.apps = list;
        Config.saveSoon();
    }
    Label {
        visible: (Config.startup.apps ?? []).length === 0
        color: Theme.overlay1
        text: Tr.t("None")
    }
    Repeater {
        model: Config.startup.apps ?? []
        RowLayout {
            id: startRow
            required property var modelData
            required property int index
            readonly property var entry: modelData.id ? DesktopEntries.byId(modelData.id) : null
            Layout.fillWidth: true
            spacing: Theme.space12
            Image {
                Layout.preferredWidth: 24; Layout.preferredHeight: 24
                sourceSize: Qt.size(48, 48)
                source: Quickshell.iconPath(startRow.entry?.icon ?? "", true) || Quickshell.iconPath("application-x-executable", true)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.DemiBold; text: startRow.entry?.name ?? startRow.modelData.name }
                Label {
                    Layout.fillWidth: true; elide: Text.ElideRight; mono: true
                    font.pixelSize: Theme.fontSizeSmall; color: Theme.overlay1
                    text: startRow.modelData.command || (startRow.entry ? startRow.entry.command.join(" ") : Tr.t("not installed any more"))
                }
            }
            Button {
                icon: "trash"; text: Tr.t("Remove")
                onClicked: {
                    const list = (Config.startup.apps ?? []).slice();
                    list.splice(startRow.index, 1);
                    Config.startup.apps = list;
                    Config.saveSoon();
                }
            }
        }
    }
    SettingsSection { text: Tr.t("Add") }
    // Chosen from a dropdown like every other list in Settings, the apps already starting left out.
    property bool picking: false
    SettingsRow {
        title: Tr.t("An app")
        Button { id: appButton; icon: "plus"; text: Tr.t("Choose"); onClicked: startupPage.picking = !startupPage.picking }
    }
    SettingsPicker {
        anchor: appButton
        shown: startupPage.picking
        results: {
            const q = query.trim().toLowerCase();
            const have = (Config.startup.apps ?? []).map(a => a.id);
            return DesktopEntries.applications.values
                .filter(e => !e.noDisplay && !have.includes(e.id)
                    && (!q || e.name.toLowerCase().includes(q) || (e.genericName ?? "").toLowerCase().includes(q)))
                .sort((a, b) => a.name.localeCompare(b.name))
                .map(e => ({ value: e.id, title: e.name, caption: e.genericName ?? "" }));
        }
        empty: Tr.t("Nothing by that name")
        onPicked: v => {
            const e = DesktopEntries.byId(v);
            if (e) startupPage.add({ id: e.id, name: e.name });
            startupPage.picking = false;
        }
        onClosed: startupPage.picking = false
    }
    SettingsRow {
        title: Tr.t("Command")
        RowLayout {
            spacing: Theme.space8
            Field {
                id: startCmd
                Layout.preferredWidth: 260
                mono: true
                placeholder: "discord --start-minimized"
            }
            Button {
                id: addCommand
                icon: "check"; text: Tr.t("Add"); primary: true
                onClicked: {
                    const cmd = startCmd.text.trim();
                    if (!cmd) return;
                    startupPage.add({ id: "", name: cmd.split(" ")[0], command: cmd });
                    startCmd.text = "";
                }
            }
        }
    }
}
