import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import "../../components/Slant.js" as Slant
import qs.services

Item {
    id: root
    readonly property real fullWidth: 640
    readonly property real hang: 268
    function out(y) { return Theme.slanted ? Slant.out(height, Theme.barHeight, y) : 0; }
    readonly property var pk: Activities.packages

    width: fullWidth
    height: Theme.barHeight + hang

    PanelHeader {
        icon: "package-update"
        tint: root.pk?.state === "failed" ? Theme.red : Theme.accent
        title: !root.pk ? Tr.t("Packages")
            : Activities.removing ? Tr.t("Removing · ") + root.pk.count
            : Activities.installing ? (root.pk.count > 0 ? Tr.t("Installing · ") + root.pk.count : Tr.t("Installing"))
            : root.pk.state === "failed" ? Tr.t("Installation failed")
            : root.pk.state === "done" && root.pk.count > 0 && root.pk.removed === root.pk.count
                ? (root.pk.count === 1 ? Tr.t("1 package removed") : root.pk.count + Tr.t(" packages removed"))
            : root.pk.state === "done" ? (root.pk.count === 1 ? Tr.t("1 package installed") : root.pk.count + Tr.t(" packages installed"))
            : Tr.t("Nothing changed")
        Label {
            visible: Activities.installing && (root.pk?.name ?? "") !== ""
            color: Theme.overlay1
            font.family: Theme.monoFamily
            text: root.pk?.name ?? ""
        }
    }

    PanelSurface {
        x: Theme.panelInset - root.out(y + height)
        y: Theme.panelTop
        width: parent.width - 2 * Theme.panelInset + 2 * root.out(y + height)
        height: root.hang - 18
        radius: Theme.r(Theme.radius)
        fill: Theme.alpha(Theme.crust, 0.7)
        edgeWidth: 1; edge: Theme.hairline

        ListView {
            id: log
            anchors { fill: parent; margins: 10 }
            clip: true
            model: ListModel { id: shown }
            readonly property var lines: root.pk?.lines ?? []
            onLinesChanged: {
                for (let i = 0; i < lines.length; i++) {
                    if (i >= shown.count) shown.append({ line: lines[i] });
                    else if (shown.get(i).line !== lines[i]) shown.setProperty(i, "line", lines[i]);
                }
                if (shown.count > lines.length) shown.remove(lines.length, shown.count - lines.length);
                if (following) Qt.callLater(positionViewAtEnd);
            }
            property bool following: true
            onMovementEnded: following = atYEnd
            Component.onCompleted: { linesChanged(); positionViewAtEnd(); }
            delegate: Text {
                required property string line
                readonly property string modelData: line
                width: ListView.view.width
                wrapMode: root.pk?.source === "log" ? Text.WrapAnywhere : Text.NoWrap
                elide: root.pk?.source === "log" ? Text.ElideNone : Text.ElideRight
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontSizeSmall - 1
                text: modelData
                color: root.pk?.source !== "log" ? (/error|failed/i.test(modelData) ? Theme.red : /^::/.test(modelData) ? Theme.accent : Theme.text)
                    : /\[ALPM\] transaction (failed|interrupted)|error|failed/i.test(modelData) ? Theme.red
                    : /\[ALPM\] (installed|upgraded|reinstalled|downgraded) /.test(modelData) ? Theme.green
                    : /\[ALPM\] removed /.test(modelData) ? Theme.peach
                    : /^\[PACMAN\] Running /.test(modelData) ? Theme.accent
                    : Theme.subtext0
            }
        }
        Caption {
            anchors.centerIn: parent
            visible: log.count === 0
            text: Activities.installing ? Tr.t("Starting…") : Tr.t("No install since the shell started")
        }
    }
}
