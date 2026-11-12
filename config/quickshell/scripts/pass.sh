#!/bin/bash
# The island's passwords, kept by pass (passwordstore.org): GPG-encrypted files in ~/.password-store.
#   status                 ready | nokey
#   list                   every entry
#   setup [login]          a new key and store; the passphrase on stdin, or (login) a random one kept in the
#                          login keyring, which signing in opens
#   unlock [remember]      the passphrase on stdin; gpg-agent keeps it for a while (remember: the keyring too)
#   lock                   forget it now
#   kept                   exit 0 if the passphrase is in the keyring
#   master                 off the login: the key's passphrase changed to the one on stdin (from the keyring's,
#                          the only copy of a made-up one), then out of the keyring
#   forget                 out of the keyring: asked for again
#   show NAME              the entry (exit 5: locked)
#   fill NAME [user|here|page]  into the field with the focus: through Firefox's extension, else typed (the
#                          password; the username, Tab, the password from the password field (user) or
#                          from the username field (here)); page: only through the extension (exit 6: it didn't)
#   fill-fields NAME       personal info or a card ("key: value" lines) into the form with the focus, through Firefox's extension
#   check SITE             a login (username and password lines on stdin): same | changed NAME | new NAME | locked
#   copy NAME [login|field:KEY|note]   to the clipboard (the password, the username, a "KEY:" line, a note's text),
#                          cleared after 45 s
#   save NAME              the entry on stdin
#   delete NAME
#   generate               a new password
store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# The passphrase in the login keyring, opened by signing in.
keyring=(service vyntaris-passwords)
remember() { printf '%s' "$1" | secret-tool store --label="Vyntaris passwords" "${keyring[@]}"; }

open_entry() {
    gpg --quiet --batch --pinentry-mode error -d "$store/$1.gpg" 2>/dev/null && return
    # Not in gpg-agent any more: from the keyring, without asking.
    local phrase
    phrase=$(secret-tool lookup "${keyring[@]}" 2>/dev/null)
    [ -n "$phrase" ] && gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 3 -d "$store/$1.gpg" \
        3<<<"$phrase" 2>/dev/null
}
decrypt() {
    [ -f "$store/$1.gpg" ] || exit 1
    open_entry "$1" || exit 5
}

# The first line is the password; the username is a "login:" line, or the entry's last part ("site/name").
password() { head -n 1; }
login() {
    local l
    l=$(grep -m 1 -iE '^(login|user|username|email|e-mail): *' | sed -E 's/^[^:]+: *//')
    if [ -z "$l" ] && [[ "$1" == */* ]]; then l=${1##*/}; fi
    printf '%s' "$l"
}

case "$1" in
status)
    if [ -f "$store/.gpg-id" ]; then echo ready; else echo nokey; fi ;;
list)
    [ -d "$store" ] || exit 0
    cd "$store" && find . -name '*.gpg' -printf '%P\n' | sed 's/\.gpg$//' | sort ;;
setup)
    if [ "$2" = login ]; then
        phrase=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)
        remember "$phrase" || exit 1
    else
        IFS= read -r phrase || exit 1
    fi
    [ -n "$phrase" ] || exit 1
    name=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)
    uid="${name:-$USER} <$USER@$(cat /etc/hostname 2>/dev/null || echo vyntaris)>"
    printf '%s' "$phrase" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 \
        --quick-gen-key "$uid (passwords)" ed25519 cert,sign never || exit 1
    fpr=$(gpg --with-colons --list-secret-keys "$uid (passwords)" | awk -F: '/^fpr/ { print $10; exit }')
    printf '%s' "$phrase" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 \
        --quick-add-key "$fpr" cv25519 encr never || exit 1
    pass init "$fpr" >/dev/null || exit 1
    # Asked again after 30 minutes unused, and at the latest after 8 hours.
    conf="${GNUPGHOME:-$HOME/.gnupg}/gpg-agent.conf"
    grep -q '^default-cache-ttl' "$conf" 2>/dev/null || printf 'default-cache-ttl 1800\nmax-cache-ttl 28800\n' >>"$conf"
    gpg-connect-agent reloadagent /bye >/dev/null 2>&1 ;;
unlock)
    IFS= read -r phrase || exit 1
    any=$(cd "$store" 2>/dev/null && find . -name '*.gpg' -print -quit)
    if [ -z "$any" ]; then
        # Nothing to open yet: check the passphrase against the key itself.
        fpr=$(head -n 1 "$store/.gpg-id")
        printf 'x' | gpg --batch --pinentry-mode loopback --passphrase-fd 3 -u "$fpr" -s -o /dev/null 3<<<"$phrase" 2>/dev/null || exit 2
    else
        gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 0 -d "$store/$any" >/dev/null 2>&1 <<<"$phrase" || exit 2
    fi
    [ "$2" = remember ] && remember "$phrase"
    exit 0 ;;
