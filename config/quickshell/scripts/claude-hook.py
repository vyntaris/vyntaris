#!/usr/bin/env python3
# Claude Code hooks, for every session on this desktop: its state and its permission questions go to the island.
# Hook input on stdin (JSON), the decision (if any) on stdout. Island chats run with VYNTARIS_ISLAND=1.
import json
import os
import re
import subprocess
import sys
import time

RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "vyntaris-claude")
CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "quickshell/settings.json")
ISLAND = os.environ.get("VYNTARIS_ISLAND") == "1"
SYSTEM = re.compile(r"(^|[;&|(`]\s*|\bthen\s+|\bdo\s+)(sudo|doas|pkexec|run0|mkinitcpio|grub-mkconfig|bootctl"
                    r"|(pacman|paru|yay)\s+(--\S+\s+)*-(S(?![sil]\b)|R|U)[A-Za-z]*|systemctl(?!\s+--user))\b")


def settings():
    try:
        with open(CONFIG) as f:
            c = json.load(f).get("claude", {})
    except (OSError, ValueError):
        c = {}
    return {"timeout": int(c.get("askTimeout", 60)), "snapshot": c.get("snapshotBeforeSystem", True) is not False}


def write(name, data):
    path = os.path.join(RUN, name)
    fd = os.open(path + ".new", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.replace(path + ".new", path)


def read(name, default=None):
    try:
        with open(os.path.join(RUN, name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def ping(fn, arg):
    try:
        return subprocess.run(["qs", "-c", "vyntaris", "ipc", "call", "claude", fn, arg], timeout=3,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def safe(s):
    return re.sub(r"[^A-Za-z0-9_-]", "", s or "")[:80] or "none"


def summary(tool, inp):
    home = os.path.expanduser("~")
    path = lambda p: str(p or "").replace(home, "~", 1)
    if tool == "Bash":
        return {"icon": "terminal", "what": inp.get("command", ""), "detail": inp.get("description", "")}
    if tool in ("Edit", "MultiEdit"):
        edits = inp.get("edits") or [{"old_string": inp.get("old_string", ""), "new_string": inp.get("new_string", "")}]
        diff = "\n".join("- " + l for e in edits[:2] for l in e.get("old_string", "").splitlines()[:6]) + "\n" + \
               "\n".join("+ " + l for e in edits[:2] for l in e.get("new_string", "").splitlines()[:6])
        return {"icon": "edit", "what": path(inp.get("file_path")), "detail": diff.strip()}
    if tool in ("Write", "NotebookEdit"):
        text = inp.get("content") or inp.get("new_source") or ""
        return {"icon": "edit", "what": path(inp.get("file_path") or inp.get("notebook_path")),
                "detail": "\n".join(text.splitlines()[:10])}
    if tool in ("WebFetch", "WebSearch"):
        return {"icon": "globe", "what": inp.get("url") or inp.get("query", ""), "detail": ""}
    return {"icon": "settings", "what": tool, "detail": json.dumps(inp)[:400]}


def rule(tool, inp):
    # What "always, in this session" covers: the tool, and for commands their first word.
    if tool == "Bash":
        return "Bash:" + (inp.get("command", "").split() or [""])[0]
    return tool


def snapshot(sid, cwd, command):
    marker = f"snap-{sid}"
    if read(marker) is not None:
        return
    write(marker, {"at": time.time()})
    ping("snapshot", sid)
    try:
        subprocess.run(["pkexec", "/usr/bin/vyntaris-claude-snapshot", cwd, command[:120]], timeout=600,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        pass


def doing(tool, inp):
    # What the island shows while a session works: the tool and what it works on, short.
    name = lambda p: os.path.basename(str(p or "").rstrip("/")) or str(p or "")
    if tool == "Bash":
        return {"verb": "run", "what": " ".join(inp.get("command", "").split())[:60]}
    if tool in ("Edit", "MultiEdit", "NotebookEdit"):
        return {"verb": "edit", "what": name(inp.get("file_path") or inp.get("notebook_path"))}
    if tool == "Write":
        return {"verb": "write", "what": name(inp.get("file_path"))}
    if tool == "Read":
        return {"verb": "read", "what": name(inp.get("file_path"))}
    if tool in ("Grep", "Glob"):
        return {"verb": "search", "what": inp.get("pattern", "")[:40]}
    if tool in ("WebFetch", "WebSearch"):
        return {"verb": "web", "what": (inp.get("query") or inp.get("url") or "")[:40]}
    if tool in ("Task", "Agent"):
        return {"verb": "agent", "what": inp.get("description", "")[:40]}
    if tool == "TodoWrite":
        return {"verb": "plan", "what": ""}
    return {"verb": "tool", "what": tool}


def session(h, state):
    sid = safe(h.get("session_id"))
    s = read(f"session-{sid}.json", {}) or {}
    s.update({"id": sid, "cwd": h.get("cwd", ""), "state": state, "at": time.time()})
    if h.get("hook_event_name") == "UserPromptSubmit":
        s["title"] = " ".join(h.get("prompt", "").split())[:120]
        s["doing"] = {}
    if h.get("hook_event_name") == "PreToolUse":
        s["doing"] = doing(h.get("tool_name", ""), h.get("tool_input") or {})
    if h.get("hook_event_name") == "Notification":
        s["message"] = h.get("message", "")
    write(f"session-{sid}.json", s)
    ping("event", sid)


def permission(h):
    sid = safe(h.get("session_id"))
    tool = h.get("tool_name", "")
    inp = h.get("tool_input") or {}
    if rule(tool, inp) in (read(f"always-{sid}.json", []) or []):
        return {"behavior": "allow"}
    rid = f"{sid}-{int(time.time() * 1000)}"
    ask = {"id": rid, "session": sid, "cwd": h.get("cwd", ""), "tool": tool, "island": ISLAND, **summary(tool, inp)}
    write(f"ask-{rid}.json", ask)
    answer = os.path.join(RUN, f"answer-{rid}")
    got = None
    if ping("ask", rid):
        end = time.time() + settings()["timeout"]
        while time.time() < end:
            try:
                with open(answer) as f:
                    got = f.read().strip()
                break
            except OSError:
                time.sleep(0.15)
    for name in (f"ask-{rid}.json", f"answer-{rid}"):
        try:
            os.remove(os.path.join(RUN, name))
        except OSError:
            pass
    ping("event", sid)
    if got == "always":
        rules = read(f"always-{sid}.json", []) or []
        write(f"always-{sid}.json", rules + [rule(tool, inp)])
        return {"behavior": "allow"}
    if got == "allow":
        return {"behavior": "allow"}
    if got == "deny" or ISLAND:
        return {"behavior": "deny", "message": "Not allowed in the Vyntaris island."}
    return None  # unanswered, or "terminal": the terminal asks as usual


def main():
    try:
        h = json.load(sys.stdin)
    except ValueError:
        return
    os.makedirs(RUN, mode=0o700, exist_ok=True)
    event = h.get("hook_event_name")
    if event == "PreToolUse":
        cmd = (h.get("tool_input") or {}).get("command", "")
        if h.get("tool_name") == "Bash" and SYSTEM.search(cmd) and settings()["snapshot"]:
            snapshot(safe(h.get("session_id")), h.get("cwd", ""), cmd)
        if not ISLAND:
            session(h, "working")
    elif event == "PermissionRequest":
        decision = permission(h)
        if decision:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}))
    elif not ISLAND:
        if event == "UserPromptSubmit":
            session(h, "working")
        elif event == "Notification":
            session(h, "waiting")
        elif event == "Stop":
            session(h, "done")
        elif event == "SessionEnd":
            sid = safe(h.get("session_id"))
            for name in (f"session-{sid}.json", f"always-{sid}.json", f"snap-{sid}"):
                try:
                    os.remove(os.path.join(RUN, name))
                except OSError:
                    pass
            ping("event", sid)


if __name__ == "__main__":
    main()
