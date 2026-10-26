#!/usr/bin/env python3
import hashlib
import json
import os
import pathlib
import queue
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
DAEMON = os.environ.get("PHONED") or str(ROOT / "rust/target/release/vyntaris-phoned")

if "DBUS_TEST_PRIVATE" not in os.environ:
    os.environ["DBUS_TEST_PRIVATE"] = "1"
    os.execvp("dbus-run-session", ["dbus-run-session", "--", sys.executable, __file__])

TMP = pathlib.Path(tempfile.mkdtemp())
UDP, PHONE_UDP, TCP, PAYLOAD = 41716, 41717, 41720, 41780
ENV = dict(os.environ, HOME=str(TMP / "home"), XDG_CONFIG_HOME=str(TMP / "home/.config"),
           XDG_CACHE_HOME=str(TMP / "home/.cache"), XDG_RUNTIME_DIR=str(TMP), VYNTARIS_PHONE_TEST="1",
           VYNTARIS_PHONE_UDP_PORT=str(UDP), VYNTARIS_PHONE_PEER_UDP_PORT=str(PHONE_UDP),
           VYNTARIS_PHONE_TCP_PORT=str(TCP), VYNTARIS_PHONE_PAYLOAD_PORT=str(PAYLOAD),
           VYNTARIS_PHONE_FAKE_DESKTOP=str(TMP / "desktop.log"), VYNTARIS_PHONE_FAKE_PICK=str(ROOT / "README.md"))
CONFIG = TMP / "home/.config/vyntaris/phone"
SOCK = TMP / "vyntaris-phone.sock"

fails = 0

def check(what, ok):
    global fails
    print(("   ok    " if ok else "   FAIL  ") + what)
    fails += not ok

def packet(kind, body=None, **extra):
    return {"id": int(time.time() * 1000), "type": kind, "body": body or {}, **extra}

def line(pkt):
    return (json.dumps(pkt) + "\n").encode()

def spki(cert_pem_path):
    out = subprocess.run(["openssl", "x509", "-in", str(cert_pem_path), "-pubkey", "-noout"], capture_output=True, text=True).stdout
    return ssl.PEM_cert_to_DER_cert(out.replace("PUBLIC KEY", "CERTIFICATE"))

class Phone:

    def __init__(self, name, id=None):
        self.name, self.id = name, id or os.urandom(16).hex()
        self.dir = TMP / f"phone-{name}"
        self.dir.mkdir()
        self.cert, self.key = self.dir / "cert.pem", self.dir / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30", "-keyout", str(self.key),
                        "-out", str(self.cert), "-subj", f"/O=KDE/OU=Kde connect/CN={self.id}"], check=True, capture_output=True)
        self.kept = []
        self.sock = None

    def identity(self, **extra):
        return packet("kdeconnect.identity", {
            "deviceId": self.id, "deviceName": self.name, "deviceType": "phone", "protocolVersion": 8,
            "incomingCapabilities": ["kdeconnect.ping", "kdeconnect.findmyphone.request", "kdeconnect.share.request",
                                     "kdeconnect.clipboard", "kdeconnect.battery"],
            "outgoingCapabilities": ["kdeconnect.ping", "kdeconnect.notification", "kdeconnect.battery"], **extra})

    def connect(self):
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp.bind(("127.0.0.1", PHONE_UDP))
        udp.settimeout(5)
        udp.sendto(line(self.identity(tcpPort=1716)), ("127.0.0.1", UDP))
        try:
            answer = json.loads(udp.recvfrom(65536)[0])
        finally:
            udp.close()
        self.computer = answer["body"]
        raw = socket.create_connection(("127.0.0.1", self.computer["tcpPort"]), timeout=5)
        raw.sendall(line(self.identity(targetDeviceId=self.computer["deviceId"], targetProtocolVersion=8)))
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(self.cert, self.key)
        ctx.verify_mode = ssl.CERT_REQUIRED
        ctx.load_verify_locations(cafile=str(CONFIG / "cert.pem"))
        self.sock = ctx.wrap_socket(raw, server_side=True)
        self.buffer = b""
        self.sock.sendall(line(self.identity()))
        self.secure_identity = self.next_packet(5)
        return self

    def next_packet(self, timeout):
        end = time.time() + timeout
        while b"\n" not in self.buffer:
            left = end - time.time()
            if left <= 0:
                return None
            self.sock.settimeout(left)
            try:
                chunk = self.sock.recv(65536)
            except (socket.timeout, ssl.SSLWantReadError):
                return None
            except OSError:
                return None
            if not chunk:
                return None
            self.buffer += chunk
        raw, _, self.buffer = self.buffer.partition(b"\n")
        return json.loads(raw)

    def send(self, kind, body=None, **extra):
        self.sock.sendall(line(packet(kind, body, **extra)))

    def expect(self, kind, timeout=5, where=None):
        for i, pkt in enumerate(self.kept):
            if pkt["type"] == kind and (where is None or where(pkt["body"])):
                return self.kept.pop(i)
        end = time.time() + timeout
        while time.time() < end:
            pkt = self.next_packet(end - time.time())
            if pkt is None:
                return None
            if pkt["type"] == kind and (where is None or where(pkt["body"])):
                return pkt
            self.kept.append(pkt)
        return None

    def offer(self, data):
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(self.cert, self.key)
        ctx.verify_mode = ssl.CERT_REQUIRED
        ctx.load_verify_locations(cafile=str(CONFIG / "cert.pem"))

        def give():
            conn, _ = server.accept()
            with ctx.wrap_socket(conn, server_side=True) as s:
                s.sendall(data)
            server.close()
        threading.Thread(target=give, daemon=True).start()
        return server.getsockname()[1]

    def take(self, pkt):
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        ctx.load_cert_chain(self.cert, self.key)
        with ctx.wrap_socket(socket.create_connection(("127.0.0.1", pkt["payloadTransferInfo"]["port"]), timeout=5)) as s:
            data = b""
            while len(data) < pkt["payloadSize"]:
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
        return data

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

