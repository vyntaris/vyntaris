import QtQuick
import QtQuick.Layouts
import QtMultimedia
import qs.config
import qs.components

Item {
    id: root
    property string path

    MediaPlayer {
        id: player
        source: root.path ? "file://" + root.path : ""
        videoOutput: video
        audioOutput: AudioOutput {}
        onSourceChanged: play()
    }
    VideoOutput {
        id: video
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: bar.top; bottomMargin: 10 }
        MouseArea { anchors.fill: parent; onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
    }
    Icon {
        anchors.centerIn: video
        visible: !player.hasVideo
        name: "music"
        size: 96
        color: Theme.accent
    }
    RowLayout {
        id: bar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 12
        IconButton {
            icon: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
            onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
        }
        Meter {
            Layout.fillWidth: true
            implicitHeight: 6
            value: player.duration > 0 ? player.position / player.duration : 0
            MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: mouse => player.position = mouse.x / width * player.duration }
        }
        Label {
            mono: true
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.overlay1
            function t(ms) { const s = Math.floor(ms / 1000); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
            text: t(player.position) + " / " + t(player.duration)
        }
    }
}
