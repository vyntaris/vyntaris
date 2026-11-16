#!/usr/bin/env bash
# The island's passwords (scripts/pass.sh) against a store and a key of their own: nothing of the user's is touched.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'gpgconf --homedir "$T/gnupg" --kill gpg-agent 2>/dev/null; gpgconf --homedir "$T/gnupg2" --kill gpg-agent 2>/dev/null; rm -rf "$T"' EXIT
fails=0
ok() { echo "   ok    $*"; }
no() { echo "   FAIL  $*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else no "$what"; fi; }

mkdir -p "$T/home" "$T/bin" "$T/scripts" && chmod 700 "$T"
export HOME="$T/home" GNUPGHOME="$T/gnupg" PASSWORD_STORE_DIR="$T/store" PATH="$T/bin:$PATH"
mkdir -m700 "$GNUPGHOME"
cp "$REPO/config/quickshell/scripts/pass.sh" "$T/scripts/"
# What leaves pass.sh: Firefox's side, the clipboard, the keyring (none here)
printf '#!/bin/sh\ncat > "%s/filled"\n' "$T" > "$T/scripts/pass-host.py"
printf '#!/bin/sh\necho "$*" > "%s/copied-args"; cat > "%s/copied"\n' "$T" "$T" > "$T/bin/wl-copy"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/secret-tool"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/wl-paste"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/wtype"
chmod 755 "$T"/scripts/* "$T"/bin/*
P="$T/scripts/pass.sh"

gpg --batch --quiet --passphrase '' --quick-gen-key "test@vyntaris.invalid" default default never 2>/dev/null
pass init "test@vyntaris.invalid" >/dev/null || { echo "pass: no store"; exit 1; }

echo ":: saving and checking logins"
printf 's3cret\nlogin: me\n' | "$P" save github.com/me
check "an entry is saved"                     test -f "$T/store/github.com/me.gpg"
check "the same login: same"                  test "$(printf 'me\ns3cret\n' | "$P" check github.com)" = same
check "another password: changed, which one"  test "$(printf 'me\nother\n' | "$P" check github.com)" = "changed github.com/me"
check "www. is the same site"                 test "$(printf 'me\ns3cret\n' | "$P" check www.github.com)" = same
check "a site not saved: new, named for it"   test "$(printf 'bob\npw\n' | "$P" check example.org)" = "new example.org/bob"
check "a subdomain is that site's"            test "$(printf 'me\ns3cret\n' | "$P" check gist.github.com)" = same

echo ":: filling: only into the entry's site"
"$P" fill github.com/me page >/dev/null 2>&1
check "the password goes to Firefox"          grep -q '"password": "s3cret"' "$T/filled"
check "… with the site it belongs to"         grep -q '"sites": \["github.com"\]' "$T/filled"
printf 'pw\n' | "$P" save work/notes >/dev/null
"$P" fill work/notes page >/dev/null 2>&1
check "an entry named for no site: none"      grep -q '"sites": \[\]' "$T/filled"
printf 'card\nnumber: 4111\n' | "$P" save shop.example.com/card >/dev/null
"$P" fill-fields shop.example.com/card >/dev/null 2>&1
check "form fields go with their site too"    grep -q '"sites": \["shop.example.com"\]' "$T/filled"
check "… and the fields"                      grep -q '"number": "4111"' "$T/filled"

echo ":: copying"
"$P" copy github.com/me >/dev/null 2>&1
check "the password to the clipboard"         test "$(cat "$T/copied")" = s3cret
check "… marked sensitive (kept off the phone and the history)" grep -q -- --sensitive "$T/copied-args"
"$P" copy github.com/me login >/dev/null 2>&1
check "the username"                          test "$(cat "$T/copied")" = me

echo ":: with the login: nothing asks, whoever opens the key"
# A store of its own whose key has a passphrase, kept in the (stand-in) keyring as setup login does
export GNUPGHOME="$T/gnupg2" PASSWORD_STORE_DIR="$T/store2"
mkdir -m700 "$GNUPGHOME"
cp "$REPO/config/quickshell/scripts/pinentry-keyring.py" "$T/scripts/"
printf '#!/bin/sh\necho "OK ready"; while read -r l; do case "$l" in GETPIN) echo "ERR 83886179 Operation cancelled";; BYE) echo OK; exit;; *) echo OK;; esac; done\n' > "$T/bin/pinentry-none"
chmod 755 "$T/bin/pinentry-none" "$T/scripts/pinentry-keyring.py"
export VYNTARIS_PINENTRY_REAL="$T/bin/pinentry-none"   # a person who answers nothing
printf '%s' 'Kx9mLong40CharsFromSetupLogin0000000000' | gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 0 \
    --quick-gen-key "login@vyntaris.invalid" default default never 2>/dev/null
pass init "login@vyntaris.invalid" >/dev/null
printf 'hidden\n' | "$P" save site.org/x
printf '#!/bin/sh\nprintf %%s Kx9mLong40CharsFromSetupLogin0000000000\n' > "$T/bin/secret-tool"
"$P" kept
check "kept: gpg-agent asks through the keyring"   grep -q '^pinentry-program .*pinentry-keyring' "$GNUPGHOME/gpg-agent.conf"
gpgconf --kill gpg-agent
check "pass in a terminal opens it, nobody asked" bash -c 'test "$(pass show site.org/x </dev/null 2>/dev/null)" = hidden'
printf '#!/bin/sh\nexit 1\n' > "$T/bin/secret-tool"
gpgconf --kill gpg-agent
check "not in the keyring: asked as before"       bash -c '! pass show site.org/x </dev/null >/dev/null 2>&1'
"$P" forget
check "the login off: the usual pinentry again"   bash -c '! grep -q pinentry-keyring "$0"' "$GNUPGHOME/gpg-agent.conf"
gpgconf --kill gpg-agent

echo
[ "$fails" = 0 ] && echo "pass: all checks passed" || echo "pass: $fails failed"
exit $((fails > 0))