class Shell:

    def __init__(self):
        for _ in range(100):
            try:
                self.sock = socket.socket(socket.AF_UNIX)
                self.sock.connect(str(SOCK))
                break
            except OSError:
                time.sleep(0.1)
        self.file = self.sock.makefile("rb")
        self.msgs = queue.Queue()
        threading.Thread(target=lambda: [self.msgs.put(json.loads(raw)) for raw in self.file], daemon=True).start()
        self.state = None
        self.errors = []

    def do(self, **cmd):
        self.sock.sendall(line(cmd))

    def until(self, test, timeout=5):
        end = time.time() + timeout
        while time.time() < end:
            if self.state and test(self.state):
                return self.state
            try:
                msg = self.msgs.get(timeout=max(0.01, end - time.time()))
            except queue.Empty:
                break
            if "state" in msg:
                self.state = msg["state"]
            if "error" in msg:
                self.errors.append(msg["error"])
        return self.state if self.state and test(self.state) else None

    def device(self, id):
        return next((d for d in (self.state or {}).get("devices", []) if d["id"] == id), None)

def desktop_log():
    try:
        return [json.loads(l) for l in (TMP / "desktop.log").read_text().splitlines()]
    except OSError:
        return []

def did(test, timeout=3):
    end = time.time() + timeout
    while time.time() < end:
        if any(test(e) for e in desktop_log()):
            return True
        time.sleep(0.05)
    return False

