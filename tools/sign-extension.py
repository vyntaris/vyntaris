#!/usr/bin/env python3
# Has Mozilla sign the passwords extension (unlisted: not in the public store) and keeps the signed .xpi in the repo,
# which the package installs. Run once for each new version in firefox/passwords/manifest.json.
#   tools/sign-extension.py            keys from ~/.config/vyntaris/amo-keys (AMO_JWT_ISSUER=…, AMO_JWT_SECRET=…)
#   tools/sign-extension.py --check    the signed .xpi is this version and has the same files (CI)
import base64
import hashlib
import hmac
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "firefox", "passwords")
OUT = os.path.join(REPO, "firefox", "vyntaris-passwords.xpi")
API = "https://addons.mozilla.org/api/v5"
GUID = json.load(open(os.path.join(SRC, "manifest.json")))["browser_specific_settings"]["gecko"]["id"]


def sources():
    return {n: open(os.path.join(SRC, n), "rb").read() for n in sorted(os.listdir(SRC))}


def check():
    if not os.path.exists(OUT):
        sys.exit(f"{OUT} is missing: run tools/sign-extension.py")
    signed = zipfile.ZipFile(OUT)
    names = {n for n in signed.namelist() if not n.startswith("META-INF/")}
    src = sources()
    # Mozilla rewrites the manifest's whitespace.
    same = lambda n: (json.loads(signed.read(n)) == json.loads(src[n])) if n == "manifest.json" else signed.read(n) == src[n]
    stale = [n for n in src if n not in names or not same(n)] + [n for n in names if n not in src]
    if stale:
        sys.exit(f"the signed extension is older than firefox/passwords ({', '.join(stale)}): "
                 "raise its version and run tools/sign-extension.py")
    print(f"extension: signed {json.loads(signed.read('manifest.json'))['version']}, same as the source")


def keys():
    found = {k: os.environ.get(k) for k in ("AMO_JWT_ISSUER", "AMO_JWT_SECRET")}
    path = os.path.expanduser("~/.config/vyntaris/amo-keys")
    if not all(found.values()) and os.path.exists(path):
        for line in open(path):
            k, _, v = line.strip().partition("=")
            if k in found and not found[k]:
                found[k] = v.strip().strip("'\"")
    if not all(found.values()):
        sys.exit("no AMO keys: AMO_JWT_ISSUER and AMO_JWT_SECRET, or ~/.config/vyntaris/amo-keys")
    return found["AMO_JWT_ISSUER"], found["AMO_JWT_SECRET"]


def token(issuer, secret):
    b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
    now = int(time.time())
    head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": issuer, "jti": str(uuid.uuid4()), "iat": now, "exp": now + 60}).encode())
    sig = b64(hmac.new(secret.encode(), head + b"." + body, hashlib.sha256).digest())
    return (head + b"." + body + b"." + sig).decode()


def call(creds, method, path, data=None, files=None, raw=False):
    url = path if path.startswith("http") else API + path
    headers = {"Authorization": "JWT " + token(*creds)}
    body = None
    if files:
        edge = uuid.uuid4().hex
        parts = []
        for k, v in (data or {}).items():
            parts.append(f'--{edge}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
        for k, (name, blob) in files.items():
            parts.append(f'--{edge}\r\nContent-Disposition: form-data; name="{k}"; filename="{name}"\r\n'
                         f'Content-Type: application/zip\r\n\r\n'.encode() + blob + b"\r\n")
        body = b"".join(parts) + f"--{edge}--\r\n".encode()
        headers["Content-Type"] = f"multipart/form-data; boundary={edge}"
    elif data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            out = r.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {url}: {e.code} {e.read().decode(errors='replace')[:500]}")
    return out if raw else json.loads(out or b"{}")


def sign():
    creds = keys()
    zipped = io.BytesIO()
    with zipfile.ZipFile(zipped, "w", zipfile.ZIP_DEFLATED) as z:
        for n, blob in sources().items():
            z.writestr(n, blob)
    version = json.load(open(os.path.join(SRC, "manifest.json")))["version"]
    print(f"uploading {GUID} {version}…")
    up = call(creds, "POST", "/addons/upload/", {"channel": "unlisted"},
              {"upload": ("vyntaris-passwords.zip", zipped.getvalue())})
    while not up.get("processed"):
        time.sleep(3)
        up = call(creds, "GET", f"/addons/upload/{up['uuid']}/")
    if not up.get("valid"):
        sys.exit("Mozilla's check refused it:\n" + json.dumps(up.get("validation"), indent=1)[:3000])
    # A new add-on is made with its first version; later ones are added to it.
    exists = True
    try:
        call(creds, "GET", f"/addons/addon/{GUID}/")
    except SystemExit:
        exists = False
    if exists:
        ver = call(creds, "POST", f"/addons/addon/{GUID}/versions/", {"upload": up["uuid"]})
    else:
        ver = call(creds, "PUT", f"/addons/addon/{GUID}/", {"version": {"upload": up["uuid"]}})["latest_unlisted_version"]
    print("waiting for the signature…")
    while True:
        ver = call(creds, "GET", f"/addons/addon/{GUID}/versions/{ver['id']}/")
        f = ver.get("file") or {}
        if f.get("status") == "public" and f.get("url"):
            break
        if f.get("status") == "disabled":
            sys.exit("Mozilla disabled this version")
        time.sleep(5)
    open(OUT, "wb").write(call(creds, "GET", f["url"], raw=True))
    print(f"signed: {os.path.relpath(OUT, REPO)}")
    check()


if __name__ == "__main__":
    check() if sys.argv[1:2] == ["--check"] else sign()
