#!/usr/bin/env bash
# The hotspot (scripts/hotspot.sh) against a stand-in NetworkManager, and the firewall letting its devices through.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$REPO/config/quickshell/scripts/hotspot.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "   ok    $*"; }
no() { echo "   FAIL  $*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else no "$what"; fi; }
field() { python3 -I -c 'import json, sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }

mkdir -p "$T/bin" "$T/cons"
: > "$T/active"
# nmcli as far as hotspot.sh uses it: connections are files of key=value lines
cat > "$T/bin/nmcli" <<'PY'
#!/usr/bin/env python3
import os, sys
T = os.environ["FAKE_NM"]
a = sys.argv[1:]
cons, active = os.path.join(T, "cons"), os.path.join(T, "active")
key = lambda k: k.replace("wifi-sec.", "802-11-wireless-security.")
def load(n):
    return dict(l.rstrip("\n").split("=", 1) for l in open(os.path.join(cons, n)) if "=" in l)
def save(n, d):
    open(os.path.join(cons, n), "w").write("".join(f"{k}={v}\n" for k, v in d.items()))
def names(): return sorted(os.listdir(cons))
def on(): return [l.strip() for l in open(active) if l.strip()]
if a[:4] == ["-t", "-f", "DEVICE,TYPE", "dev"]:
    print("eth0:ethernet")
    if os.environ.get("FAKE_WIFI"): print(os.environ["FAKE_WIFI"] + ":wifi")
elif a[:5] == ["-t", "-f", "NAME", "con", "show"]:
    print("\n".join(on() if "--active" in a else names()))
elif a[:2] == ["con", "add"]:
    i = a.index("con-name"); n = a[i + 1]
    d = {"connection.interface-name": a[a.index("ifname") + 1], "802-11-wireless.ssid": a[a.index("ssid") + 1]}
    rest = a[2:]
    for j in range(0, len(rest) - 1):
        if "." in rest[j]: d[key(rest[j])] = rest[j + 1]
    save(n, d)
elif a[:2] == ["con", "modify"]:
    n = a[2]; d = load(n)
    for j in range(3, len(a) - 1, 2): d[key(a[j])] = a[j + 1]
    save(n, d)
elif a[:2] == ["con", "up"]:
    if os.environ.get("FAKE_UP_FAILS"): sys.exit(4)
    open(active, "a").write(a[2] + "\n"); open(os.path.join(T, "ups"), "a").write(a[2] + "\n")
elif a[:2] == ["con", "down"]:
    open(active, "w").write("".join(n + "\n" for n in on() if n != a[2]))
elif "-g" in a and a[-3:-1] == ["con", "show"]:
    print(load(a[-1]).get(a[a.index("-g") + 1], ""))
PY
cat > "$T/bin/ip" <<'SH'
#!/bin/sh
case "$*" in
    "route show default") [ -n "${FAKE_ROUTE:-}" ] && echo "default via 192.168.1.1 dev $FAKE_ROUTE proto dhcp" ;;
    neigh*) printf '10.42.0.10 lladdr aa:bb lladdr\n10.42.0.11 lladdr cc:dd\n' ;;
esac
SH
chmod 755 "$T/bin/"*
export PATH="$T/bin:$PATH" FAKE_NM="$T"
host="$(cat /etc/hostname 2>/dev/null || echo Vyntaris)"

echo ":: before it's ever on"
s="$(FAKE_WIFI='' "$H" status)"
check "no Wi-Fi card: no device"              test "$(field "$s" device)" = ""
check "on without a card: refused (2)"        bash -c 'FAKE_WIFI= "$0" on; [ $? = 2 ]' "$H"
s="$(FAKE_WIFI=wlan0 "$H" status)"
check "a card: named"                         test "$(field "$s" device)" = wlan0
check "not made yet"                          test "$(field "$s" exists)" = False
check "its name would be the computer's"      test "$(field "$s" ssid)" = "$host"

