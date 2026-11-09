import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// Passwords: search, fill into the field that opened it, copy, add and change them.
Item {
    id: root
    readonly property real fullWidth: 600
    readonly property real hang: content.implicitHeight + 26
    readonly property bool active: Panels.passwordsOpen

    width: fullWidth
    height: Theme.barHeight + hang

    readonly property string page: !Passwords.installed ? "missing"
        : !Passwords.ready ? "setup"
        : Passwords.locked && Passwords.pending ? "unlock"
        : editing ? "edit"
        : "list"
    property bool editing: false
    property string editingName: ""
    property int current: 0
    readonly property var rows: Passwords.search(search.text).slice(0, 7)
    onRowsChanged: current = Math.min(current, Math.max(0, rows.length - 1))

    onActiveChanged: if (active) {
        editing = false;
        Passwords.wrong = false;
        search.text = Passwords.site || "";
        if (search.text && !Passwords.entries.some(e => Passwords.matches(e, Passwords.site))) search.text = "";
        current = 0;
        focusLater.restart();
    } else {
        phrase.text = ""; phrase2.text = ""; unlockField.text = "";
        if (!Passwords.busy) Passwords.pending = null;
    }
    Component.onCompleted: if (active) activeChanged()
    onPageChanged: focusLater.restart()
    Timer {
        id: focusLater
        interval: 40
        onTriggered: (root.page === "setup" ? phrase.input : root.page === "unlock" ? unlockField.input
            : root.page === "edit" ? (!nameField.text ? nameField.input : !userField.text ? userField.input : passField.input) : search.input).forceActiveFocus()
    }

    // Opened from an entry: its fields; "New": the site that asked.
    Connections {
        target: Passwords
        function onOpened(name, text) {
            const lines = text.split("\n");
            const pick = re => (lines.find(l => re.test(l)) ?? "").replace(/^[^:]+:\s*/, "");
            root.editingName = name;
            nameField.text = name;
            passField.text = lines[0] ?? "";
            userField.text = pick(/^(login|user|username|email|e-mail):/i)
                || (name.includes("/") ? name.split("/").pop() : "");
            urlField.text = pick(/^url:/i);
            passField.revealed = false;
            root.editing = true;
        }
        function onGenerated(password) { passField.text = password; passField.revealed = true; }
    }
    function newEntry() {
        editingName = "";
        nameField.text = Passwords.site || search.text.trim();
        userField.text = "";
        passField.text = "";
        urlField.text = Passwords.site;
        passField.revealed = false;
        editing = true;
        Passwords.generate();
    }
    function pick(name) {
        if (!name) return;
        if (Passwords.site || Passwords.app) Passwords.fill(name);
        else { Passwords.copy(name); Panels.passwordsOpen = false; }
    }

    PanelHeader {
        icon: "lock"
        title: Passwords.site ? Passwords.site : Passwords.app ? Passwords.app : Tr.t("Passwords")
        HeaderButton {
            visible: root.page === "list"
            icon: "plus"; label: Tr.t("New")
            onClicked: root.newEntry()
        }
        HeaderButton {
            visible: root.page === "list" && !Passwords.locked
            icon: "lock"; label: Tr.t("Lock")
            onClicked: { Passwords.lock(); Panels.passwordsOpen = false; }
        }
        HeaderButton { icon: "close"; label: Tr.t("Close"); onClicked: Panels.passwordsOpen = false }
    }

    PanelBody {
        id: content
        spacing: Theme.space10

        Keys.onEscapePressed: {
            if (root.page === "edit") { root.editing = false; focusLater.restart(); }
            else Panels.passwordsOpen = false;
        }

        // Not installed.
        Label {
            Layout.fillWidth: true
            visible: root.page === "missing"
            wrapMode: Text.Wrap
            color: Theme.overlay1
            text: Tr.t("pass isn't installed.")
        }

        // The first time: a master password for the new store.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.page === "setup"
            spacing: Theme.space10
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtext0
                text: Tr.t("Your passwords are kept encrypted on this computer. Pick a master password: it's asked when you use them, and again after the screen locks. If you forget it, they can't be read.")
            }
            Field {
                id: phrase
                Layout.fillWidth: true
                secret: true; canReveal: true
                placeholder: Tr.t("Master password")
                input.Keys.onReturnPressed: phrase2.input.forceActiveFocus()
            }
            Field {
                id: phrase2
                Layout.fillWidth: true
                secret: true; revealed: phrase.revealed
                invalid: text !== "" && text !== phrase.text
                placeholder: Tr.t("Again")
                input.Keys.onReturnPressed: setupButton.clicked()
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    color: Theme.error
                    visible: Passwords.failure !== ""
                    elide: Text.ElideRight
                    text: Passwords.failure
                }
                Item { Layout.fillWidth: true }
                Button {
                    id: setupButton
                    primary: true
                    icon: Passwords.busy ? "" : "check"
                    active: !Passwords.busy && phrase.text.length >= 6 && phrase.text === phrase2.text
                    text: Passwords.busy ? Tr.t("Setting up…") : Tr.t("Set up")
                    onClicked: if (active) Passwords.setup(phrase.text)
                }
            }
        }

        // Locked: the master password, then what was asked goes on.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.page === "unlock"
            spacing: Theme.space10
            Field {
                id: unlockField
                Layout.fillWidth: true
                secret: true; canReveal: true
                invalid: Passwords.wrong
                placeholder: Tr.t("Master password")
                input.Keys.onReturnPressed: { Passwords.unlock(text); text = ""; }
            }
            Label {
                visible: Passwords.wrong
                color: Theme.error
                text: Tr.t("That isn't the master password.")
            }
        }

        // The list.
        SearchField {
            id: search
            Layout.fillWidth: true
            visible: root.page === "list"
            placeholder: Tr.t("Search passwords…")
            count: text.trim() ? Passwords.search(text).length : -1
            input.onTextChanged: root.current = 0
            input.Keys.onDownPressed: root.current = Math.min(root.current + 1, root.rows.length - 1)
            input.Keys.onUpPressed: root.current = Math.max(root.current - 1, 0)
            input.Keys.onReturnPressed: event => {
                if (event.modifiers & Qt.ControlModifier) root.newEntry();
                else if (root.rows.length) root.pick(root.rows[root.current]);
                else root.newEntry();
            }
            input.Keys.onPressed: event => {
                const name = root.rows[root.current];
                if (!(event.modifiers & Qt.ControlModifier) || !name) return;
                if (event.key === Qt.Key_C) { Passwords.copy(name); Panels.passwordsOpen = false; }
                else if (event.key === Qt.Key_B) { Passwords.copy(name, "login"); Panels.passwordsOpen = false; }
                else if (event.key === Qt.Key_E) Passwords.show(name);
                else return;
                event.accepted = true;
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.page === "list"
            spacing: Theme.space2

            Repeater {
                model: root.rows
                PanelSurface {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool chosen: index === root.current
                    readonly property var parts: modelData.split("/")
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: Theme.r(12)
                    fill: chosen ? Theme.accent : area.containsMouse ? Theme.hoverOn(parent) : "transparent"
                    Behavior on fill { ColorAnim {} }

                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = row.index
                        onClicked: root.pick(row.modelData)
                    }
                    RowLayout {
                        anchors { fill: parent; leftMargin: Theme.space14; rightMargin: Theme.space8 }
                        spacing: Theme.space10
                        Avatar {
                            size: 28
                            name: row.parts.find(p => p.includes(".")) || row.parts[0]
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.weight: Font.DemiBold
                                color: row.chosen ? Theme.textOnAccent : Theme.text
                                text: row.parts.length > 1 ? row.parts.slice(0, -1).join(" / ") : row.parts[0]
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: row.parts.length > 1
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSizeSmall
                                color: row.chosen ? Theme.textOnAccent : Theme.overlay1
                                text: row.parts[row.parts.length - 1]
                            }
                        }
                        IconButton {
                            size: 30; visible: row.chosen; ink: Theme.textOnAccent; icon: "users"; label: Tr.t("Copy username")
                            onClicked: { Passwords.copy(row.modelData, "login"); Panels.passwordsOpen = false; }
                        }
                        IconButton {
                            size: 30; visible: row.chosen; ink: Theme.textOnAccent; icon: "copy"; label: Tr.t("Copy password")
                            onClicked: { Passwords.copy(row.modelData); Panels.passwordsOpen = false; }
                        }
                        IconButton {
                            size: 30; visible: row.chosen; ink: Theme.textOnAccent; icon: "edit"; label: Tr.t("Edit")
                            onClicked: Passwords.show(row.modelData)
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space4
                Layout.bottomMargin: Theme.space4
                visible: root.rows.length === 0
                horizontalAlignment: Text.AlignHCenter
                color: Theme.overlay1
                text: Passwords.entries.length === 0 ? Tr.t("No passwords yet. Enter adds one.")
                    : Tr.t("Nothing found. Enter adds it.")
            }
            KeyHints {
                Layout.topMargin: Theme.space4
                visible: root.rows.length > 0
                keys: [["↵", Passwords.site || Passwords.app ? Tr.t("fill") : Tr.t("copy")],
                    ["Ctrl+C", Tr.t("password")], ["Ctrl+B", Tr.t("username")], ["Ctrl+E", Tr.t("edit")]]
            }
        }

        // A new entry, or one opened to change.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.page === "edit"
            spacing: Theme.space8
            Field {
                id: nameField
                Layout.fillWidth: true
                placeholder: Tr.t("Name, like github.com")
                input.Keys.onReturnPressed: userField.input.forceActiveFocus()
            }
            Field {
                id: userField
                Layout.fillWidth: true
                placeholder: Tr.t("Username or email")
                input.Keys.onReturnPressed: passField.input.forceActiveFocus()
            }
            Field {
                id: passField
                Layout.fillWidth: true
                mono: true
                secret: true; canReveal: true
                extraIcon: "refresh"; extraLabel: Tr.t("New password")
                onExtraClicked: Passwords.generate()
                placeholder: Tr.t("Password")
                input.Keys.onReturnPressed: saveButton.clicked()
            }
            Field {
                id: urlField
                Layout.fillWidth: true
                placeholder: Tr.t("Website (optional)")
                input.Keys.onReturnPressed: saveButton.clicked()
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space6
                Button {
                    visible: root.editingName !== ""
                    danger: true
                    icon: "trash"
                    text: Tr.t("Delete")
                    onClicked: { Passwords.remove(root.editingName); root.editing = false; }
                }
                Label {
                    Layout.fillWidth: true
                    color: Theme.error
                    elide: Text.ElideRight
                    text: Passwords.failure
                }
                Button {
                    text: Tr.t("Cancel")
                    onClicked: root.editing = false
                }
                Button {
                    id: saveButton
                    primary: true
                    icon: "check"
                    active: nameField.text.trim() !== "" && passField.text !== ""
                    text: Tr.t("Save")
                    onClicked: if (active) {
                        Passwords.save(nameField.text, passField.text, userField.text, urlField.text, root.editingName);
                        search.text = nameField.text.trim();
                        root.editing = false;
                    }
                }
            }
        }
    }
}
