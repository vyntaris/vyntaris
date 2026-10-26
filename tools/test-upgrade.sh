#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO/config/quickshell/scripts"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then echo "   ok    $what"; else echo "   FAIL  $what"; fails=$((fails + 1)); fi; }

mkdir -p "$T/bin" "$T/run"
cat > "$T/bin/pkexec" <<'EOF'
#!/bin/sh
echo "pkexec $*" >> "$CALLS"
[ -n "${PKEXEC:-}" ] && exit "$PKEXEC"
exec "$@"
EOF
cat > "$T/bin/pacman" <<'EOF'
#!/bin/sh
echo "pacman $*" >> "$CALLS"
case "$1" in
    -Syu) [ "${SYU:-0}" = 0 ] || { echo "error: failed to commit transaction (conflicting files)"; exit 1; } ;;
    -Q|-Qq) grep -qx "$2" "$INSTALLED" ;;
    -S) shift; for p; do case "$p" in -*) ;; *) echo "$p" >> "$INSTALLED" ;; esac; done ;;
esac
EOF
cat > "$T/bin/yay" <<'EOF'
#!/bin/sh
echo "yay $*" >> "$CALLS"
case "$1" in
    -Qua) [ -n "${AURUP:-}" ] && echo "$AURUP 1 -> 2"; exit 0 ;;
    -Sua) [ "${BUILD:-0}" = 0 ] ;;
    -S) [ "${BUILD:-0}" = 0 ] || exit 1; for p; do case "$p" in -*|None|pkexec) ;; *) echo "$p" >> "$INSTALLED" ;; esac; done ;;
esac
EOF
printf '#!/bin/sh\necho "notify $*" >> "$CALLS"\n' > "$T/bin/notify-send"
chmod +x "$T"/bin/*
export CALLS="$T/calls" INSTALLED="$T/installed" XDG_RUNTIME_DIR="$T/run" PATH="$T/bin:$PATH"

up() { : > "$CALLS"; printf 'base\n' > "$INSTALLED"; env "$@" sh "$SCRIPTS/upgrade.sh" yay; cat "$T/run/vyntaris-upgrade/result" 2>/dev/null; }
echo ":: updating"
check "done: ok, and said"                         test "$(up)" = ok -a -n "$(grep '^notify .*Up to date' "$CALLS")"
check "… through pkexec, not sudo in a terminal"   grep -q '^pkexec pacman -Syu --noconfirm' "$CALLS"
check "… the AUR not built when nothing changed"   bash -c "! grep -q '^yay -Sua' '$CALLS'"
check "the password dialog closed: cancelled"      test "$(up PKEXEC=126)" = cancelled
check "… and nothing said"                         bash -c "! grep -q '^notify' '$CALLS'"
check "pacman fails: failed"                       test "$(up SYU=1)" = failed
check "… said, with pacman's reason"               grep -q '^notify .*conflicting files' "$CALLS"
check "AUR updates: the build tools first"         test "$(up AURUP=foo)" = ok -a -n "$(grep '^pacman -S --needed --noconfirm base-devel' "$CALLS")"
check "… then built, installing through pkexec"    grep -q '^yay -Sua .*--sudo pkexec' "$CALLS"
check "an AUR build that fails: failed"            test "$(up AURUP=foo BUILD=1)" = failed

aur() { : > "$CALLS"; printf 'base\n%s' "${PRE:-}" > "$INSTALLED"; env "$@" sh "$SCRIPTS/aur-install.sh" yay "$PKG"; cat "$T/run/vyntaris-aur/$PKG" 2>/dev/null; }
echo ":: an app from the AUR"
check "built and installed: ok"                    test "$(PKG=foo-bin aur)" = ok
check "… the build tools brought in first"         grep -q '^pacman -S --needed --noconfirm base-devel' "$CALLS"
check "… never in a terminal, never asked about diffs" grep -q '^yay -S --noconfirm --answerclean None --answerdiff None --answeredit None' "$CALLS"
PRE=$'base-devel\n' PKG=foo-bin aur >/dev/null
check "build tools already there: not again"       bash -c "! grep -q '^pacman -S .*base-devel' '$CALLS'"
check "the build fails: failed"                    test "$(PKG=foo-bin aur BUILD=1)" = failed
check "the dialog closed for the tools: cancelled" test "$(PKG=foo-bin aur PKEXEC=126)" = cancelled
check "a name that isn't a package's: nothing run" test "$(PKG='foo;rm' aur)" = failed -a ! -s "$CALLS"

[ "$fails" -eq 0 ] && echo ":: all fine" || { echo ":: $fails failed"; exit 1; }
