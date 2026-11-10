#!/bin/bash
# The island's passwords, kept by pass (passwordstore.org): GPG-encrypted files in ~/.password-store.
#   status                 ready | nokey
#   list                   every entry
#   setup                  a new key and store; the passphrase on stdin
#   unlock                 the passphrase on stdin; gpg-agent keeps it for a while
#   lock                   forget it now
#   show NAME              the entry (exit 5: locked)
#   fill NAME [user|here]  into the field with the focus: through Firefox's extension, else typed (the
#                          password; the username, Tab, the password from the password field (user) or
#                          from the username field (here))
#   fill-fields NAME       personal info or a card ("key: value" lines) into the form with the focus, through Firefox's extension
#   check SITE             a login (username and password lines on stdin): same | changed NAME | new NAME | locked
#   copy NAME [login|field:KEY|note]   to the clipboard (the password, the username, a "KEY:" line, a note's text),
#                          cleared after 45 s
#   save NAME              the entry on stdin
#   delete NAME
#   generate               a new password
store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

decrypt() {
    [ -f "$store/$1.gpg" ] || exit 1
    local err
    err=$(mktemp) || exit 1
    if gpg --quiet --batch --pinentry-mode error -d "$store/$1.gpg" 2>"$err"; then
        rm -f "$err"
        return
    fi
    rm -f "$err"
    exit 5
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
    IFS= read -r phrase || exit 1
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
        exit 0
    fi
    gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 0 -d "$store/$any" >/dev/null 2>&1 <<<"$phrase" || exit 2 ;;
lock)
    gpg-connect-agent reloadagent /bye >/dev/null 2>&1 ;;
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
        entry=$(gpg --quiet --batch --pinentry-mode error -d "$store/$e.gpg" 2>/dev/null) || { echo locked; exit 0; }
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
