#!/bin/sh
c="$(pactl -f json list cards 2>/dev/null)" || c="[]"
k="$(pactl -f json list sinks 2>/dev/null)" || k="[]"
s="$(pactl -f json list sources 2>/dev/null)" || s="[]"
printf '{"cards":%s,"sinks":%s,"sources":%s}\n' "${c:-[]}" "${k:-[]}" "${s:-[]}"
