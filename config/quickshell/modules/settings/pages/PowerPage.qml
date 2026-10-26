import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    pageId: "power"

    SettingsRow { title: Tr.t("Dim"); SecondsSlider { value: Config.idle.dimAfter; onEdited: v => { Config.idle.dimAfter = v; Config.saveSoon(); } } }
    SettingsRow { title: Tr.t("Lock"); SecondsSlider { value: Config.idle.lockAfter; onEdited: v => { Config.idle.lockAfter = v; Config.saveSoon(); } } }
    SettingsRow { title: Tr.t("Screen off"); SecondsSlider { value: Config.idle.screenOffAfter; onEdited: v => { Config.idle.screenOffAfter = v; Config.saveSoon(); } } }
    SettingsRow { title: Tr.t("Suspend"); SecondsSlider { value: Config.idle.suspendAfter; onEdited: v => { Config.idle.suspendAfter = v; Config.saveSoon(); } } }
    SettingsRow {
        title: Tr.t("Lid")
        Choice {
            options: [{ value: "suspend", label: Tr.t("Suspend") }, { value: "lock", label: Tr.t("Lock") }, { value: "nothing", label: Tr.t("Nothing") }]
            current: Config.power.lidAction
            onPicked: v => { Config.power.lidAction = v; Config.saveSoon(); }
        }
    }
    SettingsRow {
        visible: Battery.available
        title: Tr.t("Low battery")
        Choice {
            options: [{ value: 10, label: "10%" }, { value: 15, label: "15%" }, { value: 20, label: "20%" }]
            current: Config.battery.low
            onPicked: v => { Config.battery.low = v; Config.saveSoon(); }
        }
    }
    SettingsRow {
        visible: Battery.available
        title: Tr.t("Critical battery")
        Choice {
            options: [{ value: 3, label: "3%" }, { value: 5, label: "5%" }, { value: 8, label: "8%" }]
            current: Config.battery.critical
            onPicked: v => { Config.battery.critical = v; Config.saveSoon(); }
        }
    }
    SettingsRow {
        visible: Battery.available
        title: Tr.t("Saver on low battery")
        Switch { checked: Config.battery.autoPowerSaver; onToggled: on => { Config.battery.autoPowerSaver = on; Config.saveSoon(); } }
    }
    SettingsRow {
        visible: Battery.available && Power.hasPerformance
        title: Tr.t("Performance when plugged in")
        Switch { checked: Config.battery.performanceOnAC; onToggled: on => { Config.battery.performanceOnAC = on; Config.saveSoon(); } }
    }
    SettingsRow {
        title: Tr.t("Hibernation")
        Switch {
            checked: Sleep.canHibernate
            onToggled: Config.runInTerminal(`vyntaris-hibernate${Sleep.canHibernate ? " off" : ""}; ${Config.enterToClose()}`)
        }
    }
    SettingsRow {
        title: Tr.t("Power mode")
        Choice {
            options: Power.order.map(p => ({ value: p, label: Power.name(p) }))
            current: Power.profile
            onPicked: v => Power.set(v)
        }
    }
    SettingsRow {
        title: Tr.t("Responsive under load")
        Switch {
            checked: Sleep.lavd
            onToggled: Config.runInTerminal(`vyntaris-scheduler ${Sleep.lavd ? "off" : "on"}; ${Config.enterToClose()}`)
        }
    }
}
