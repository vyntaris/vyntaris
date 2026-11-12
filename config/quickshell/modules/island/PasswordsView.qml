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
        : editingIdentity ? "identity"
        : editingNote ? "note"
        : editing ? "edit"
        : "list"
    property bool editing: false
    property bool editingIdentity: false
    property bool editingNote: false
    property string editingName: ""
    property int current: 0
    readonly property var rows: Passwords.search(search.text).slice(0, 7)
    onRowsChanged: current = Math.min(current, Math.max(0, rows.length - 1))

    onActiveChanged: if (active) {
        editing = false;
        editingIdentity = false;
        editingNote = false;
        Passwords.wrong = false;
        search.text = Passwords.site || "";
        if (search.text && (Passwords.tab !== "logins" || !Passwords.entries.some(e => Passwords.matches(e, Passwords.site)))) search.text = "";
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
        onTriggered: (root.page === "setup" ? (Config.passwords.withLogin ? content : phrase.input) : root.page === "unlock" ? unlockField.input
            : root.page === "edit" ? (!nameField.text ? nameField.input : !userField.text ? userField.input : passField.input)
            : root.page === "identity" ? identityLabel.input : root.page === "note" ? noteLabel.input : search.input).forceActiveFocus()
    }

    // Opened from an entry: its fields; "New": the site that asked.
    Connections {
        target: Passwords
        function onOpened(name, text) {
            const kind = Passwords.kindOf(name);
            if (kind === "notes") { root.editNote(name, Passwords.noteOf(text)); return; }
            if (kind !== "logins") { root.editIdentity(name, Passwords.fieldsOf(text), kind); return; }
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
        if (Passwords.tab === "people" || Passwords.tab === "cards") { editIdentity("", {}, Passwords.tab); return; }
        if (Passwords.tab === "notes") { editNote("", ""); return; }
        editingName = "";
        nameField.text = Passwords.site || search.text.trim();
        userField.text = "";
        passField.text = "";
        urlField.text = Passwords.site;
        passField.revealed = false;
        editing = true;
        Passwords.generate();
    }
    // Personal info or a card: a new one, or one opened to change.
    property string identityName: ""
    property string identityKind: "people"
    readonly property var identityLabels: ({
        first: Tr.t("First name"), last: Tr.t("Last name"), username: Tr.t("Username"), email: Tr.t("Email"),
        phone: Tr.t("Phone"), address: Tr.t("Address"), city: Tr.t("City"), postal: Tr.t("Postal code"),
        country: Tr.t("Country"), company: Tr.t("Company"),
        holder: Tr.t("Name on card"), number: Tr.t("Card number"), expiry: Tr.t("Expires (MM/YY)"), cvv: Tr.t("Security code (CVV)"),
    })
    function editIdentity(name, values, kind) {
        identityKind = kind ?? "people";
        identityName = name;
        identityLabel.text = name ? Passwords.labelOf(name) : identityKind === "cards" ? "" : Tr.t("Me");
        for (let i = 0; i < identityFields.count; i++) {
            const f = identityFields.itemAt(i);
            f.text = values[f.key] ?? "";
        }
        editingIdentity = true;
    }
    function saveIdentity() {
        const values = {};
        for (let i = 0; i < identityFields.count; i++) {
            const f = identityFields.itemAt(i);
            values[f.key] = f.text;
        }
        Passwords.saveFields(identityKind, identityLabel.text, values, identityName);
        editingIdentity = false;
    }

    // A note: a new one, or one opened to read or change.
    property string noteName: ""
    function editNote(name, text) {
        noteName = name;
        noteLabel.text = name ? Passwords.labelOf(name) : "";
        noteText.text = text;
        editingNote = true;
    }
    function saveNote() {
        Passwords.saveNote(noteLabel.text, noteText.text, noteName);
        editingNote = false;
    }
    // Ctrl+C on an entry: a login's password, a card's number, a note's text.
    function copyOf(name) {
        const kind = Passwords.kindOf(name);
        if (kind === "people") return;
        Passwords.copy(name, kind === "cards" ? "field:number" : kind === "notes" ? "note" : "");
        Panels.passwordsOpen = false;
    }

    readonly property var tabs: ["logins", "people", "cards", "notes"]
    function cycleTab(step) {
        Passwords.tab = tabs[(tabs.indexOf(Passwords.tab) + step + tabs.length) % tabs.length];
        current = 0;
    }

    function pick(name) {
        if (!name) return;
        // A note is only read; personal info and cards fill a form, or open when nothing asked.
        if (Passwords.kindOf(name) === "notes" || Passwords.kindOf(name) !== "logins" && !Passwords.site && !Passwords.app) Passwords.show(name);
        else if (Passwords.site || Passwords.app) Passwords.fill(name);
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
            visible: root.page === "list" && !Passwords.locked && !Config.passwords.withLogin
            icon: "lock"; label: Tr.t("Lock")
            onClicked: { Passwords.lock(); Panels.passwordsOpen = false; }
        }
        HeaderButton { icon: "close"; label: Tr.t("Close"); onClicked: Panels.passwordsOpen = false }
    }

    PanelBody {
        id: content
        spacing: Theme.space10

        Keys.onReturnPressed: if (root.page === "setup") setupButton.clicked()
        Keys.onEscapePressed: {
            if (root.page !== "list") { root.editing = false; root.editingIdentity = false; root.editingNote = false; focusLater.restart(); }
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

        // The first time: a master password for the new store, or only a yes when the login opens it.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.page === "setup"
            spacing: Theme.space10
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtext0
                text: Config.passwords.withLogin
                    ? Tr.t("Your passwords are kept encrypted on this computer, and open when you sign in. Anyone who knows your login password can read them.")
                    : Tr.t("Your passwords are kept encrypted on this computer. Pick a master password: it's asked when you use them, and again after the screen locks. If you forget it, they can't be read.")
            }
            Field {
                id: phrase
                Layout.fillWidth: true
                visible: !Config.passwords.withLogin
                secret: true; canReveal: true
                placeholder: Tr.t("Master password")
                input.Keys.onReturnPressed: phrase2.input.forceActiveFocus()
            }
            Field {
                id: phrase2
                Layout.fillWidth: true
                visible: !Config.passwords.withLogin
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
                    active: !Passwords.busy && (Config.passwords.withLogin || phrase.text.length >= 6 && phrase.text === phrase2.text)
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
            Label {
                Layout.fillWidth: true
                visible: Config.passwords.withLogin && !Passwords.wrong
                wrapMode: Text.Wrap
                color: Theme.overlay1
                text: Tr.t("Asked this once: from now on your passwords open when you sign in.")
            }
        }

        // The list: the passwords, or the personal info.
        Choice {
            Layout.fillWidth: true
            visible: root.page === "list"
            stretch: true
            options: [{ value: "logins", label: Tr.t("Passwords") }, { value: "people", label: Tr.t("Personal info") },
                { value: "cards", label: Tr.t("Cards") }, { value: "notes", label: Tr.t("Notes") }]
            current: Passwords.tab
            onPicked: v => { Passwords.tab = v; root.current = 0; focusLater.restart(); }
        }
        SearchField {
            id: search
            Layout.fillWidth: true
            visible: root.page === "list"
            placeholder: Passwords.tab === "people" ? Tr.t("Search personal info…") : Passwords.tab === "cards" ? Tr.t("Search cards…")
                : Passwords.tab === "notes" ? Tr.t("Search notes…") : Tr.t("Search passwords…")
            count: text.trim() ? Passwords.search(text).length : -1
            input.onTextChanged: root.current = 0
            input.Keys.onDownPressed: root.current = Math.min(root.current + 1, root.rows.length - 1)
            input.Keys.onUpPressed: root.current = Math.max(root.current - 1, 0)
            input.Keys.onTabPressed: root.cycleTab(1)
            input.Keys.onBacktabPressed: root.cycleTab(-1)
            input.Keys.onReturnPressed: event => {
                if (event.modifiers & Qt.ControlModifier) root.newEntry();
                else if (root.rows.length) root.pick(root.rows[root.current]);
                else root.newEntry();
            }
            input.Keys.onPressed: event => {
                const name = root.rows[root.current];
                if (!(event.modifiers & Qt.ControlModifier) || !name) return;
                const login = Passwords.kindOf(name) === "logins";
                if (event.key === Qt.Key_C && Passwords.kindOf(name) !== "people") root.copyOf(name);
                else if (event.key === Qt.Key_B && login) { Passwords.copy(name, "login"); Panels.passwordsOpen = false; }
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
                    readonly property string kind: Passwords.kindOf(modelData)
                    readonly property var parts: kind !== "logins" ? [Passwords.labelOf(modelData)] : modelData.split("/")
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
                            size: 30; visible: row.chosen && row.kind === "logins"; ink: Theme.textOnAccent; icon: "users"; label: Tr.t("Copy username")
                            onClicked: { Passwords.copy(row.modelData, "login"); Panels.passwordsOpen = false; }
                        }
                        IconButton {
                            size: 30; visible: row.chosen && row.kind !== "people"; ink: Theme.textOnAccent; icon: "copy"
                            label: row.kind === "cards" ? Tr.t("Copy card number") : row.kind === "notes" ? Tr.t("Copy note") : Tr.t("Copy password")
                            onClicked: root.copyOf(row.modelData)
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
                wrapMode: Text.Wrap
                text: Passwords.tab !== "logins" && search.text.trim() ? Tr.t("Nothing found. Enter adds it.")
                    : Passwords.tab === "people" ? Tr.t("Add your personal info (Enter) and sign-ups fill themselves.")
                    : Passwords.tab === "cards" ? Tr.t("No cards yet. Enter adds one, and checkouts fill themselves.")
                    : Passwords.tab === "notes" ? Tr.t("No notes yet. Enter adds one: PINs, recovery codes, anything.")
                    : Passwords.entries.length === 0 ? Tr.t("No passwords yet. Enter adds one.")
                    : Tr.t("Nothing found. Enter adds it.")
            }
            KeyHints {
                Layout.topMargin: Theme.space4
                visible: root.rows.length > 0
                keys: Passwords.tab === "people" ? [["↵", Tr.t("fill")], ["Ctrl+E", Tr.t("edit")]]
                    : Passwords.tab === "cards" ? [["↵", Tr.t("fill")], ["Ctrl+C", Tr.t("number")], ["Ctrl+E", Tr.t("edit")]]
                    : Passwords.tab === "notes" ? [["↵", Tr.t("open")], ["Ctrl+C", Tr.t("copy")]]
                    : [["↵", Passwords.site || Passwords.app ? Tr.t("fill") : Tr.t("copy")],
                    ["Ctrl+C", Tr.t("password")], ["Ctrl+B", Tr.t("username")], ["Ctrl+E", Tr.t("edit")]]
            }
        }

        // Personal info: what sign-ups ask for.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.page === "identity"
            spacing: Theme.space8
            Field {
                id: identityLabel
                Layout.fillWidth: true
                placeholder: root.identityKind === "cards" ? Tr.t("Name for it, like Visa") : Tr.t("Name for it, like Me or Work")
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.space8
                rowSpacing: Theme.space8
                Repeater {
                    id: identityFields
                    model: root.identityKind === "cards" ? Passwords.cardKeys : Passwords.identityKeys
                    Field {
                        required property string modelData
                        readonly property string key: modelData
                        Layout.fillWidth: true
                        mono: key === "number" || key === "cvv" || key === "expiry"
                        secret: key === "cvv"; canReveal: secret
                        placeholder: root.identityLabels[modelData]
                        input.Keys.onReturnPressed: identitySave.clicked()
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space6
                Button {
                    visible: root.identityName !== ""
                    danger: true
                    icon: "trash"
                    text: Tr.t("Delete")
                    onClicked: { Passwords.remove(root.identityName); root.editingIdentity = false; }
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: Tr.t("Cancel")
                    onClicked: root.editingIdentity = false
                }
                Button {
                    id: identitySave
                    primary: true
                    icon: "check"
                    active: identityLabel.text.trim() !== ""
                    text: Tr.t("Save")
                    onClicked: if (active) root.saveIdentity()
                }
            }
        }

        // A note: PINs, recovery codes, anything kept as text.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.page === "note"
            spacing: Theme.space8
            Field {
                id: noteLabel
                Layout.fillWidth: true
                placeholder: Tr.t("Name for it, like Bank PIN")
                input.Keys.onReturnPressed: noteText.forceActiveFocus()
            }
            PanelSurface {
                Layout.fillWidth: true
                implicitHeight: 160
                radius: Theme.r(16)
                fill: Theme.tint(parent, Theme.text, noteText.activeFocus ? 0.09 : 0.05)
                edgeWidth: noteText.activeFocus ? 2 : 1
                edge: noteText.activeFocus ? Theme.accentInk : Theme.controlEdge
                Flickable {
                    id: noteFlick
                    anchors { fill: parent; margins: Theme.space12 }
                    clip: true
                    contentHeight: noteText.contentHeight
                    TextEdit {
                        id: noteText
                        width: noteFlick.width
                        wrapMode: TextEdit.Wrap
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.textOnAccent
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontSize
                        Accessible.role: Accessible.EditableText
                        Accessible.name: Tr.t("Note")
                        onCursorRectangleChanged: if (cursorRectangle.y + cursorRectangle.height > noteFlick.contentY + noteFlick.height)
                            noteFlick.contentY = cursorRectangle.y + cursorRectangle.height - noteFlick.height
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) { noteSave.clicked(); event.accepted = true; }
                        }
                        Label {
                            visible: !noteText.text
                            color: Theme.overlay1
                            text: Tr.t("Anything to keep safe")
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space6
                Button {
                    visible: root.noteName !== ""
                    danger: true
                    icon: "trash"
                    text: Tr.t("Delete")
                    onClicked: { Passwords.remove(root.noteName); root.editingNote = false; }
                }
                Button {
                    visible: root.noteName !== ""
                    icon: "copy"
                    text: Tr.t("Copy")
                    onClicked: root.copyOf(root.noteName)
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: Tr.t("Cancel")
                    onClicked: root.editingNote = false
                }
                Button {
                    id: noteSave
                    primary: true
                    icon: "check"
                    active: noteLabel.text.trim() !== ""
                    text: Tr.t("Save")
                    onClicked: if (active) root.saveNote()
                }
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
