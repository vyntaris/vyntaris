import Quickshell.Widgets
import Qt.labs.folderlistmodel
import QtQuick
import qs.config
import qs.components
import qs.services
import "../../config/Wallpapers.js" as Walls

Item {
    id: root
    readonly property real fullWidth: 820
    readonly property real hang: 208
    readonly property bool active: Panels.wallpaperOpen

    readonly property string directory: Config.expandHome(Config.wallpaper.directory)
    readonly property string current: Config.wallpaperPath

    width: fullWidth
    height: Theme.barHeight + hang

    property var entries: []
    function rebuild() {
        const paths = [];
        for (let k = 0; k < files.count; k++) paths.push(files.get(k, "filePath"));
        entries = [{ path: Config.defaultWallpaper, title: "Floating Cubes" }]
            .concat(Walls.group(paths, Theme.isDark).map(e => ({ path: e.path, title: e.title })));
        showCurrent();
    }
    Component.onCompleted: { rebuild(); if (active) activeChanged(); }
    readonly property bool dark: Theme.isDark
    onDarkChanged: rebuild()

    FolderListModel {
        id: files
        folder: root.directory ? "file://" + root.directory : ""
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg", "*.heic", "*.heif", "*.PNG", "*.JPG", "*.JPEG", "*.HEIC", "*.HEIF"]
        showDirs: false
        sortField: FolderListModel.Name
        onStatusChanged: if (status === FolderListModel.Ready) root.rebuild()
    }

    function apply(i) {
        const e = entries[i];
        if (!e) return;
        Config.wallpaper.path = e.path;
        Config.save();
    }

    function inUse(e) {
        return Walls.same(e.path, current);
    }
    function showCurrent() {
        let i = 0;
        for (let k = 0; k < entries.length; k++)
            if (inUse(entries[k])) { i = k; break; }
        carousel.positionViewAtIndex(i, PathView.Center);
        carousel.currentIndex = i;
    }
    onActiveChanged: {
        if (!active) return;
        showCurrent();
        if (root.directory) {
            files.folder = "";
            files.folder = Qt.binding(() => root.directory ? "file://" + root.directory : "");
        }
        focusTimer.restart();
    }
    Timer { id: focusTimer; interval: 30; onTriggered: carousel.forceActiveFocus() }
    Connections {
        target: root.Window.window
        function onActiveChanged() { if (root.active && root.Window.window.active) carousel.forceActiveFocus(); }
    }

    PanelHeader {
        icon: "image"
        title: Tr.t("Wallpapers")
        Label {
            mono: true
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.overlay0
            text: carousel.count > 0 ? `${carousel.currentIndex + 1} / ${carousel.count}` : ""
        }
    }

    PathView {
        id: carousel
        readonly property real step: 270
        y: Theme.barHeight + 4
        width: parent.width
        height: 180
        clip: true
        model: root.entries
        focus: true
        pathItemCount: Math.min(3, count)
        preferredHighlightBegin: 0.5
        preferredHighlightEnd: 0.5
        highlightRangeMode: PathView.StrictlyEnforceRange
        highlightMoveDuration: Theme.durationNormal
        snapMode: PathView.SnapToItem
        interactive: count > 1

        path: Path {
            startX: carousel.width / 2 - carousel.step * 1.5
            startY: carousel.height / 2
            PathLine { x: carousel.width / 2 + carousel.step * 1.5; y: carousel.height / 2 }
        }

        Keys.onEscapePressed: Panels.wallpaperOpen = false
        Keys.onLeftPressed: decrementCurrentIndex()
        Keys.onRightPressed: incrementCurrentIndex()
        Keys.onReturnPressed: { root.apply(currentIndex); Panels.wallpaperOpen = false; }
        Keys.onEnterPressed: { root.apply(currentIndex); Panels.wallpaperOpen = false; }

        WheelHandler {
            onWheel: event => {
                if ((event.angleDelta.y || event.angleDelta.x) > 0) carousel.decrementCurrentIndex();
                else carousel.incrementCurrentIndex();
            }
        }

        delegate: Item {
            id: card
            required property int index
            required property var modelData
            readonly property bool selected: PathView.isCurrentItem
            readonly property bool inUse: root.inUse(modelData)

            width: 240
            height: carousel.height

            ClippingRectangle {
                id: thumb
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -8
                width: card.width
                height: Math.round(card.width * 9 / 16)
                radius: Theme.r(14)
                color: Theme.surface0
                scale: card.selected ? 1.08 : 0.86
                opacity: card.selected ? 1 : 0.55
                Behavior on scale { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }
                Behavior on opacity { Anim {} }

                Image {
                    anchors.fill: parent
                    source: card.modelData.path ? "file://" + Config.wallpaperFileOf(card.modelData.path) : ""
                    sourceSize: Qt.size(480, 270)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }

                Rectangle {
                    visible: card.inUse
                    anchors { right: parent.right; top: parent.top; margins: 8 }
                    width: 22; height: 22; radius: 11
                    color: Theme.accent
                    Icon { anchors.centerIn: parent; name: "check"; size: 14; stroke: 2.2; color: Theme.textOnAccent }
                }
            }

            Rectangle {
                anchors.centerIn: thumb
                width: thumb.width * thumb.scale + 6
                height: thumb.height * thumb.scale + 6
                radius: Theme.r(17)
                color: "transparent"
                border { width: 2; color: card.selected ? Theme.accent : "transparent" }
                Behavior on border.color { ColorAnim {} }
            }

            Label {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                color: card.selected ? Theme.text : Theme.overlay0
                text: card.modelData.title
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    carousel.currentIndex = card.index;
                    root.apply(card.index);
                }
            }
        }
    }

}
