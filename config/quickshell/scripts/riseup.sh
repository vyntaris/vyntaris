#!/bin/sh
dir="${XDG_CACHE_HOME:-$HOME/.cache}/vyntaris/riseup"
json="${VYNTARIS_JSON:-/usr/lib/vyntaris/json}"
api=https://api.black.riseup.net/3
T() { "$json" tr "$@" 2>/dev/null || printf '%s' "$1"; }

umask 077
mkdir -p "$dir"
fetch() {
    [ -s "$dir/$1" ] && [ -z "$(find "$dir/$1" -mmin +"$2")" ] && return 0
    if curl -fsS --max-time 20 -o "$dir/$1.new" "$3"; then mv "$dir/$1.new" "$dir/$1"; else rm -f "$dir/$1.new"; [ -s "$dir/$1" ]; fi
}

case "${1:-}" in
    places)
        fetch eip.json 1440 "$api/config/eip-service.json" || { T "Riseup can't be reached." >&2; exit 1; }
        "$json" riseup-places "$dir/eip.json"
        ;;
    connect)
        place="${2:?}"
        { fetch eip.json 1440 "$api/config/eip-service.json" && fetch ca.crt 43200 https://black.riseup.net/ca.crt \
            && fetch cert.pem 10080 "$api/cert"; } || { T "Riseup can't be reached." >&2; exit 1; }
        "$json" riseup-ovpn "$dir/eip.json" "$dir/cert.pem" "$dir/ca.crt" "$place" > "$dir/riseup.ovpn" \
            || { rm -f "$dir/riseup.ovpn"; T "Riseup has no server in {0} now." "$place" >&2; exit 1; }
        nmcli -t -f UUID,NAME connection show | while IFS=: read -r uuid name; do
            case "$name" in "Riseup · "*) nmcli connection delete "$uuid" >/dev/null ;; esac
        done
        out="$(nmcli connection import type openvpn file "$dir/riseup.ovpn" 2>&1)"
        code=$?
        rm -f "$dir/riseup.ovpn"
        [ "$code" -eq 0 ] || { printf '%s\n' "$out" >&2; exit 1; }
        uuid="$(printf '%s' "$out" | sed -n 's/.*(\([0-9a-f-]\{36\}\)).*/\1/p')"
        nmcli connection modify "$uuid" connection.id "Riseup · $place" connection.autoconnect no
        nmcli connection up "$uuid" >/dev/null
        ;;
    *)
        echo "riseup.sh places | connect NAME" >&2
        exit 2
        ;;
esac