echo ":: turned on"
FAKE_WIFI=wlan0 "$H" on
check "a connection made"                     test -f "$T/cons/Vyntaris hotspot"
check "… an access point"                     grep -qx '802-11-wireless.mode=ap' "$T/cons/Vyntaris hotspot"
check "… sharing this computer's internet"    grep -qx 'ipv4.method=shared' "$T/cons/Vyntaris hotspot"
check "… WPA2 (RSN, CCMP)"                    grep -qx '802-11-wireless-security.proto=rsn' "$T/cons/Vyntaris hotspot"
check "… on the Wi-Fi card"                   grep -qx 'connection.interface-name=wlan0' "$T/cons/Vyntaris hotspot"
psk="$(sed -n 's/^802-11-wireless-security.psk=//p' "$T/cons/Vyntaris hotspot")"
check "a password of 12, easy to type (no l, 1, 0, o)" bash -c '[[ "$0" =~ ^[a-km-z2-9]{12}$ ]]' "$psk"
check "started"                               grep -qx "Vyntaris hotspot" "$T/active"
s="$(FAKE_WIFI=wlan0 "$H" status)"
check "status: on, with its password"         test "$(field "$s" active)" = True -a "$(field "$s" password)" = "$psk"
check "status: the devices that joined"       test "$(field "$s" clients)" = 2
FAKE_WIFI=wlan0 "$H" on
check "on again: the same connection, password kept" test "$(sed -n 's/^802-11-wireless-security.psk=//p' "$T/cons/Vyntaris hotspot")" = "$psk"

echo ":: a new name and password"
printf 'Kafa\nnovalozinka\n' | FAKE_WIFI=wlan0 "$H" set
check "both changed"                          grep -qx '802-11-wireless.ssid=Kafa' "$T/cons/Vyntaris hotspot"
check "… the password too"                    grep -qx '802-11-wireless-security.psk=novalozinka' "$T/cons/Vyntaris hotspot"
check "… applied at once while it's on"       test "$(grep -c . "$T/ups")" -ge 3
check "a password under 8: refused"           bash -c '! printf "Kafa\nkratka\n" | FAKE_WIFI=wlan0 "$0" set' "$H"
check "… and nothing changed"                 grep -qx '802-11-wireless-security.psk=novalozinka' "$T/cons/Vyntaris hotspot"

echo ":: off, and where the internet comes from"
FAKE_WIFI=wlan0 "$H" off
check "off"                                   bash -c '! grep -q . "$0"' "$T/active"
s="$(FAKE_WIFI=wlan0 FAKE_ROUTE=wlan0 "$H" status)"
check "internet over the same card: can't share" test "$(field "$s" viaWifi)" = True -a "$(field "$s" otherInternet)" = False
s="$(FAKE_WIFI=wlan0 FAKE_ROUTE=eth0 "$H" status)"
check "internet over the cable: can"          test "$(field "$s" viaWifi)" = False -a "$(field "$s" otherInternet)" = True
check "NetworkManager refuses it: an error"   bash -c '! FAKE_WIFI=wlan0 FAKE_UP_FAILS=1 "$0" on' "$H"

echo ":: what it needs from the package and the firewall"
check "dnsmasq is a dependency (NetworkManager shares through it)" grep -qE '^\s.*\bdnsmasq\b' "$REPO/pkg/PKGBUILD"
check "the firewall answers its devices' DHCP and DNS" grep -qE 'ip saddr 10\.42\.0\.0/16 .*th dport \{ 53, 67 \} accept' "$REPO/system/nftables.conf"
check "… and forwards them out"               grep -qE 'ip saddr 10\.42\.0\.0/16 accept' "$REPO/system/nftables.conf"
if command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    check "nftables.conf is valid"            unshare -rn nft -c -f "$REPO/system/nftables.conf"
fi

echo
[ "$fails" = 0 ] && echo "hotspot: all checks passed" || echo "hotspot: $fails failed"
exit $((fails > 0))
