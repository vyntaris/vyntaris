#!/usr/bin/env python3
# Firefox's side of the passwords (native messaging host "vyntaris_passwords"), and the island's way in.
#   pass-host.py <manifest> <extension id>    started by Firefox: logins go to the island, fills come back
#   pass-host.py fill                          {"user", "password"} or {"fields"} on stdin, to the page with the focus;
#                                              exit 0 if a page took it, 1 if not (type it instead)
import json
import os
import socket
import struct
import subprocess
import sys
import threading

RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "vyntaris-passwords")


def host():
    os.makedirs(RUN, mode=0o700, exist_ok=True)
    os.chmod(RUN, 0o700)
    out_lock = threading.Lock()
    waiting = {}

    def send(msg):
        data = json.dumps(msg).encode()
        with out_lock:
            sys.stdout.buffer.write(struct.pack("@I", len(data)) + data)
            sys.stdout.buffer.flush()

    def offer(msg):
        # Kept for the island in a file only this user can read; the password never goes through argv.
        path = os.path.join(RUN, "offer.json")
        fd = os.open(path + ".new", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump({"site": msg.get("site", ""), "user": msg.get("user", ""), "password": msg["password"]}, f)
        os.replace(path + ".new", path)
        subprocess.run(["qs", "-c", "vyntaris", "ipc", "call", "passwords", "offer"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # The island's fills, through a socket of this Firefox's own.
    sock_path = os.path.join(RUN, f"{os.getpid()}.sock")
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(sock_path)
    os.chmod(sock_path, 0o600)
    server.listen()

    def serve():
        n = 0
        while True:
            conn, _ = server.accept()
            with conn:
                try:
                    req = json.loads(conn.makefile().readline())
                except (ValueError, OSError):
                    continue
                n += 1
                done = threading.Event()
                waiting[n] = [done, False]
                fill = {"type": "fill", "id": n, "user": req.get("user", ""), "password": req.get("password", "")}
                if isinstance(req.get("fields"), dict):
                    fill["fields"] = {str(k): str(v) for k, v in req["fields"].items()}
                send(fill)
                done.wait(1.5)
                ok = waiting.pop(n, [None, False])[1]
                try:
                    conn.sendall(b"ok\n" if ok else b"no\n")
                except OSError:
                    pass

    threading.Thread(target=serve, daemon=True).start()

    try:
        while True:
            head = sys.stdin.buffer.read(4)
            if len(head) < 4:
                break
            msg = json.loads(sys.stdin.buffer.read(struct.unpack("@I", head)[0]))
            if msg.get("type") == "login" and msg.get("password"):
                offer(msg)
            elif msg.get("type") == "open" and msg.get("site"):
                # The icon in a field: the island, always.
                field = msg.get("field") if msg.get("field") in ("user", "card") else "password"
                subprocess.run(["qs", "-c", "vyntaris", "ipc", "call", "passwords", "pick", str(msg["site"])[:253], field,
                                str(bool(msg.get("user"))).lower(), str(bool(msg.get("userEmpty"))).lower(),
                                str(bool(msg.get("signup"))).lower()],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            elif msg.get("type") == "filled" and msg.get("id") in waiting:
                waiting[msg["id"]][1] = bool(msg.get("ok"))
                waiting[msg["id"]][0].set()
    finally:
        os.unlink(sock_path)


def fill():
    req = sys.stdin.read()
    if not os.path.isdir(RUN):
        sys.exit(1)
    for name in os.listdir(RUN):
        if not name.endswith(".sock"):
            continue
        path = os.path.join(RUN, name)
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.settimeout(2)
                s.connect(path)
                s.sendall(req.strip().encode() + b"\n")
                if s.makefile().readline().strip() == "ok":
                    sys.exit(0)
        except ConnectionRefusedError:
            os.unlink(path)  # left by a Firefox that's gone
        except OSError:
            pass
    sys.exit(1)


if __name__ == "__main__":
    if sys.argv[1:2] == ["fill"]:
        fill()
    else:
        host()
