#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[ -z "$(git tag --points-at HEAD -l 'v*')" ] || exit 0
latest="$(git tag -l 'v*' --sort=-v:refname | head -1)"
latest="${latest#v}"
file="$(cat VERSION)"
if [ -z "$latest" ] || { [ "$file" != "$latest" ] && [ "$(printf '%s\n%s\n' "$file" "$latest" | sort -V | tail -1)" = "$file" ]; }; then
    echo "$file"
else
    IFS=. read -r major minor patch <<< "$latest"
    echo "$major.$minor.$((patch + 1))"
fi
