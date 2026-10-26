//@ pragma ShellId vyntaris-help
import QtQuick
import qs.config
import qs.modules.apps
import qs.modules.settings

AppRoot {
    name: "help"
    flag: "help"
    windowTitle: Tr.t("Help")

    Help {}
}