def main():
    daemon = subprocess.Popen([DAEMON], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    crashed = False
    try:
        run()
    except Exception:
        crashed = True
        raise
    finally:
        daemon.terminate()
        try:
            _, err = daemon.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            daemon.kill()
            _, err = daemon.communicate()
        if (fails or crashed) and err:
            print("\nthe link said:\n" + err[-3000:])
        shutil.rmtree(TMP, ignore_errors=True)
    print()
    print("phone: all checks passed" if fails == 0 else f"phone: {fails} failed")
    return 1 if fails else 0

def run():
    print("Started")
    shell = Shell()
    state = shell.until(lambda s: s["running"])
    check("it tells the shell it runs, no phones yet", bool(state) and state["devices"] == [])
    check("its own certificate, the key kept private", (CONFIG / "cert.pem").exists() and oct((CONFIG / "key.pem").stat().st_mode)[-3:] == "600")

    print("A phone comes")
    phone = Phone("Pixel").connect()
    check("found it, connected, TLS both ways", phone.secure_identity["body"]["deviceId"] == phone.computer["deviceId"])
    state = shell.until(lambda s: (shell.device(phone.id) or {}).get("reachable"))
    check("shown to the shell, not paired", bool(state) and shell.device(phone.id)["pairState"] == 0)
    phone.send("kdeconnect.notification", {"id": "1", "appName": "Chat", "title": "Sneaky", "text": "unpaired"})
    phone.send("kdeconnect.mousepad.request", {"dx": 50, "dy": 50})
    time.sleep(0.5)
    check("nothing taken from a phone not paired", not did(lambda e: e.get("title") == "Sneaky" or e["do"] == "pointer", 0.3))

    print("Pairing (the phone asks)")
    stamp = int(time.time())
    phone.send("kdeconnect.pair", {"pair": True, "timestamp": stamp})
    state = shell.until(lambda s: (shell.device(phone.id) or {}).get("code"))
    a, b = spki(CONFIG / "cert.pem"), spki(phone.cert)
    code = hashlib.sha256(max(a, b) + min(a, b) + str(stamp).encode()).hexdigest()[:8].upper()
    check("asking, with the code the phone shows too", bool(state) and shell.device(phone.id)["pairState"] == 2
          and shell.device(phone.id)["code"] == code)
    check("asked on the screen too", did(lambda e: e["do"] == "notify" and "wants to pair" in e["title"] and code in e["body"]))
    shell.do(do="accept", id=phone.id)
    check("accepted: the phone told", phone.expect("kdeconnect.pair", where=lambda b: b.get("pair") is True) is not None)
    state = shell.until(lambda s: (shell.device(phone.id) or {}).get("pairState") == 3)
    check("paired, and kept", bool(state) and (CONFIG / "devices" / f"{phone.id}.json").exists())
    check("told this computer's battery", phone.expect("kdeconnect.battery", where=lambda b: b.get("currentCharge") == 64) is not None)
    check("told it can be typed on", phone.expect("kdeconnect.mousepad.keyboardstate") is not None)
    commands = phone.expect("kdeconnect.runcommand")
    check("told what it can run here", bool(commands) and "lock" in json.loads(commands["body"]["commandList"]))

    print("From the phone")
    phone.send("kdeconnect.battery", {"currentCharge": 55, "isCharging": True})
    phone.send("kdeconnect.connectivity_report", {"signalStrengths": {"1": {"networkType": "5G", "signalStrength": 3}}})
    state = shell.until(lambda s: (shell.device(phone.id) or {}).get("battery") == 55 and shell.device(phone.id)["network"] == "5G")
    check("its battery and network", bool(state) and shell.device(phone.id)["charging"] and shell.device(phone.id)["signal"] == 3)
    phone.send("kdeconnect.notification", {"id": "n1", "appName": "Chat", "title": "Ana", "text": "Hi!", "isClearable": True,
                                           "actions": ["Mark as read"]})
    check("its notification, with its button", did(lambda e: e["do"] == "notify" and e["title"] == "Ana" and e["actions"] == ["a:Mark as read"]))
    phone.send("kdeconnect.notification", {"id": "n2", "appName": "Mail", "title": "Old", "silent": True})
    check("the ones there already aren't shown again", not did(lambda e: e.get("title") == "Old", 0.4))
    phone.send("kdeconnect.clipboard", {"content": "copied on the phone"})
    check("its clipboard, here", did(lambda e: e["do"] == "clipboard" and e["text"] == "copied on the phone"))
    phone.send("kdeconnect.mousepad.request", {"dx": 12.5, "dy": -4})
    check("its touchpad moves the pointer", did(lambda e: e["do"] == "pointer" and e["what"] == "move" and e["args"] == [12.5, -4.0]))
    phone.send("kdeconnect.mousepad.request", {"singleclick": True})
    check("and clicks", did(lambda e: e["do"] == "pointer" and e["what"] == "click"))
    phone.send("kdeconnect.mousepad.request", {"specialKey": 12})
    check("its keyboard: Enter", did(lambda e: e["do"] == "keys" and e["cmd"] == ["wtype", "-k", "Return"]))
    phone.send("kdeconnect.mousepad.request", {"key": "c", "ctrl": True})
    check("and Ctrl+C", did(lambda e: e["do"] == "keys" and e["cmd"] == ["wtype", "-M", "ctrl", "-k", "c", "-m", "ctrl"]))
    phone.send("kdeconnect.runcommand.request", {"key": "lock"})
    check("runs a command offered", did(lambda e: e["do"] == "run" and e["cmd"] == ["loginctl", "lock-session"]))
    phone.send("kdeconnect.runcommand.request", {"key": "rm -rf ~"})
    check("never one not offered", not did(lambda e: e["do"] == "run" and "rm" in " ".join(e["cmd"]), 0.4))
    phone.send("kdeconnect.systemvolume.request", {"requestSinks": True})
    sinks = phone.expect("kdeconnect.systemvolume")
    check("this computer's volume, for its slider", bool(sinks) and sinks["body"]["sinkList"][0]["volume"] == 40)
    phone.send("kdeconnect.mpris.request", {"requestPlayerList": True})
    players = phone.expect("kdeconnect.mpris", where=lambda b: "playerList" in b)
    check("the music players here", bool(players) and players["body"]["playerList"] == ["Music"])
    phone.send("kdeconnect.mpris.request", {"player": "Music", "action": "PlayPause"})
    check("its remote plays and pauses them", did(lambda e: e["do"] == "player" and e["action"] == "PlayPause"))
    check("and is told what's playing", phone.expect("kdeconnect.mpris", where=lambda b: b.get("title") == "Song") is not None)
    phone.send("kdeconnect.telephony", {"event": "ringing", "contactName": "Mom"})
    check("a call: shown", did(lambda e: e["do"] == "notify" and e["title"] == "Call from Mom"))
    check("and the music paused", did(lambda e: e["do"] == "player" and e["action"] == "Pause"))
    phone.send("kdeconnect.telephony", {"event": "ringing", "contactName": "Mom", "isCancel": True})
    check("after it, playing again", did(lambda e: e["do"] == "player" and e["action"] == "Play"))
    phone.send("kdeconnect.findmyphone.request")
    check("it looks for this computer: it rings", did(lambda e: e["do"] == "ring" and e["on"]))
    data = os.urandom(200_000)
    port = phone.offer(data)
    phone.send("kdeconnect.share.request", {"filename": "../../photo.jpg"}, payloadSize=len(data), payloadTransferInfo={"port": port})
    got = TMP / "home/Downloads/photo.jpg"
    for _ in range(50):
        if got.exists():
            break
        time.sleep(0.1)
    check("a file from it: in Downloads, whole, its name kept to itself", got.exists() and got.read_bytes() == data)
    check("and said", did(lambda e: e["do"] == "notify" and e["title"] == "A file from your phone"))

    print("To the phone")
    shell.do(do="ring", id=phone.id)
    check("ring it", phone.expect("kdeconnect.findmyphone.request") is not None)
    shell.do(do="clipboard", id=phone.id)
    check("send it the clipboard", phone.expect("kdeconnect.clipboard", where=lambda b: b.get("content") == "copied on the phone") is not None)
    afile = ROOT / "pkg/PKGBUILD"
    shell.do(do="share", id=phone.id, paths=[str(afile)])
    offer = phone.expect("kdeconnect.share.request")
    check("send it a file: offered", bool(offer) and offer["body"]["filename"] == "PKGBUILD")
    check("and taken whole, over TLS", bool(offer) and phone.take(offer) == afile.read_bytes())
    shell.do(do="pick", id=phone.id)
    offer = phone.expect("kdeconnect.share.request")
    check("files chosen in the file chooser, sent", bool(offer) and offer["body"]["filename"] == "README.md" and phone.take(offer))
    shell.do(do="feature", id=phone.id, plugin="control", on=False)
    shell.until(lambda s: (shell.device(phone.id) or {}).get("features", {}).get("control") is False)
    phone.send("kdeconnect.mousepad.request", {"dx": 99, "dy": 99})
    check("control turned off: its touchpad does nothing", not did(lambda e: e["do"] == "pointer" and e["args"] == [99.0, 99.0], 0.5))
    shell.do(do="rename", name="Den: PC!")
    check("this computer renamed, the phone told", phone.expect("kdeconnect.identity", where=lambda b: b.get("deviceName") == "Den PC") is not None)

    print("Kept out")
    shell.errors.clear()
    for cmd in ({"do": "share", "id": phone.id, "paths": ["/nonexistent"]}, {"do": "feature", "id": phone.id, "plugin": "everything", "on": True},
                {"do": "ring", "id": "nobody"}, {"do": "rm", "id": phone.id}, {"do": "rename", "name": "?!"}):
        shell.do(**cmd)
    shell.until(lambda s: False, timeout=1)
    check("what the shell can't ask: said, not done", len(shell.errors) == 5)
    impostor = Phone("Impostor", id=phone.id)
    try:
        impostor.connect()
        let_in = impostor.expect("kdeconnect.battery", timeout=1) is not None
    except (OSError, ValueError, KeyError):
        let_in = False
    check("a phone with the paired one's id but another certificate: not let in", not let_in)
    stranger = Phone("Stranger").connect()
    shell.until(lambda s: shell.device(stranger.id) is not None)
    stranger.send("kdeconnect.findmyphone.request")
    check("an unpaired phone can't make it ring", not did(lambda e: e["do"] == "ring" and e["on"] and e is not None, 0.4) or
          sum(1 for e in desktop_log() if e["do"] == "ring") == 1)

    print("Going")
    phone.send("kdeconnect.pair", {"pair": False})
    state = shell.until(lambda s: (shell.device(phone.id) or {}).get("pairState") == 0)
    check("unpaired from the phone: forgotten here too", bool(state) and not (CONFIG / "devices" / f"{phone.id}.json").exists())
    stranger.close()
    state = shell.until(lambda s: shell.device(stranger.id) is None)
    check("an unpaired phone gone: gone from the list", state is not None)

if __name__ == "__main__":
    sys.exit(main())
