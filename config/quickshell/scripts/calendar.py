#!/usr/bin/env python3
# The calendar's events, kept in ~/.local/share/vyntaris/calendar/events.json; with a Google account added in Online
# Accounts (GNOME's, which signs in for us), Google Calendar's too, both ways.
#   status                 {"google": "name@gmail.com" or null}
#   list                   every event kept, as JSON
#   sync                   Google's events from a month ago to a year ahead, and what was added here offline
#   add                    {"title", "start", "end", "allDay", "remind"} on stdin (local times, ISO); prints the event
#   update ID              the event's new fields on stdin, like add
#   delete ID
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

DIR = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "vyntaris", "calendar")
FILE = os.path.join(DIR, "events.json")
API = "https://www.googleapis.com/calendar/v3"


def load():
    try:
        return json.load(open(FILE))
    except (OSError, ValueError):
        return {"events": [], "pending": []}


def store(data):
    os.makedirs(DIR, exist_ok=True)
    with open(FILE + ".new", "w") as f:
        json.dump(data, f)
    os.replace(FILE + ".new", FILE)


def google():
    """The Google account with its calendar on, and a fresh token for it: (email, token), or (None, None)."""
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        bus = Gio.bus_get_sync(Gio.BusType.SESSION)
        objects = bus.call_sync("org.gnome.OnlineAccounts", "/org/gnome/OnlineAccounts",
                                "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None, None,
                                Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
        for path, ifaces in objects.items():
            acc = ifaces.get("org.gnome.OnlineAccounts.Account")
            if not acc or acc.get("ProviderType") != "google" or acc.get("CalendarDisabled", True):
                continue
            if "org.gnome.OnlineAccounts.OAuth2Based" not in ifaces:
                continue
            token = bus.call_sync("org.gnome.OnlineAccounts", path, "org.gnome.OnlineAccounts.OAuth2Based",
                                  "GetAccessToken", None, None, Gio.DBusCallFlags.NONE, 15000, None).unpack()[0]
            return acc.get("PresentationIdentity") or acc.get("Identity"), token
    except Exception:
        pass
    return None, None


def call(token, method, path, body=None, query=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        out = r.read()
    return json.loads(out) if out else {}


def local(dt):
    """An aware time as this computer's local time, ISO, no zone: what the shell shows."""
    return dt.astimezone().replace(tzinfo=None).isoformat(timespec="minutes")


def from_google(e, cal, defaults):
    s, en = e.get("start", {}), e.get("end", {})
    all_day = "date" in s
    if all_day:
        start, end = s["date"] + "T00:00", en.get("date", s["date"]) + "T00:00"
    else:
        start = local(datetime.fromisoformat(s["dateTime"].replace("Z", "+00:00")))
        end = local(datetime.fromisoformat(en.get("dateTime", s["dateTime"]).replace("Z", "+00:00")))
    r = e.get("reminders", {})
    popups = [o["minutes"] for o in r.get("overrides", []) if o.get("method") == "popup"]
    if r.get("useDefault", True):
        popups = defaults
    return {"id": e["id"], "calendar": cal, "title": e.get("summary") or "(no title)", "start": start, "end": end,
            "allDay": all_day, "remind": min(popups) if popups else -1, "google": True}


def to_google(ev):
    if ev["allDay"]:
        start, end = {"date": ev["start"][:10]}, {"date": ev["end"][:10]}
    else:
        zone = datetime.now().astimezone().tzinfo
        start = {"dateTime": datetime.fromisoformat(ev["start"]).replace(tzinfo=zone).isoformat()}
        end = {"dateTime": datetime.fromisoformat(ev["end"]).replace(tzinfo=zone).isoformat()}
    reminders = {"useDefault": False, "overrides": [{"method": "popup", "minutes": ev["remind"]}] if ev["remind"] >= 0 else []}
    return {"summary": ev["title"], "start": start, "end": end, "reminders": reminders}


def sync():
    data = load()
    who, token = google()
    if not token:
        print(json.dumps({"google": None}))
        return
    try:
        # Added here while offline, or before the account was: to Google now.
        for ev in data["pending"]:
            made = call(token, "POST", "/calendars/primary/events", to_google(ev))
            data["events"] = [e for e in data["events"] if e["id"] != ev["id"]]
            data["events"].append(from_google(made, "primary", []) | {"remind": ev["remind"]})
        data["pending"] = []
        now = datetime.now(timezone.utc)
        window = {"timeMin": (now - timedelta(days=31)).isoformat(), "timeMax": (now + timedelta(days=366)).isoformat(),
                  "singleEvents": "true", "orderBy": "startTime", "maxResults": "2500"}
        events = [e for e in data["events"] if not e.get("google")]
        for cal in call(token, "GET", "/users/me/calendarList").get("items", []):
            if not cal.get("selected") or cal.get("deleted"):
                continue
            defaults = [d["minutes"] for d in cal.get("defaultReminders", []) if d.get("method") == "popup"]
            cid = "primary" if cal.get("primary") else cal["id"]
            page = None
            while True:
                q = dict(window, **({"pageToken": page} if page else {}))
                got = call(token, "GET", f"/calendars/{urllib.parse.quote(cal['id'])}/events", query=q)
                events += [from_google(e, cid, defaults) for e in got.get("items", []) if e.get("status") != "cancelled"]
                page = got.get("nextPageToken")
                if not page:
                    break
        data["events"] = events
    except (urllib.error.URLError, OSError, KeyError, ValueError) as e:
        print(json.dumps({"google": who, "error": str(e)}))
        store(data)
        return
    store(data)
    print(json.dumps({"google": who}))


def add():
    ev = clean(json.load(sys.stdin))
    data = load()
    _, token = google()
    made = None
    if token:
        try:
            made = from_google(call(token, "POST", "/calendars/primary/events", to_google(ev)), "primary", []) | {"remind": ev["remind"]}
        except (urllib.error.URLError, OSError):
            pass
    if not made:
        made = ev | {"id": "local-" + uuid.uuid4().hex, "calendar": "", "google": False}
        # Google didn't take it (offline): sent at the next sync.
        if token:
            data["pending"].append(made)
    data["events"].append(made)
    store(data)
    print(json.dumps(made))


def clean(ev):
    ev = {"title": ev["title"].strip(), "start": ev["start"], "end": ev.get("end") or ev["start"],
          "allDay": bool(ev.get("allDay")), "remind": int(ev.get("remind", -1))}
    if ev["allDay"] and ev["end"][:10] <= ev["start"][:10]:
        ev["end"] = (datetime.fromisoformat(ev["start"][:10]) + timedelta(days=1)).isoformat(timespec="minutes")
    elif not ev["allDay"] and ev["end"] <= ev["start"]:
        ev["end"] = (datetime.fromisoformat(ev["start"]) + timedelta(hours=1)).isoformat(timespec="minutes")
    return ev


def update(eid):
    new = clean(json.load(sys.stdin))
    data = load()
    old = next((e for e in data["events"] if e["id"] == eid), None)
    if not old:
        sys.exit(1)
    if old.get("google"):
        _, token = google()
        if not token:
            sys.exit(2)
        cal = urllib.parse.quote(old["calendar"] or "primary")
        try:
            got = call(token, "PATCH", f"/calendars/{cal}/events/{urllib.parse.quote(eid)}", to_google(new))
        except (urllib.error.URLError, OSError):
            sys.exit(1)
        new = from_google(got, old["calendar"], []) | {"remind": new["remind"]}
    else:
        new = old | new
        for p in data["pending"]:
            if p["id"] == eid:
                p.update(new)
    data["events"] = [new if e["id"] == eid else e for e in data["events"]]
    store(data)
    print(json.dumps(new))


def delete(eid):
    data = load()
    ev = next((e for e in data["events"] if e["id"] == eid), None)
    if ev and ev.get("google"):
        _, token = google()
        if not token:
            sys.exit(2)
        try:
            call(token, "DELETE", f"/calendars/{urllib.parse.quote(ev['calendar'] or 'primary')}/events/{urllib.parse.quote(eid)}")
        except urllib.error.HTTPError as e:
            if e.code not in (404, 410):
                sys.exit(1)
    data["events"] = [e for e in data["events"] if e["id"] != eid]
    data["pending"] = [e for e in data["pending"] if e["id"] != eid]
    store(data)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "status":
        print(json.dumps({"google": google()[0]}))
    elif cmd == "list":
        print(json.dumps(load()["events"]))
    elif cmd == "sync":
        sync()
    elif cmd == "add":
        add()
    elif cmd == "update" and len(sys.argv) > 2:
        update(sys.argv[2])
    elif cmd == "delete" and len(sys.argv) > 2:
        delete(sys.argv[2])
    else:
        sys.exit(1)
