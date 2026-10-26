import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: adding ? 400 : Math.max(260, (entries.length + 1) * 72 + 44)
    readonly property real hang: content.implicitHeight + 18
    readonly property bool active: Panels.keyboardOpen

    width: fullWidth
    height: Theme.barHeight + hang

    readonly property var entries: Keyboard.entries
    property bool adding: false
    readonly property var hits: Keyboard.search(search.text, 6)

    Component.onCompleted: if (active) activeChanged()
    onActiveChanged: {
        if (!active) return;
        adding = false;
        search.text = "";
        focusTimer.restart();
    }
    onAddingChanged: if (adding) search.forceActiveFocus(); else { search.text = ""; keys.forceActiveFocus(); }
    Timer { id: focusTimer; interval: 30; onTriggered: keys.forceActiveFocus() }
    Connections {
        target: root.Window.window
        function onActiveChanged() { if (root.active && root.Window.window.active && !search.activeFocus) keys.forceActiveFocus(); }
    }
    component Badge: Rectangle {
        id: badge
        property string icon
        property color fill
        signal clicked()
        width: 18; height: 18; radius: 9
        color: badgeArea.containsMouse ? fill : Theme.surface1
        border { width: 1; color: Theme.glassRim }
        Behavior on color { ColorAnim {} }
        Icon { anchors.centerIn: parent; name: badge.icon; size: 10; stroke: 2.2; color: badgeArea.containsMouse ? Theme.textOnAccent : Theme.text }
        MouseArea { id: badgeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: badge.clicked() }
    }

    function choose(i) { Keyboard.select(i); }
    function addHit(h) {
        if (!h) return;
        Keyboard.add(h.layout, h.variant);
        adding = false;
    }

    Item {
        id: keys
        anchors.fill: parent
        readonly property int count: root.entries.length
        Keys.onEscapePressed: Panels.keyboardOpen = false
        Keys.onLeftPressed: root.choose((Keyboard.index + count - 1) % count)
        Keys.onRightPressed: root.choose((Keyboard.index + 1) % count)
        Keys.onTabPressed: root.choose((Keyboard.index + 1) % count)
        Keys.onPressed: event => {
            const n = parseInt(event.text);
            if (n >= 1 && n <= count) { root.choose(n - 1); event.accepted = true; return; }
            if (event.text && /\S/.test(event.text) && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                root.adding = true;
                search.text = event.text;
                event.accepted = true;
            }
        }
    }

    PanelHeader { icon: "keyboard"; title: Tr.t("Keyboard") }

    PanelBody {
        id: content

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            Repeater {
                model: root.entries
                RoundToggle {
                    id: key
                    required property var modelData
                    required property int index
                    glyph: modelData.code
                    label: modelData.name.split(" (")[0]
                    on: Keyboard.index === index
                    onClicked: root.choose(index)

                    Badge {
                        visible: root.adding && root.entries.length > 1
                        x: parent.width / 2 + 12; y: -3
                        icon: "close"; fill: Theme.error
                        onClicked: Keyboard.remove(key.index)
                    }
                    Badge {
                        visible: root.adding && key.index > 0
                        x: parent.width / 2 - 30; y: -3
                        icon: "arrow-up"; fill: Theme.accent
                        onClicked: Keyboard.makeDefault(key.index)
                    }
                }
            }

            RoundToggle {
                icon: root.adding ? "check" : "plus"
                label: root.adding ? Tr.t("Done") : Tr.t("Add")
                on: root.adding
                onClicked: root.adding = !root.adding
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.adding
            spacing: 8

            PanelSurface {
                Layout.fillWidth: true
                implicitHeight: 34
                radius: Theme.r(10)
                fill: Theme.alpha(Theme.crust, 0.45)
                edgeWidth: 1; edge: search.activeFocus ? Theme.accent : Theme.glassRim
                Behavior on edge { ColorAnim {} }
                MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: search.forceActiveFocus() }
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 8
                    Icon { name: "search"; size: 13; color: search.activeFocus ? Theme.accent : Theme.overlay1 }
                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.textOnAccent
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSize }
                        clip: true
                        Keys.onEscapePressed: root.adding = false
                        Keys.onReturnPressed: root.addHit(root.hits[0])
                        Keys.onEnterPressed: root.addHit(root.hits[0])
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !search.text
                            color: Theme.overlay0
                            text: Tr.t("Language")
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                visible: root.hits.length > 0
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                    model: root.hits
                    PanelSurface {
                        id: hit
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 42
                        radius: Theme.r(12)
                        fill: hitArea.containsMouse || index === 0 ? Theme.alpha(Theme.accent, 0.12) : Theme.alpha(Theme.text, 0.05)
                        edgeWidth: 1; edge: index === 0 ? Theme.alpha(Theme.accent, 0.45) : Theme.glassRim
                        Behavior on fill { ColorAnim {} }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                            spacing: 10
                            Label { mono: true; font.weight: Font.DemiBold; color: Theme.accent; text: hit.modelData.layout.toUpperCase() }
                            Label { Layout.fillWidth: true; elide: Text.ElideRight; text: hit.modelData.name }
                            Icon { name: "plus"; size: 13; color: hitArea.containsMouse ? Theme.accent : Theme.overlay1 }
                        }
                        MouseArea { id: hitArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.addHit(hit.modelData) }
                    }
                }
            }
        }
    }
}
