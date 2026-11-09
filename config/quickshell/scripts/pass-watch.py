#!/usr/bin/env python3
# Tells the shell when any app's password field gets the focus: one JSON line each time, with the site
# (a browser's page) or the app, and whether a username field comes right before it.
import json
import sys
import warnings
from urllib.parse import urlparse

import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, Gio, GLib  # noqa: E402

warnings.simplefilter("ignore", DeprecationWarning)
SKIP = {"quickshell", "qs", "kitty", "pinentry", "gcr-prompter"}


def turn_on():
    # Apps only describe their fields while someone listens; from the next start of each app.
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION)
        bus.call_sync("org.a11y.Bus", "/org/a11y/bus", "org.freedesktop.DBus.Properties", "Set",
                      GLib.Variant("(ssv)", ("org.a11y.Status", "IsEnabled", GLib.Variant("b", True))),
                      None, Gio.DBusCallFlags.NONE, 2000, None)
    except GLib.Error as e:
        print(json.dumps({"error": e.message}), flush=True)


def ancestor(acc, roles, depth=40):
    for _ in range(depth):
        acc = acc.get_parent() if acc else None
        if acc is None:
            return None
        if acc.get_role() in roles:
            return acc
    return None


def site(acc):
    doc = ancestor(acc, {Atspi.Role.DOCUMENT_WEB})
    if not doc:
        return ""
    try:
        url = (doc.get_document_iface().get_document_attributes() or {}).get("DocURL", "")
    except (GLib.Error, AttributeError):
        url = ""
    host = urlparse(url).hostname or ""
    return host[4:] if host.startswith("www.") else host


def fields(root, limit=400):
    out, todo = [], [root]
    while todo and limit:
        a = todo.pop()
        limit -= 1
        try:
            role = a.get_role()
            if role in (Atspi.Role.ENTRY, Atspi.Role.PASSWORD_TEXT):
                out.append(a)
            n = a.get_child_count()
            todo.extend(a.get_child_at_index(i) for i in range(n - 1, -1, -1))
        except GLib.Error:
            pass
    return out


def length(acc):
    try:
        return acc.get_text_iface().get_character_count() if acc.get_text_iface() else 0
    except GLib.Error:
        return 0


last = [None, 0]


def focused(ev):
    if not ev.detail1:
        return
    acc = ev.source
    # Firefox says it twice.
    now = GLib.get_monotonic_time()
    if last[0] == acc and now - last[1] < 1_000_000:
        return
    last[:] = [acc, now]
    try:
        if acc.get_role() != Atspi.Role.PASSWORD_TEXT:
            return
        app = (acc.get_application().get_name() or "").lower()
        if app in SKIP:
            return
        host = site(acc)
        user, user_empty = False, False
        box = ancestor(acc, {Atspi.Role.FORM}) or ancestor(acc, {Atspi.Role.DOCUMENT_WEB, Atspi.Role.FRAME, Atspi.Role.DIALOG})
        if box:
            row = fields(box)
            at = next((i for i, f in enumerate(row) if f == acc), -1)
            if at > 0 and row[at - 1].get_role() == Atspi.Role.ENTRY:
                user, user_empty = True, length(row[at - 1]) == 0
        print(json.dumps({"app": app, "site": host, "user": user, "userEmpty": user_empty,
                          "empty": length(acc) == 0}), flush=True)
    except GLib.Error:
        pass


turn_on()
listener = Atspi.EventListener.new(focused)
listener.register("object:state-changed:focused")
try:
    Atspi.event_main()
except KeyboardInterrupt:
    sys.exit(0)
