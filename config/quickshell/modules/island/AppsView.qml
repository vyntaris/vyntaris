import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import "../../components/Slant.js" as Slant
import qs.services
import "Search.js" as Search

Item {
    id: root
    readonly property int gap: 16
    function out(y) { return Theme.slanted ? Slant.out(height, Theme.barHeight, y) : 0; }
    readonly property int columns: 6
    readonly property int rows: 4
    readonly property real cell: 100
    readonly property real fullWidth: columns * cell + 2 * gap
    readonly property real hang: gap + field.height + gap + chips.height + gap + grid.height + gap + hints.height + gap
    readonly property bool active: Panels.appsOpen

    width: fullWidth
    height: Theme.barHeight + hang

    readonly property var allApps: DesktopEntries.applications.values.filter(a => Search.listed(a))
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property var categories: {
        const order = ["Internet", "Development", "Media", "Graphics", "Office", "Games", "Utility", "System"];
        const present = new Set(allApps.map(a => Search.category(a)));
        return ["All"].concat(order.filter(c => present.has(c)));
    }
    property int categoryIndex: 0
    readonly property string category: categories[categoryIndex] ?? "All"
    function categoryName(c) {
        return ({ All: Tr.t("All"), Internet: Tr.t("Internet"), Development: Tr.t("Development"), Media: Tr.t("Media"),
                  Graphics: Tr.t("Graphics"), Office: Tr.t("Office"), Games: Tr.t("Games"), Utility: Tr.t("Utility"),
                  System: Tr.t("System") })[c] ?? c;
    }
    readonly property var apps: {
        const q = search.text.trim().toLowerCase();
        return allApps.filter(a => (category === "All" || Search.category(a) === category)
            && (!q || a.name.toLowerCase().includes(q) || (a.genericName ?? "").toLowerCase().includes(q)
                || (a.keywords ?? []).some(k => k.toLowerCase().includes(q))));
    }
    function cycle(step) {
        categoryIndex = (categoryIndex + step + categories.length) % categories.length;
        grid.currentIndex = 0;
    }

    property bool entering: false
    Timer { id: enterTimer; interval: Theme.durationSlow + 400; onTriggered: root.entering = false }
    onActiveChanged: if (active) {
        search.text = "";
        categoryIndex = 0;
        grid.currentIndex = 0;
        grid.positionViewAtBeginning();
        entering = true;
        enterTimer.restart();
        focusLater.restart();
    }
    Component.onCompleted: if (active) activeChanged()
    Timer { id: focusLater; interval: 30; onTriggered: search.forceActiveFocus() }

    function start(app) {
        if (!app) return;
        if (app.runInTerminal) Config.runInTerminal(app.command.join(" "));
        else if (!Games.launch(app)) Config.openEntry(app);
        Panels.appsOpen = false;
    }

    PanelHeader {
        inset: root.gap
        icon: "apps"
        title: Tr.t("Apps")
    }

    PanelSurface {
        id: field
        x: root.gap - root.out(y + height)
        y: Theme.barHeight + root.gap
        width: parent.width - 2 * root.gap + 2 * root.out(y + height)
        height: 38
        radius: Theme.r(height / 2)
        fill: Theme.alpha(Theme.crust, 0.45)
        edgeWidth: 1; edge: Theme.glassRim

        Rectangle {
            id: disc
            anchors { left: parent.left; leftMargin: 5; verticalCenter: parent.verticalCenter }
            width: parent.height - 10
            height: width
            radius: width / 2
            color: Theme.accent
        }
        Icon {
            id: prompt
            anchors.centerIn: disc
            name: "search"
            size: 16
            color: Theme.textOnAccent
        }
        Rectangle {
            id: fieldCount
            anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
            width: Math.max(disc.width, countText.implicitWidth + 16)
            height: disc.height
            radius: Theme.r(height / 2)
            color: Theme.accent
            Label {
                id: countText
                anchors.centerIn: parent
                mono: true
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.textOnAccent
                text: root.apps.length
            }
        }
        TextInput {
            id: search
            anchors { left: disc.right; leftMargin: 12; right: fieldCount.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: Theme.textOnAccent
            font { family: Theme.fontFamily; pixelSize: Theme.fontSize + 2 }
            clip: true
            onTextChanged: grid.currentIndex = 0
            Keys.onEscapePressed: Panels.appsOpen = false
            Keys.onTabPressed: root.cycle(1)
            Keys.onBacktabPressed: root.cycle(-1)
            Keys.onDownPressed: grid.moveCurrentIndexDown()
            Keys.onUpPressed: grid.moveCurrentIndexUp()
            Keys.onRightPressed: grid.moveCurrentIndexRight()
            Keys.onLeftPressed: grid.moveCurrentIndexLeft()
            Keys.onReturnPressed: root.start(root.apps[grid.currentIndex])
            Keys.onEnterPressed: root.start(root.apps[grid.currentIndex])

            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: !search.text
                text: Tr.t("Search apps…")
                color: Theme.overlay0
            }
        }
    }

    Item {
        id: chips
        anchors { top: field.bottom; topMargin: root.gap; left: parent.left; leftMargin: root.gap + 5 - root.out(y + height) }
        width: parent.width - 2 * (root.gap + 5) + 2 * root.out(y + height)
        height: 28

        Rectangle {
            readonly property Item target: chipRow.children[root.categoryIndex] ?? null
            x: target?.x ?? 0
            width: target?.width ?? 0
            height: parent.height
            radius: Theme.r(height / 2)
            color: Theme.accent
            Behavior on x { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }
            Behavior on width { Anim { duration: Theme.durationNormal } }
        }
        Row {
            id: chipRow
            height: parent.height
            width: parent.width
            spacing: {
                let words = 0, n = 0;
                for (const c of children) if (c.isChip) { words += c.width; n++; }
                return n > 1 ? Math.max(0, (width - words) / (n - 1)) : 0;
            }
            Repeater {
                model: root.categories
                Item {
                    required property string modelData
                    required property int index
                    readonly property bool current: root.categoryIndex === index
                    readonly property bool isChip: true
                    width: chipText.implicitWidth + 24
                    height: chipRow.height
                    Label {
                        id: chipText
                        anchors.centerIn: parent
                        caps: true
                        font.weight: current ? Font.DemiBold : Font.Normal
                        text: root.categoryName(modelData)
                        color: current ? Theme.textOnAccent : chipArea.containsMouse ? Theme.subtext0 : Theme.overlay1
                    }
                    MouseArea {
                        id: chipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.categoryIndex = index; grid.currentIndex = 0; }
                    }
                }
            }
        }
    }

    Item {
        id: gridClip
        readonly property real widest: root.out(y)
        anchors { top: chips.bottom; topMargin: root.gap; left: parent.left; leftMargin: root.gap - widest }
        width: root.columns * root.cell + 2 * widest
        height: grid.height
        clip: true

        GridView {
            id: grid
            x: gridClip.widest
            width: root.columns * root.cell
            height: root.rows * root.cell
            cellWidth: root.cell
            cellHeight: root.cell
            function spread(tile) {
                if (!Theme.slanted || !tile) return 0;
                const half = (root.columns - 1) / 2, col = tile.index % root.columns;
                return (col - half) / half * root.out(gridClip.y + tile.y - contentY + root.cell);
            }
            model: root.apps
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationWraps: true
            highlightMoveDuration: 0

            delegate: Item {
                id: tile
                required property var modelData
                required property int index
                readonly property bool picked: GridView.isCurrentItem
                width: root.cell
                height: root.cell

                Component.onCompleted: if (root.entering && index < root.columns * root.rows) { surface.opacity = 0; surface.y = 14; intro.start(); }
                SequentialAnimation {
                    id: intro
                    PauseAnimation { duration: Theme.duration(120 + tile.index * 18) }
                    ParallelAnimation {
                        Anim { target: surface; property: "opacity"; to: 1 }
                        Anim { target: surface; property: "y"; to: 4; easing.bezierCurve: Theme.curveDecelerate }
                    }
                }

                PanelSurface {
                    id: surface
                    x: 4 + grid.spread(tile); y: 4
                    width: parent.width - 8
                    height: parent.height - 8
                    radius: Theme.r(12)
                    fill: tile.picked ? Theme.accent : "transparent"
                    scale: area.pressed ? 0.96 : 1
                    Behavior on fill { ColorAnim {} }
                    Behavior on scale { Anim { duration: Theme.durationFast; easing.bezierCurve: Theme.curveSpring } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        spacing: 8
                        AppIcon {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: 40
                            source: Quickshell.iconPath(tile.modelData.icon, true) || Quickshell.iconPath("application-x-executable", true)
                        }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            font.pixelSize: Theme.fontSizeSmall + 1
                            color: tile.picked ? Theme.textOnAccent : Theme.subtext1
                            text: tile.modelData.name
                        }
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: grid.currentIndex = tile.index
                    onClicked: root.start(tile.modelData)
                }
            }

            Label {
                anchors.centerIn: parent
                visible: grid.count === 0
                caps: true
                text: Tr.t("No apps found")
            }
        }
    }

    KeyHints {
        id: hints
        anchors { horizontalCenter: parent.horizontalCenter; top: gridClip.bottom; topMargin: root.gap }
        keys: [["↑ ↓ ← →", Tr.t("select")], ["⇥", Tr.t("category")], ["↵", Tr.t("open")], ["esc", Tr.t("close")]]
    }
}
