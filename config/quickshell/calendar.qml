//@ pragma ShellId vyntaris-calendar
import QtQuick
import qs.config
import qs.modules.apps

AppRoot {
    id: app
    name: "calendar"
    flag: "calendar"
    windowTitle: Tr.t("Calendar")

    CalendarApp { id: cal }
    // "open 2026-11-12": that day's week.
    onCalled: (call, arg) => { if (/^\d{4}-\d{2}-\d{2}$/.test(arg)) cal.show(arg); }
}
