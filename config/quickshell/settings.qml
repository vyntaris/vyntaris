//@ pragma ShellId vyntaris-settings
import QtQuick
import qs.config
import qs.modules.apps
import qs.modules.settings
import qs.services

AppRoot {
    name: "settings"
    flag: "settings"
    windowTitle: Tr.t("Settings")
    onCalled: (call, arg) => {
        if (call === "page") Panels.settings(arg);
        else if (call === "search") Panels.settingsSearch(arg);
        else if (call === "row") Panels.settingsRow(arg.split("\t")[0], arg.split("\t")[1] ?? "");
    }

    Settings {}
}
