#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then echo "   ok    $what"; else echo "   FAIL  $what"; fails=$((fails + 1)); fi; }

mkdir -p "$T/bin" "$T/run"
cat > "$T/bin/Hyprland" <<'EOF'
#!/bin/sh
n=$(head -n1 "$CODES"); sed -i 1d "$CODES"
echo "$n ${VYNTARIS_RECOVERED:-0}" >> "$RUNS"
case "$n" in
    hang) trap 'exit 143' TERM; while :; do sleep 0.1; done ;;
    leave) touch "$XDG_RUNTIME_DIR/vyntaris-leaving"; exit 1 ;;
esac
exit "$n"
EOF
chmod +x "$T/bin/Hyprland"
printf '#!/bin/sh\necho "$*" >> "$SYSTEMCTL"\n[ "$1" = is-system-running ] && echo running\nexit 0\n' > "$T/bin/systemctl"
chmod +x "$T/bin/systemctl"
export SYSTEMCTL="$T/systemctl.log"

session() {
    printf '%s\n' "$@" > "$T/codes"; : > "$T/runs"; rm -f "$T/run/vyntaris-leaving"
    HOME="$T" XDG_STATE_HOME="$T/state" XDG_RUNTIME_DIR="$T/run" CODES="$T/codes" RUNS="$T/runs" \
        PATH="$T/bin:$PATH" timeout 20 sh "$REPO/system/bin/vyntaris-session"
}
runs() { wc -l < "$T/runs"; }

echo ":: the session"
session 0; rc=$?
check "logging out ends it"                         test "$rc" = 0 -a "$(runs)" = 1
session 139 0; rc=$?
check "a crash starts it again"                     test "$rc" = 0 -a "$(runs)" = 2
check "… and the new one knows (VYNTARIS_RECOVERED)" test "$(sed -n 2p "$T/runs")" = "0 1"
check "… once what the old one started is stopped"   grep -q "stop vyntaris-session.target" "$SYSTEMCTL"
session 139 6 0; rc=$?
check "two crashes, then fine"                      test "$rc" = 0 -a "$(runs)" = 3
session 139 139 139 0; rc=$?
check "three in five minutes: the login screen"     test "$rc" = 1 -a "$(runs)" = 3
check "… and the log says so"                       grep -q "crashed 3 times" "$T/state/vyntaris/session.log"
session leave 0; rc=$?
check "the power menu's log out or shutdown: not again" test "$(runs)" = 1

printf 'hang\n0\n' > "$T/codes"; : > "$T/runs"
HOME="$T" XDG_STATE_HOME="$T/state" XDG_RUNTIME_DIR="$T/run" CODES="$T/codes" RUNS="$T/runs" \
    PATH="$T/bin:$PATH" sh "$REPO/system/bin/vyntaris-session" &
pid=$!
for _ in $(seq 50); do [ -s "$T/runs" ] && break; sleep 0.1; done
kill -TERM "$pid"
for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
check "asked to end (logind, shutdown): ends, and Hyprland with it" bash -c "! kill -0 $pid && ! pgrep -f '^/bin/sh $T/bin/Hyprland'"
check "… not started again"                         test "$(runs)" = 1
kill -9 "$pid" 2>/dev/null

[ "$fails" -eq 0 ] && echo ":: all fine" || { echo ":: $fails failed"; exit 1; }
