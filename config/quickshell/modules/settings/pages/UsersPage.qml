import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    id: page
    pageId: "users"

    onVisibleChanged: if (visible) Accounts.refresh()

    Label {
        visible: Accounts.failure !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.error
        text: Accounts.failure
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space14
        Avatar { size: 56; name: Accounts.self.full; source: Accounts.hasFace ? Accounts.face : ""; version: Accounts.faceVersion }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space2
            Label { font.pixelSize: Theme.fontSizeLarge; font.weight: Font.DemiBold; text: Accounts.self.full }
            Dotted { parts: [Accounts.self.name, Accounts.self.admin ? Tr.t("administrator") : ""] }
        }
    }

    SettingsRow {
        title: Tr.t("Name")
        Field {
            implicitWidth: 240
            text: Accounts.self.full
            onCommitted: t => { if (t.trim() && t.trim() !== Accounts.self.full) Accounts.setName(Accounts.self.name, t.trim()); }
        }
    }
    SettingsRow {
        title: Tr.t("Picture")
        RowLayout {
            spacing: Theme.space8
            Button { text: picking.visible ? Tr.t("Done") : Tr.t("Choose"); onClicked: { picking.visible = !picking.visible; if (picking.visible) Accounts.findPictures(); } }
            Button { visible: Accounts.hasFace; text: Tr.t("Remove"); onClicked: Accounts.clearFace() }
        }
    }
    Flow {
        id: picking
        Layout.fillWidth: true
        visible: false
        spacing: Theme.space8
        Label { visible: Accounts.pictures.length === 0; color: Theme.overlay1; text: Tr.t("No pictures in Pictures yet") }
        Repeater {
            model: Accounts.pictures
            Avatar {
                id: choice
                required property string modelData
                size: 64
                source: modelData
                scale: pickArea.pressed ? 0.94 : pickArea.containsMouse ? 1.06 : 1
                Behavior on scale { Anim { duration: Theme.durationFast; easing.bezierCurve: Theme.curveSpring } }
                PressArea {
                    label: Tr.t("Use this picture")
                    id: pickArea
                    anchors.fill: parent
                    onClicked: { Accounts.setFace(choice.modelData); picking.visible = false; }
                }
            }
        }
    }
    SettingsRow {
        title: Tr.t("Password")
        Button { text: passwordBox.visible ? Tr.t("Cancel") : Tr.t("Change"); onClicked: { passwordBox.visible = !passwordBox.visible; currentPw.text = ""; newPw.text = ""; againPw.text = ""; } }
    }
    RowLayout {
        id: passwordBox
        Layout.fillWidth: true
        visible: false
        spacing: Theme.space8
        Field { id: currentPw; Layout.fillWidth: true; secret: true; canReveal: true; placeholder: Tr.t("Current password") }
        Field { id: newPw; Layout.fillWidth: true; secret: true; canReveal: true; placeholder: Tr.t("New password") }
        Field { id: againPw; Layout.fillWidth: true; secret: true; canReveal: true; placeholder: Tr.t("Once more") }
        Button {
            primary: true
            text: Tr.t("Save")
            active: currentPw.text !== "" && newPw.text.length >= 4 && newPw.text === againPw.text && !Accounts.busy
            onClicked: { Accounts.setOwnPassword(currentPw.text, newPw.text); passwordBox.visible = false; currentPw.text = ""; newPw.text = ""; againPw.text = ""; }
        }
    }
    Label {
        visible: passwordBox.visible && newPw.text !== "" && (newPw.text.length < 4 || (againPw.text !== "" && newPw.text !== againPw.text))
        color: Theme.warning
        text: newPw.text.length < 4 ? Tr.t("4 characters at least") : Tr.t("The two aren't the same")
    }
    // Off: a master password of their own, asked when they're used; picked first when the keyring has the key's.
    SettingsRow {
        title: Tr.t("Passwords open when you sign in")
        Switch {
            id: withLogin
            checked: Config.passwords.withLogin && !masterBox.visible
            onToggled: on => {
                masterLabel.failed = false;
                if (on || !Passwords.kept) { masterBox.visible = false; Passwords.setWithLogin(on); }
                else { masterBox.visible = true; master.text = ""; master2.text = ""; }
                checked = Qt.binding(() => Config.passwords.withLogin && !masterBox.visible);
            }
        }
    }
    RowLayout {
        id: masterBox
        Layout.fillWidth: true
        visible: false
        spacing: Theme.space8
        Field { id: master; Layout.fillWidth: true; secret: true; canReveal: true; placeholder: Tr.t("Master password") }
        Field {
            id: master2; Layout.fillWidth: true; secret: true; revealed: master.revealed; placeholder: Tr.t("Again")
            invalid: text !== "" && text !== master.text
        }
        Button { text: Tr.t("Cancel"); onClicked: masterBox.visible = false }
        Button {
            primary: true
            text: Tr.t("Save")
            active: master.text.length >= 6 && master.text === master2.text && !Passwords.busy
            onClicked: if (active) Passwords.setWithLogin(false, master.text)
        }
    }
    Connections {
        target: Passwords
        function onWithLoginDone(ok) {
            masterLabel.failed = !ok;
            if (ok) { masterBox.visible = false; master.text = ""; master2.text = ""; }
        }
    }
    Label {
        id: masterLabel
        property bool failed: false
        visible: masterBox.visible
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: failed ? Theme.error : Theme.overlay1
        text: failed ? Tr.t("The master password couldn't be set.") : Tr.t("Pick a master password for your passwords: it's asked when you use them. If you forget it, they can't be read.")
    }

    SettingsSection { text: Accounts.others.length ? Tr.t("Other people") : Tr.t("Other people: none") }
    Repeater {
        model: Accounts.others
        RowLayout {
            id: other
            required property var modelData
            Layout.fillWidth: true
            spacing: Theme.space12
            Avatar { name: other.modelData.full }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space2
                Label { Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.DemiBold; text: other.modelData.full }
                Caption { text: other.modelData.name }
            }
            Caption { text: Tr.t("Administrator") }
            Switch { checked: other.modelData.admin; onToggled: on => Accounts.setAdmin(other.modelData.name, on) }
            Button {
                id: removeButton
                property bool asking: false
                danger: asking
                text: asking ? Tr.t("Remove (files stay)") : Tr.t("Remove")
                onClicked: {
                    if (!asking) { asking = true; stopAsking.restart(); return; }
                    asking = false;
                    Accounts.remove(other.modelData.name);
                }
                Timer { id: stopAsking; interval: 5000; onTriggered: removeButton.asking = false }
            }
        }
    }

    // Like the password above: a button until it's wanted, then the few things to fill in, in the same card.
    property bool adding: false
    function stopAdding() { adding = false; newFull.text = ""; newName.text = ""; newName.edited = false; newPass.text = ""; newAdmin.checked = false; }
    SettingsRow {
        title: Tr.t("Add someone")
        RowLayout {
            spacing: Theme.space8
            Button { visible: page.adding; text: Tr.t("Cancel"); onClicked: page.stopAdding() }
            Button {
                primary: page.adding
                icon: "plus"
                text: Tr.t("Add")
                active: !page.adding || (newFull.text.trim() !== "" && /^[a-z_][a-z0-9_-]{0,31}$/.test(newName.text) && newPass.text.length >= 4 && !Accounts.busy)
                onClicked: {
                    if (!page.adding) { page.adding = true; newFull.input.forceActiveFocus(); return; }
                    Accounts.add(newName.text, newFull.text.trim(), newAdmin.checked, newPass.text);
                    page.stopAdding();
                }
            }
        }
    }
    SettingsRow {
        visible: page.adding
        title: Tr.t("Full name")
        Field {
            id: newFull
            implicitWidth: 260
            placeholder: Tr.t("Full name")
            onTextChanged: if (!newName.edited) newName.text = Accounts.nameFor(text)
        }
    }
    SettingsRow {
        visible: page.adding
        title: Tr.t("User name")
        Field {
            id: newName
            property bool edited: false
            implicitWidth: 260
            mono: true
            placeholder: Tr.t("user name")
            input.onTextEdited: edited = true
        }
    }
    SettingsRow {
        visible: page.adding
        title: Tr.t("Password")
        Field { id: newPass; implicitWidth: 260; secret: true; canReveal: true; placeholder: Tr.t("Password") }
    }
    SettingsRow {
        visible: page.adding
        title: Tr.t("Administrator")
        Switch { id: newAdmin; onToggled: on => checked = on }
    }
}
