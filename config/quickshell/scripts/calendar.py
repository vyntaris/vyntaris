#!/usr/bin/env python3
# The calendar's events, kept in ~/.local/share/vyntaris/calendar/events.json; with a Google account signed in
# (connect), Google Calendar's too, both ways.
#   status                 {"google": "name@gmail.com" or null, "client": whether a Google client is set up}
#   connect | disconnect   Google: sign in in the browser, or out
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


# Google: Vyntaris's own sign-in (OAuth for a desktop app, through the browser), the refresh token in the keyring.
TOKEN = "https://oauth2.googleapis.com/token"
SCOPE = "https://www.googleapis.com/auth/calendar"
KEYRING = ["service", "vyntaris-calendar", "account", "google"]


def client():
    """The OAuth client: the user's own (~/.config/vyntaris/google-oauth), else the one Vyntaris ships."""
    for path in (os.path.expanduser("~/.config/vyntaris/google-oauth"), "/usr/share/vyntaris/google-oauth"):
        try:
            vals = dict(line.strip().split("=", 1) for line in open(path) if "=" in line)
        except OSError:
            continue
        if vals.get("GOOGLE_CLIENT_ID") and vals.get("GOOGLE_CLIENT_SECRET"):
            return vals["GOOGLE_CLIENT_ID"].strip(), vals["GOOGLE_CLIENT_SECRET"].strip()
    return None, None


def post(url, fields):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(fields).encode(), method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read() or b"{}")


def keyring(*args, secret=None):
    import subprocess
    p = subprocess.run(["secret-tool", *args], input=secret, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


def google():
    """The account signed in, and a fresh access token for it: (email, token), or (None, None)."""
    refresh = keyring("lookup", *KEYRING)
    cid, secret = client()
    if not refresh or not cid:
        return None, None
    who = load().get("google") or ""
    cache = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "vyntaris-calendar-token")
    try:
        t = json.load(open(cache))
        if t["expires"] > datetime.now().timestamp() + 60:
            return who, t["token"]
    except (OSError, ValueError, KeyError):
        pass
    try:
        got = post(TOKEN, {"client_id": cid, "client_secret": secret, "refresh_token": refresh, "grant_type": "refresh_token"})
    except urllib.error.HTTPError:
        return who or None, None
    except (urllib.error.URLError, OSError):
        return who or None, None
    fd = os.open(cache, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({"token": got["access_token"], "expires": datetime.now().timestamp() + got.get("expires_in", 3000)}, f)
    return who, got["access_token"]


def connect():
    """Sign in in the browser; the answer comes back to a port on this computer only."""
    import base64
    import hashlib
    import http.server
    import secrets
    import subprocess
    cid, secret = client()
    if not cid:
        sys.exit("no Google client: ~/.config/vyntaris/google-oauth")
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    got = {}

    class Answer(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if q.get("state", [""])[0] == state:
                got.update({k: v[0] for k, v in q.items()})
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            ok = "code" in got
            self.wfile.write(("<!doctype html><meta charset=utf-8><title>Vyntaris</title>"
                              "<body style='font:16px sans-serif;background:#1e1e2e;color:#cdd6f4;display:grid;place-items:center;height:90vh'>"
                              + ("Signed in. You can close this tab." if ok else "Not signed in.") + "</body>").encode())

        def log_message(self, *a):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Answer)
    server.timeout = 300
    redirect = f"http://127.0.0.1:{server.server_port}"
    url = "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode({
        "client_id": cid, "redirect_uri": redirect, "response_type": "code", "scope": SCOPE, "state": state,
        "code_challenge": challenge, "code_challenge_method": "S256", "access_type": "offline", "prompt": "consent"})
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    server.handle_request()
    if "code" not in got:
        sys.exit("not signed in")
    tok = post(TOKEN, {"client_id": cid, "client_secret": secret, "code": got["code"], "code_verifier": verifier,
                       "redirect_uri": redirect, "grant_type": "authorization_code"})
    if not tok.get("refresh_token"):
        sys.exit("Google gave no refresh token")
    keyring("store", "--label=Vyntaris Calendar (Google)", *KEYRING, secret=tok["refresh_token"])
    # The primary calendar's id is the account's address.
    cal = call(tok["access_token"], "GET", "/calendars/primary")
    data = load()
    data["google"] = cal.get("id", "")
    store(data)
    sync()


def disconnect():
    refresh = keyring("lookup", *KEYRING)
    if refresh:
        try:
            post("https://oauth2.googleapis.com/revoke", {"token": refresh})
        except (urllib.error.URLError, OSError):
            pass
    keyring("clear", *KEYRING)
    data = load()
    data["google"] = ""
    data["events"] = [e for e in data["events"] if not e.get("google")]
    store(data)


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
        print(json.dumps({"google": load().get("google") or None if keyring("lookup", *KEYRING) else None,
                          "client": client()[0] is not None}))
    elif cmd == "connect":
        connect()
    elif cmd == "disconnect":
        disconnect()
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
