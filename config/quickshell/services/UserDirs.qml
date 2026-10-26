pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property string download: home + "/Downloads"
    property string pictures: home + "/Pictures"
    property string videos: home + "/Videos"

    Process {
        running: true
        command: ["sh", "-c", "xdg-user-dir DOWNLOAD; xdg-user-dir PICTURES; xdg-user-dir VIDEOS"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = text.split("\n").map(s => s.trim());
                const pick = (v, fallback) => v && v !== root.home ? v : fallback;
                root.download = pick(d[0], root.download);
                root.pictures = pick(d[1], root.pictures);
                root.videos = pick(d[2], root.videos);
            }
        }
    }
}