lock)
    gpg-connect-agent reloadagent /bye >/dev/null 2>&1 ;;
kept)
    secret-tool lookup "${keyring[@]}" >/dev/null 2>&1 ;;
master)
    IFS= read -r new || exit 1
    [ -n "$new" ] || exit 1
    old=$(secret-tool lookup "${keyring[@]}" 2>/dev/null)
    [ -n "$old" ] || exit 1
    fpr=$(head -n 1 "$store/.gpg-id")
    printf '%s\n%s\n' "$old" "$new" | gpg --batch --pinentry-mode loopback --command-fd 0 --passwd "$fpr" 2>/dev/null
    # Out of the keyring only once the new one opens the key.
    gpg-connect-agent reloadagent /bye >/dev/null 2>&1
    printf 'x' | gpg --batch --pinentry-mode loopback --passphrase-fd 3 -u "$fpr" -s -o /dev/null 3<<<"$new" 2>/dev/null || exit 1
    secret-tool clear "${keyring[@]}"
    gpg-connect-agent reloadagent /bye >/dev/null 2>&1 ;;
forget)
    secret-tool clear "${keyring[@]}" ;;
show)
    decrypt "$2" ;;
fill)
    entry=$(decrypt "$2") || exit $?
    user=$(login "$2" <<<"$entry")
    # The island goes first, so the field has the focus again.
    sleep 0.35
    if U="$user" P="$(password <<<"$entry")" python3 -c \
        'import json, os; print(json.dumps({"user": os.environ["U"], "password": os.environ["P"]}))' \
        | "$(dirname "$0")/pass-host.py" fill; then
        exit 0
    fi
    # Not known to be a password field: never typed.
    [ "$3" = page ] && exit 6
    if [ "$3" = here ]; then
        printf '%s' "$user" | wtype -
        wtype -k Tab
    elif [ "$3" = user ]; then
        if [ -n "$user" ]; then
            wtype -M shift -k Tab -m shift
            printf '%s' "$user" | wtype -
            wtype -k Tab
        fi
    fi
    password <<<"$entry" | tr -d '\n' | wtype - ;;
fill-fields)
    entry=$(decrypt "$2") || exit $?
    sleep 0.35
    python3 -c '
import json, sys
d = {}
for line in sys.stdin.read().splitlines()[1:]:
    k, sep, v = line.partition(":")
    if sep and v.strip():
        d[k.strip().lower()] = v.strip()
print(json.dumps({"fields": d}))' <<<"$entry" | "$(dirname "$0")/pass-host.py" fill ;;
copy)
    entry=$(decrypt "$2") || exit $?
    if [ "$3" = login ]; then
        login "$2" <<<"$entry" | wl-copy
    else
        case "$3" in
            field:*) secret=$(grep -m 1 -i "^${3#field:}:" <<<"$entry" | sed -E 's/^[^:]+: *//') ;;
            note) secret=$(tail -n +2 <<<"$entry") ;;
            *) secret=$(password <<<"$entry") ;;
        esac
        printf '%s' "$secret" | wl-copy --sensitive
        (
            sleep 45
            [ "$(wl-paste -n 2>/dev/null)" = "$secret" ] && wl-copy --clear
        ) >/dev/null 2>&1 &
        disown
    fi ;;
check)
    IFS= read -r user
    IFS= read -r secret
    site=${2#www.}
    name="$site"
    [ -n "$user" ] && name="$site/$user"
    [ -d "$store" ] && while IFS= read -r e; do
        # This site's entries: "site", "site/name", "folder/site", or one for its parent domain.
        hit=
        IFS=/ read -ra parts <<<"$e"
        for part in "${parts[@]}"; do
            [ "$part" = "$site" ] || [[ "$site" == *".$part" ]] && hit=1
        done
        [ -n "$hit" ] || continue
        entry=$(open_entry "$e") || { echo locked; exit 0; }
        l=$(login "$e" <<<"$entry")
        if [ -z "$user" ] || [ -z "$l" ] || [ "$l" = "$user" ]; then
            if [ "$(password <<<"$entry")" = "$secret" ]; then echo same; else echo "changed $e"; fi
            exit 0
        fi
    done < <(cd "$store" && find . -name '*.gpg' -printf '%P\n' | sed 's/\.gpg$//')
    while [ -e "$store/$name.gpg" ]; do name="$name-2"; done
    echo "new $name" ;;
save)
    [ -n "$2" ] || exit 1
    pass insert -m -f "$2" >/dev/null ;;
delete)
    pass rm -f "$2" >/dev/null ;;
generate)
    LC_ALL=C tr -dc 'A-Za-z0-9!#%+=?@^_-' </dev/urandom | head -c 20; echo ;;
*)
    exit 1 ;;
esac
