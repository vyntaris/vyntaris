pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property var drives: []

    function refresh() { list.running = true; }
    function open(d) { if (d.mount) Config.launch(["xdg-open", d.mount]); }
    function eject(d) {
        Quickshell.execDetached(["sh", "-c",
            'udisksctl unmount -b "$1" --no-user-interaction && { udisksctl power-off -b "$2" --no-user-interaction 2>/dev/null; notify-send -a Devices -i drive-removable-media "$4" "$3"; } || notify-send -a Devices -u critical -i dialog-warning "$5" "$3 · $6"',
            "sh", d.path, d.parent, d.label, Tr.t("Safe to remove"), Tr.t("Cannot eject"), Tr.t("still in use")]);
        later.restart();
    }
    Timer { id: later; interval: 1200; onTriggered: root.refresh() }

    Process {
        id: list
        command: ["lsblk", "-J", "-p", "-o", "PATH,PKNAME,LABEL,SIZE,MOUNTPOINT,FSTYPE,TRAN,HOTPLUG,RM,MODEL"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const out = [];
                    const walk = (devs, parent) => {
                        for (const d of devs ?? []) {
                            const usb = d.tran === "usb" || parent?.tran === "usb" || d.hotplug || d.rm || parent?.hotplug;
                            if (d.fstype && usb && d.fstype !== "swap")
                                out.push({ path: d.path, parent: d.pkname || parent?.path || d.path,
                                           label: d.label || parent?.model?.trim() || d.path.split("/").pop(),
                                           size: d.size, mount: d.mountpoint || "" });
                            walk(d.children, d);
                        }
                    };
                    walk(JSON.parse(text).blockdevices, null);
                    root.drives = out;
                } catch (e) {}
            }
        }
    }

    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block", "--subsystem-match=usb", "--property"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: block => root.event(block)
        }
    }

    function event(block) {
        const p = {};
        for (const line of block.split("\n")) {
            const i = line.indexOf("=");
            if (i > 0) p[line.slice(0, i)] = line.slice(i + 1);
        }
        if (p.SUBSYSTEM === "block" && p.ID_FS_USAGE === "filesystem" && (p.ID_BUS === "usb" || p.ID_USB_DRIVER)) {
            const label = p.ID_FS_LABEL || p.ID_MODEL || p.DEVNAME;
            if (p.ACTION === "add") arrive(p.DEVNAME, label.replace(/_/g, " "), p.ID_PATH ? p.DEVNAME.replace(/\d+$/, "") : p.DEVNAME);
            else if (p.ACTION === "remove") {
                Quickshell.execDetached(["notify-send", "-a", Tr.t("Devices"), "-i", "drive-removable-media", Tr.t("Removed"), label.replace(/_/g, " ")]);
                later.restart();
            }
        } else if (p.SUBSYSTEM === "usb" && p.DEVTYPE === "usb_device" && p.ACTION === "add" && (p.ID_MTP_DEVICE === "1" || p.ID_MEDIA_PLAYER)) {
            const name = (p.ID_MODEL_FROM_DATABASE || p.ID_MODEL || Tr.t("Phone")).replace(/_/g, " ");
            Quickshell.execDetached(["sh", "-c",
                'a=$(notify-send -a Devices -i phone -A "open=$2" "$3" "$1 · $4") && [ "$a" = open ] && xdg-open mtp://',
                "sh", name, Tr.t("Open"), Tr.t("Phone connected"), Tr.t("unlock it and allow file access")]);
        }
    }

    function arrive(dev, label, parent) {
        Quickshell.execDetached(["sh", "-c",
            'mp=$(udisksctl mount -b "$1" --no-user-interaction 2>/dev/null | sed -n "s/.* at //p" | sed "s/\\.$//"); ' +
            '[ -n "$mp" ] || mp=$(findmnt -no TARGET "$1"); ' +
            'a=$(notify-send -a Devices -i drive-removable-media -A "open=$4" -A "eject=$5" "$6" "$2"); ' +
            'case "$a" in open) xdg-open "$mp" ;; eject) udisksctl unmount -b "$1" --no-user-interaction && udisksctl power-off -b "$3" --no-user-interaction 2>/dev/null && notify-send -a Devices -i drive-removable-media "$7" "$2" ;; esac',
            "sh", dev, label, parent, Tr.t("Open"), Tr.t("Eject"), Tr.t("USB drive connected"), Tr.t("Safe to remove")]);
        later.restart();
    }

    Component.onCompleted: refresh()
}
