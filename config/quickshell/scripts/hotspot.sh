#!/bin/bash
# The Wi-Fi hotspot, a NetworkManager connection ("Vyntaris hotspot") sharing this computer's internet.
#   status        one JSON line: the Wi-Fi card, on or not, name, password, devices joined, where the internet comes from
#   on | off
#   set           a new name and password (two lines on stdin), applied at once if it's on
name="Vyntaris hotspot"

card() { nmcli -t -f DEVICE,TYPE dev | awk -F: '$2 == "wifi" { print $1; exit }'; }

# Made the first time: this computer's name, and a password easy to type on a phone.
create() {
    nmcli -t -f NAME con show | grep -qxF "$name" && return
    local ssid psk
    ssid="$(cat /etc/hostname 2>/dev/null || echo Vyntaris)"
    psk=$(LC_ALL=C tr -dc 'a-km-z2-9' </dev/urandom | head -c 12)
    # 2.4 GHz: every phone joins it, and Wi-Fi cards may host there.
    nmcli con add type wifi ifname "$1" con-name "$name" autoconnect no ssid "$ssid" \
        802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared ipv6.method ignore \
        wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp wifi-sec.psk "$psk" \
        >/dev/null
}

json() { python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"; }

case "$1" in
status)
    dev=$(card)
    exists=false; active=false; psk=""; clients=0
    ssid="$(cat /etc/hostname 2>/dev/null || echo Vyntaris)"
    if nmcli -t -f NAME con show | grep -qxF "$name"; then
        exists=true
        ssid=$(nmcli -g 802-11-wireless.ssid con show "$name")
        psk=$(nmcli -s -g 802-11-wireless-security.psk con show "$name" 2>/dev/null)
    fi
    if nmcli -t -f NAME con show --active | grep -qxF "$name"; then
        active=true
        clients=$(ip neigh show dev "$dev" 2>/dev/null | grep -c lladdr)
    fi
    # The internet comes over the card the hotspot needs: sharing it isn't possible.
    up=$(ip route show default | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1) }' | sort -u)
    viaWifi=false
    if [ "$active" = false ] && [ -n "$up" ] && [ "$up" = "$dev" ]; then viaWifi=true; fi
    other=false
    for d in $up; do [ "$d" != "$dev" ] && other=true; done
    printf '{"device": %s, "exists": %s, "active": %s, "ssid": %s, "password": %s, "clients": %s, "viaWifi": %s, "otherInternet": %s}\n' \
        "$(json "$dev")" "$exists" "$active" "$(json "$ssid")" "$(json "$psk")" "$clients" "$viaWifi" "$other" ;;
on)
    dev=$(card)
    [ -n "$dev" ] || exit 2
    create "$dev" || exit 1
    nmcli con modify "$name" connection.interface-name "$dev"
    nmcli con up "$name" >/dev/null ;;
off)
    nmcli con down "$name" >/dev/null 2>&1 ;;
set)
    IFS= read -r ssid
    IFS= read -r psk
    [ -n "$ssid" ] && [ "${#psk}" -ge 8 ] || exit 1
    create "$(card)" || exit 1
    nmcli con modify "$name" 802-11-wireless.ssid "$ssid" wifi-sec.psk "$psk" || exit 1
    if nmcli -t -f NAME con show --active | grep -qxF "$name"; then nmcli con up "$name" >/dev/null; fi ;;
*)
    exit 1 ;;
esac
