import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    id: page
    pageId: "about"
    spacing: Theme.space10

    // What the machine is, asked once when the page opens.
    property var info: ({})
    Process {
        running: true
        command: ["sh", "-c",
            'd=/sys/class/dmi/id; v=$(cat $d/sys_vendor 2>/dev/null); n=$(cat $d/product_name 2>/dev/null); f=$(cat $d/product_version 2>/dev/null); '
            + 'case "$v" in LENOVO) n=$f; v=Lenovo ;; esac; '
            + 'echo "device=$v $n"; '
            + 'echo "cpu=$(sed -n "s/^model name[[:space:]]*: //p" /proc/cpuinfo | head -n1)"; echo "cores=$(nproc)"; '
            + 'lspci -mm 2>/dev/null | grep -E "\\"(VGA|3D|Display)" | while IFS= read -r l; do echo "gpu=$l"; done; '
            + 'echo "kernel=$(uname -r)"; '
            + 'echo "hyprland=$(hyprctl version 2>/dev/null | sed -n "1s/^Hyprland \\([^ ]*\\).*/\\1/p")"; '
            + 'echo "version=$(pacman -Q vyntaris 2>/dev/null | cut -d" " -f2 | sed "s/-[0-9]*$//")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const out = { gpus: [] };
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i < 0) continue;
                    const k = line.slice(0, i), v = line.slice(i + 1).trim();
                    if (k === "gpu") out.gpus.push(page.gpuName(v));
                    else out[k] = v;
                }
                out.device = page.deviceName(out.device ?? "");
                out.cpu = (out.cpu ?? "").replace(/\((R|TM)\)/gi, "").replace(/ (\d+-Core )?Processor$/i, "").replace(/ CPU @.*$/, "")
                    .replace(/ with Radeon Graphics$/i, "").replace(/\s+/g, " ").trim();
                page.info = out;
            }
        }
    }
    // A board's placeholder isn't a name.
    function deviceName(s) {
        const t = s.replace(/\s+/g, " ").trim();
        return /^(|to be filled.*|system product name|default string|not applicable|none|o\.e\.m\..*)$/i.test(t.replace(/^\S+ /, "")) ? "" : t;
    }
    // lspci's long names, as people say them: "NVIDIA GeForce RTX 3060 Mobile".
    function gpuName(line) {
        const f = (line.match(/"[^"]*"/g) ?? []).map(x => x.slice(1, -1));
        const vendor = f[1] ?? "", model = f[2] ?? "";
        const brand = /nvidia/i.test(vendor) ? "NVIDIA" : /amd|ati/i.test(vendor) ? "AMD" : /intel/i.test(vendor) ? "Intel" : vendor.split(" ")[0];
        const inner = (model.match(/\[([^\]]+)\]/) ?? [])[1];
        const name = (inner ?? model).split("/")[0].trim();
        return name.toLowerCase().startsWith(brand.toLowerCase()) ? name : brand + " " + name;
    }

    component Value: Label {
        color: Theme.subtext0
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideMiddle
        Layout.maximumWidth: 360
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: hero.implicitHeight + 2 * Theme.space16
        ColumnLayout {
            id: hero
            anchors.centerIn: parent
            spacing: Theme.space4
            Logo {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Theme.space10
                size: 96
                animated: logoHover.hovered && Theme.speed > 0
                HoverHandler { id: logoHover }
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Theme.fontSizeHeading
                font.weight: Font.Bold
                text: Distro.name
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: !!page.info.version
                mono: true
                color: Theme.subtext0
                font.pixelSize: Theme.fontSizeLabel
                text: Tr.f("Version {0}", page.info.version ?? "")
            }
        }
    }

    SettingsSection { text: Tr.t("Hardware") }
    SettingsRow { visible: !!page.info.device; title: Tr.t("Device"); Value { text: page.info.device ?? "" } }
    SettingsRow {
        visible: !!page.info.cpu
        title: Tr.t("Processor")
        Value { text: (page.info.cpu ?? "") + (page.info.cores ? " × " + page.info.cores : "") }
    }
    SettingsRow {
        visible: (page.info.gpus ?? []).length > 0
        title: Tr.t("Graphics")
        ColumnLayout {
            spacing: Theme.space2
            Repeater {
                model: page.info.gpus ?? []
                Value { required property string modelData; Layout.alignment: Qt.AlignRight; text: modelData }
            }
        }
    }
    SettingsRow { title: Tr.t("Memory"); Value { mono: true; text: SystemStats.formatBytes(SystemStats.memTotal, 0) } }
    SettingsRow { title: Tr.t("Disk"); Value { mono: true; text: SystemStats.formatBytes(SystemStats.diskTotal, 0) } }

    SettingsSection { text: Tr.t("Software") }
    SettingsRow { visible: !!page.info.kernel; title: Tr.t("Kernel"); Value { mono: true; text: page.info.kernel ?? "" } }
    SettingsRow { visible: !!page.info.hyprland; title: "Hyprland"; Value { mono: true; text: page.info.hyprland ?? "" } }
    SettingsRow { title: Tr.t("Settings file"); Value { mono: true; text: Config.path.replace(Quickshell.env("HOME"), "~") } }
    SettingsRow {
        title: Tr.t("Welcome screen")
        Button { text: Tr.t("Open"); onClicked: Panels.settings("welcome") }
    }
}
