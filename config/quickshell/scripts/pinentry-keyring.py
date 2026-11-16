#!/usr/bin/env python3
# gpg-agent's pinentry while the passwords open with the login: asked for the passwords key's passphrase, it answers
# from the login keyring (where `pass.sh setup login` keeps it), so nothing asks for a password nobody knows. Any other
# key, or a passphrase the keyring doesn't have or got wrong, goes to the usual pinentry as if this weren't here.
import os
import subprocess
import sys

REAL = os.environ.get("VYNTARIS_PINENTRY_REAL", "/usr/bin/pinentry")
STORE = os.environ.get("PASSWORD_STORE_DIR") or os.path.expanduser("~/.password-store")


def keygrips():
    """The passwords key's keygrips (the key and its subkeys), from the public keyring: no agent needed."""
    try:
        fpr = open(os.path.join(STORE, ".gpg-id")).readline().strip()
        out = subprocess.run(["gpg", "--batch", "--with-colons", "--with-keygrip", "--list-keys", fpr],
                             capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return set()
    return {line.split(":")[9] for line in out.splitlines() if line.startswith("grp:")}


def from_keyring():
    try:
        return subprocess.run(["secret-tool", "lookup", "service", "vyntaris-passwords"],
                              capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def escape(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main():
    real = subprocess.Popen([REAL] + sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    out = sys.stdout.buffer

    def relay():
        """The real pinentry's answer, up to its OK or ERR, passed on."""
        while True:
            line = real.stdout.readline()
            if not line:
                return False
            out.write(line)
            out.flush()
            if line.startswith((b"OK", b"ERR")):
                return True

    relay()  # its greeting
    keygrip, failed = "", False
    for line in sys.stdin.buffer:
        text = line.decode(errors="replace").rstrip("\r\n")
        word, _, arg = text.partition(" ")
        if word == "SETKEYINFO":
            keygrip = arg.split("/")[-1]
            failed = False
        elif word == "SETERROR" and arg:
            failed = True  # the agent says the last answer was wrong: the person decides from now on
        if word == "GETPIN" and keygrip and not failed and keygrip in keygrips():
            phrase = from_keyring()
            if phrase:
                out.write(b"D " + escape(phrase).encode() + b"\nOK\n")
                out.flush()
                continue
        real.stdin.write(line)
        real.stdin.flush()
        if not relay() or word == "BYE":
            break
    real.stdin.close()
    real.wait()


if __name__ == "__main__":
    main()
