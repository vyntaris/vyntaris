#!/usr/bin/env python3
# Claude Code's sessions on this computer (~/.claude/projects), for the island.
#   claude-sessions.py list         one JSON line per session, newest first: {id, cwd, title, at}
#   claude-sessions.py show <id>    the session's conversation: one JSON line per message {role, text, tools}
import glob
import json
import os
import re
import sys

ROOT = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"), "projects")


def text_of(content):
    if isinstance(content, str):
        return content
    return "\n\n".join(c.get("text", "") for c in content or [] if isinstance(c, dict) and c.get("type") == "text")


def real_prompt(text):
    # Leave out what the CLI adds in the user's name: commands, reminders, interruptions.
    t = text.strip()
    return t and not t.startswith(("<", "[Request interrupted", "Caveat:"))


def summary(path):
    title = first = cwd = ""
    with open(path, errors="ignore") as f:
        for line in f:
            if '"ai-title"' in line or '"custom-title"' in line:
                try:
                    e = json.loads(line)
                    title = e.get("customTitle") or e.get("aiTitle") or title
                except ValueError:
                    pass
            elif not first and '"type":"user"' in line.replace(" ", ""):
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                cwd = cwd or e.get("cwd", "")
                t = text_of((e.get("message") or {}).get("content"))
                if real_prompt(t):
                    first = " ".join(t.split())[:120]
    return title, first, cwd


def listing():
    files = sorted(glob.glob(os.path.join(ROOT, "*", "*.jsonl")), key=os.path.getmtime, reverse=True)[:40]
    for path in files:
        title, first, cwd = summary(path)
        if not (title or first) or not os.path.isdir(cwd):
            continue
        print(json.dumps({"id": os.path.basename(path)[:-6], "cwd": cwd, "title": title or first,
                          "at": int(os.path.getmtime(path))}), flush=True)


def show(sid):
    if not re.fullmatch(r"[A-Za-z0-9-]+", sid):
        return
    paths = glob.glob(os.path.join(ROOT, "*", sid + ".jsonl"))
    if not paths:
        return
    out = []
    with open(paths[0], errors="ignore") as f:
        for line in f:
            if '"type":"user"' not in line.replace(" ", "") and '"type":"assistant"' not in line.replace(" ", ""):
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("isSidechain") or e.get("isMeta"):
                continue
            content = (e.get("message") or {}).get("content")
            if e["type"] == "user":
                t = text_of(content)
                if real_prompt(t):
                    out.append({"role": "user", "text": t.strip()})
            else:
                if not out or out[-1]["role"] != "assistant":
                    out.append({"role": "assistant", "text": "", "tools": []})
                m = out[-1]
                for c in content or []:
                    if c.get("type") == "text" and c.get("text", "").strip():
                        m["text"] += ("\n\n" if m["text"] else "") + c["text"].strip()
                    elif c.get("type") == "tool_use":
                        m["tools"].append({"name": c.get("name", ""), "input": c.get("input") or {}})
    for m in out[-40:]:
        print(json.dumps(m), flush=True)


if __name__ == "__main__":
    if sys.argv[1:2] == ["list"]:
        listing()
    elif sys.argv[1:2] == ["show"] and len(sys.argv) > 2:
        show(sys.argv[2])
