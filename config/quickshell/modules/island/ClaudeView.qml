import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 640
    readonly property real hang: content.implicitHeight + 26
    readonly property bool active: Panels.claudeOpen

    width: fullWidth
    height: Theme.barHeight + hang

    // The sessions on this computer instead of the chat, to go on with one or start one in its folder.
    property bool browsing: false

    onActiveChanged: if (active) { browsing = false; focusLater.restart(); Claude.refreshUsage(false); }
    Component.onCompleted: if (active) activeChanged()
    Timer { id: focusLater; interval: 30; onTriggered: input.forceActiveFocus() }

    function submit() {
        if (Claude.busy && input.text.trim() === "") { Claude.stop(); return; }
        const typed = input.text.trim().slice(1);
        if (suggestions.length && !Claude.commands.includes(typed) && !["clear", "usage", "model", "effort", "compact", "context", "resume"].includes(typed)) {
            complete(suggestions[pick]);
            return;
        }
        Claude.send(input.text);
        input.text = "";
    }
    // The commands that fit what's typed after "/", shortest first.
    property int pick: 0
    readonly property var suggestions: {
        const t = input.text;
        if (!t.startsWith("/") || t.includes(" ")) return [];
        const q = t.slice(1).toLowerCase();
        const all = Array.from(new Set(["clear", "usage", "model", "effort", "compact", "context", "resume"].concat(Claude.commands)));
        return all.filter(c => c.toLowerCase().includes(q) && c !== q)
            .sort((a, b) => (b.startsWith(q) - a.startsWith(q)) || a.length - b.length).slice(0, 6);
    }
    function complete(c) { input.text = "/" + c + " "; input.cursorPosition = input.text.length; input.forceActiveFocus(); }
    function browse(on) {
        browsing = on;
        if (on) Claude.loadSessions(); else focusLater.restart();
    }

    Connections {
        target: Claude
        function onBrowseWanted() { root.browse(true); }
        function onDraftWanted(text) { root.browse(false); input.text = text; input.cursorPosition = text.length; }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    function ago(t) {
        const s = Math.max(0, clock.date / 1000 - t);
        if (s < 60) return Tr.t("now");
        if (s < 3600) return Math.floor(s / 60) + " min";
        if (s < 86400) return Math.floor(s / 3600) + " h";
        return Qt.locale().toString(new Date(t * 1000), "d MMM");
    }
    function modelName(id) {
        const m = String(id).match(/claude-([a-z]+)-(\d+)-(\d+)/);
        return m ? m[1].charAt(0).toUpperCase() + m[1].slice(1) + " " + m[2] + "." + m[3] : "";
    }
    function percent(v) { return Math.round(v * 100) + "%"; }

    // Folders with their latest sessions, newest first.
    readonly property var groups: {
        const out = [], at = {};
        for (const s of Claude.history) {
            if (!(s.cwd in at)) {
                if (out.length >= 6) continue;
                at[s.cwd] = out.length;
                out.push({ cwd: s.cwd, items: [] });
            }
            const g = out[at[s.cwd]];
            if (g.items.length < 4) g.items.push(s);
        }
        return out;
    }

    // A session from elsewhere being watched, else the island's own chat
    readonly property bool watching: Claude.watching !== "" && !browsing
    readonly property var shown: watching ? Claude.watched : Claude.messages

    PanelHeader {
        icon: "claude"
        title: root.browsing ? Tr.t("Sessions") : root.watching ? Tr.f("Claude in {0}", Claude.watchedPlace) : "Claude"
        HeaderButton {
            visible: Claude.loggedIn
            icon: root.browsing || root.watching ? "chevron-left" : "history"
            label: root.browsing || root.watching ? Tr.t("Back") : Tr.t("Sessions")
            onClicked: { if (root.watching) Claude.unwatch(); else root.browse(!root.browsing); }
        }
        HeaderButton { visible: !root.browsing && !root.watching && Claude.messages.length > 0; icon: "plus"; label: Tr.t("New chat"); onClicked: Claude.newChat(Claude.cwd) }
        HeaderButton { visible: Claude.loggedIn && !root.watching; icon: "terminal"; label: Tr.t("Continue in the terminal"); onClicked: { Panels.claudeOpen = false; Claude.openInTerminal(); } }
        HeaderButton { icon: "close"; label: Tr.t("Close"); onClicked: Panels.claudeOpen = false }
    }

    PanelBody {
        id: content
        spacing: Theme.space10

        ColumnLayout {
            Layout.fillWidth: true
            visible: !Claude.installed
            spacing: Theme.space10
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.overlay1
                text: Tr.t("Claude Code isn't installed yet.")
            }
            Button {
                Layout.alignment: Qt.AlignRight
                primary: true
                icon: "download"
                text: Tr.t("Install")
                onClicked: { Panels.claudeOpen = false; Claude.install(); }
            }
        }

        // Signing in: the browser opens, and the island waits for it (or for the code, if the page shows one).
        ColumnLayout {
            Layout.fillWidth: true
            visible: Claude.needsLogin
            spacing: Theme.space12

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2
                    Label { font.weight: Font.DemiBold; text: Claude.signingIn ? Tr.t("Finish signing in in your browser") : Tr.t("Sign in to Claude") }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Theme.subtext0
                        font.pixelSize: Theme.fontSizeSmall
                        text: Claude.signingIn ? Tr.t("The island goes on by itself once you're signed in.")
                            : Tr.t("Use your Claude account (Pro, Max, Team or Enterprise), or an Anthropic Console account billed by use.")
                    }
                }
                Spinner { visible: Claude.signingIn; size: 14 }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !Claude.signingIn
                spacing: Theme.space6
                Button { text: Tr.t("Console account"); onClicked: Claude.login(true) }
                Item { Layout.fillWidth: true }
                Button { primary: true; icon: "users"; text: Tr.t("Sign in with Claude"); onClicked: Claude.login(false) }
            }

            Field {
                id: code
                Layout.fillWidth: true
                visible: Claude.signingIn
                placeholder: Tr.t("Code from the page, if it shows one")
                mono: true
                extraIcon: "check"
                extraLabel: Tr.t("Send")
                onExtraClicked: { Claude.sendCode(text); text = ""; }
                Keys.onReturnPressed: { Claude.sendCode(text); text = ""; }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: Claude.signingIn
                spacing: Theme.space6
                Button {
                    visible: Claude.loginUrl !== ""
                    icon: "external"
                    text: Tr.t("Open the page again")
                    onClicked: Config.launch(["xdg-open", Claude.loginUrl])
                }
                Item { Layout.fillWidth: true }
                Button { text: Tr.t("Cancel"); onClicked: Claude.cancelLogin() }
            }
        }

        // Where it works, which model, how much of the plan is used and what this chat has cost.
        RowLayout {
            Layout.fillWidth: true
            visible: Claude.loggedIn && !root.browsing
            spacing: Theme.space8

            Rectangle {
                implicitWidth: folderRow.implicitWidth + 20
                implicitHeight: 26
                radius: height / 2
                color: folderArea.containsMouse ? Theme.hoverOn(parent) : Theme.tint(parent, Theme.text, 0.05)
                Behavior on color { ColorAnim {} }
                RowLayout {
                    id: folderRow
                    anchors.centerIn: parent
                    spacing: Theme.space6
                    Icon { name: "folder"; size: 13; color: Theme.subtext0 }
                    Label {
                        Layout.maximumWidth: 220
                        elide: Text.ElideMiddle
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.subtext1
                        text: Claude.folderName(root.watching ? (Claude.watchedMeta.cwd || Claude.watchedSession?.cwd || "") : Claude.workdir())
                    }
                }
                PressArea { id: folderArea; anchors.fill: parent; label: Tr.t("Sessions"); onClicked: root.browse(true) }
            }
            Label {
                visible: text !== ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.overlay1
                text: root.watching ? "" : root.modelName(Claude.model)
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: [
                    { name: Tr.t("Session"), part: Claude.usage?.session },
                    { name: Tr.t("Week"), part: Claude.usage?.week },
                ].filter(u => !!u.part)
                RowLayout {
                    required property var modelData
                    spacing: Theme.space4
                    Label { font.pixelSize: Theme.fontSizeSmall; color: Theme.overlay1; text: modelData.name }
                    Meter {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 6
                        count: 10
                        value: modelData.part.used
                        fillColor: modelData.part.used >= 0.8 ? Theme.warning : Theme.accent
                    }
                    // the time it resets, while the pointer is on it
                    Label {
                        font.pixelSize: Theme.fontSizeSmall
                        color: modelData.part.used >= 0.8 ? Theme.warning : Theme.subtext0
                        text: usageHover.hovered && modelData.part.resets ? Tr.f("resets {0}", modelData.part.resets) : root.percent(modelData.part.used)
                    }
                    HoverHandler { id: usageHover }
                }
            }
            Label {
                visible: Claude.cost > 0 && !root.watching
                mono: true
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.overlay1
                text: "$" + Claude.cost.toFixed(2)
            }
        }

        Flickable {
            id: sessions
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.implicitHeight, 420)
            visible: root.browsing
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: list
                width: sessions.width
                spacing: Theme.space4

                Label {
                    Layout.fillWidth: true
                    visible: root.groups.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.overlay1
                    text: Claude.loadingHistory ? Tr.t("Searching…") : Tr.t("No sessions yet")
                }

                Repeater {
                    model: root.groups
                    ColumnLayout {
                        id: group
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.topMargin: index > 0 ? Theme.space8 : 0
                        spacing: Theme.space2

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.space14
                            spacing: Theme.space6
                            Caption { Layout.fillWidth: true; elide: Text.ElideMiddle; text: Claude.folderName(group.modelData.cwd) }
                            HeaderButton {
                                icon: "plus"
                                label: Tr.t("New chat here")
                                onClicked: { Claude.newChat(group.modelData.cwd); root.browse(false); }
                            }
                        }

                        Repeater {
                            model: group.modelData.items
                            PanelSurface {
                                id: row
                                required property var modelData
                                readonly property bool chosen: modelData.id === (Claude.watching || Claude.sessionId)
                                // running right now somewhere else: opened to watch, not to take over
                                readonly property bool live: Claude.sessions.some(s => s.id === modelData.id && s.state !== "done")
                                Layout.fillWidth: true
                                implicitHeight: 38
                                radius: Theme.r(12)
                                fill: chosen ? Theme.accent : rowArea.containsMouse ? Theme.hoverOn(parent) : "transparent"
                                Behavior on fill { ColorAnim {} }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: Theme.space14; rightMargin: Theme.space14 }
                                    spacing: Theme.space12
                                    Label {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.weight: row.chosen ? Font.DemiBold : Font.Normal
                                        color: row.chosen ? Theme.textOnAccent : Theme.text
                                        text: row.modelData.title
                                    }
                                    Spinner { visible: row.live; size: 11; color: row.chosen ? Theme.textOnAccent : Theme.accent }
                                    Label {
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: row.chosen ? Theme.textOnAccent : Theme.overlay1
                                        text: row.live ? Tr.t("working") : root.ago(row.modelData.at)
                                    }
                                }
                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (row.live) Claude.watch(row.modelData.id);
                                        else { Claude.unwatch(); Claude.resume(row.modelData); }
                                        root.browse(false);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Flickable {
            id: chat
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(column.implicitHeight, 420)
            visible: root.shown.length > 0 && !root.browsing
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

            ColumnLayout {
                id: column
                width: chat.width
                spacing: Theme.space10

                Repeater {
                    model: root.shown
                    ColumnLayout {
                        id: msg
                        required property var modelData
                        readonly property bool mine: modelData.role === "user"
                        readonly property bool isNote: modelData.role === "note"
                        Layout.fillWidth: true
                        spacing: Theme.space4

                        Item {
                            visible: msg.mine
                            Layout.fillWidth: true
                            implicitHeight: bubble.height
                            Rectangle {
                                id: bubble
                                anchors.right: parent.right
                                width: Math.min(mineText.implicitWidth, chat.width * 0.8 - 28) + 28
                                height: mineText.height + 16
                                radius: Math.min(16, height / 2)
                                color: Theme.accent
                                Label {
                                    id: mineText
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, chat.width * 0.8 - 28)
                                    wrapMode: Text.Wrap
                                    color: Theme.textOnAccent
                                    text: msg.modelData.text
                                }
                            }
                        }

                        Repeater {
                            model: msg.mine || msg.isNote ? [] : msg.modelData.tools
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.space8
                                Icon { name: modelData.icon; size: 13; color: Theme.overlay1 }
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    mono: true
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.overlay1
                                    text: modelData.text
                                }
                            }
                        }

                        Text {
                            visible: !msg.mine && msg.modelData.text !== ""
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            textFormat: msg.isNote ? Text.PlainText : Text.MarkdownText
                            horizontalAlignment: msg.isNote ? Text.AlignHCenter : Text.AlignLeft
                            opacity: msg.isNote ? 0.7 : 1
                            color: Theme.text
                            linkColor: Theme.accentInk
                            font { family: Theme.fontFamily; pixelSize: Theme.fontSize }
                            text: msg.modelData.text
                            onLinkActivated: link => Config.launch(["xdg-open", link])
                        }
                        Label {
                            visible: !msg.mine && (msg.modelData.cost ?? 0) > 0
                            mono: true
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.overlay0
                            text: "$" + (msg.modelData.cost ?? 0).toFixed(3)
                        }
                    }
                }

                RowLayout {
                    visible: root.watching ? Claude.watchedState === "working" : Claude.busy
                    spacing: Theme.space8
                    Spinner { size: 12 }
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Theme.overlay1
                        font.pixelSize: Theme.fontSizeSmall
                        text: root.watching ? Claude.doingText(Claude.watchedSession?.doing) : Claude.doingText(Claude.chatDoing)
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: Claude.error !== ""
            wrapMode: Text.Wrap
            color: Theme.error
            font.pixelSize: Theme.fontSizeSmall
            text: Claude.error
        }

        // Typing "/": Claude's commands for this chat, Tab or a click fills one in.
        ColumnLayout {
            Layout.fillWidth: true
            visible: suggestions.length > 0 && !root.browsing
            spacing: Theme.space2
            Repeater {
                model: root.suggestions
                PanelSurface {
                    id: sug
                    required property var modelData
                    required property int index
                    readonly property bool chosen: index === root.pick
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(10)
                    fill: chosen ? Theme.accent : sugArea.containsMouse ? Theme.hoverOn(parent) : "transparent"
                    Label {
                        anchors { left: parent.left; leftMargin: Theme.space14; verticalCenter: parent.verticalCenter }
                        mono: true
                        color: sug.chosen ? Theme.textOnAccent : Theme.subtext1
                        text: "/" + sug.modelData
                    }
                    MouseArea { id: sugArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.complete(sug.modelData) }
                }
            }
        }

        // Watching: it's answered where it runs; once it's done it can go on here instead
        RowLayout {
            Layout.fillWidth: true
            visible: root.watching
            spacing: Theme.space10
            Icon {
                name: Claude.watchedState === "waiting" ? "bell" : Claude.watchedState === "working" ? "claude" : "check"
                size: 15
                color: Claude.watchedState === "waiting" ? Theme.warning : Theme.overlay1
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtext0
                font.pixelSize: Theme.fontSizeSmall
                text: Claude.watchedState === "working" ? Tr.f("Working in {0}. You can follow it here.", Claude.watchedPlace)
                    : Claude.watchedState === "waiting" ? Tr.f("Waiting for you in {0}.", Claude.watchedPlace)
                    : Tr.f("Done in {0}.", Claude.watchedPlace)
            }
            Button {
                visible: Claude.watchedState !== "working"
                icon: "claude"
                text: Tr.t("Continue here")
                onClicked: Claude.continueHere()
            }
        }

        // Like the other fields in the island; the disc sends, and while Claude works it stops it.
        PanelSurface {
            Layout.fillWidth: true
            visible: Claude.installed && !Claude.needsLogin && !root.browsing && !root.watching
            implicitHeight: Theme.controlHeight
            radius: Theme.r(height / 2)
            fill: Theme.tint(parent, Theme.crust, 0.45)
            edgeWidth: 1; edge: Theme.rimOn(parent)

            readonly property bool stopping: Claude.busy && input.text.trim() === ""
            readonly property bool ready: stopping || input.text.trim() !== ""

            TextInput {
                id: input
                anchors { left: parent.left; leftMargin: Theme.space16; right: disc.left; rightMargin: Theme.space12; verticalCenter: parent.verticalCenter }
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.textOnAccent
                font { family: Theme.fontFamily; pixelSize: Theme.fontSizeLarge }
                clip: true
                Accessible.role: Accessible.EditableText
                Accessible.name: Tr.t("Ask Claude…")
                Keys.onReturnPressed: root.submit()
                Keys.onEnterPressed: root.submit()
                Keys.onEscapePressed: Panels.claudeOpen = false
                Keys.onTabPressed: if (root.suggestions.length) root.complete(root.suggestions[root.pick])
                Keys.onDownPressed: root.pick = Math.min(root.pick + 1, root.suggestions.length - 1)
                Keys.onUpPressed: root.pick = Math.max(root.pick - 1, 0)
                onTextChanged: root.pick = 0

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !input.text
                    color: Theme.overlay0
                    font: input.font
                    text: Claude.busy ? Tr.t("Claude is working, Enter stops it") : Tr.t("Ask Claude…")
                }
            }
            Rectangle {
                id: disc
                anchors { right: parent.right; rightMargin: Theme.space6; verticalCenter: parent.verticalCenter }
                width: parent.height - 10
                height: width
                radius: width / 2
                color: parent.ready ? Theme.accent : Theme.tint(parent, Theme.text, 0.08)
                Behavior on color { ColorAnim {} }
                Icon {
                    anchors.centerIn: parent
                    name: parent.parent.stopping ? "stop" : "arrow-up"
                    size: 16
                    color: parent.parent.ready ? Theme.textOnAccent : Theme.overlay1
                }
                PressArea {
                    anchors.fill: parent
                    label: parent.parent.stopping ? Tr.t("Stop") : Tr.t("Send")
                    ringRadius: width / 2
                    onClicked: root.submit()
                }
            }
        }
    }
}
