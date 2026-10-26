#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
bad=0
while IFS= read -r line; do
    file="${line%%:*}"
    for p in $(grep -oE '\$REPO/[A-Za-z0-9_./@-]+' <<<"$line" | sed 's|^\$REPO/||'); do
        p="${p%/}"
        [[ "$p" == *"*"* ]] && continue
        compgen -G "$p" >/dev/null || compgen -G "$p*" >/dev/null || { echo "missing: $p  (in $file)"; bad=1; }
    done
done < <(grep -n '\$REPO/' install.sh system/*.sh system/plymouth/*.sh iso/build.sh 2>/dev/null)
while IFS= read -r p; do
    compgen -G "$p" >/dev/null || { echo "missing: $p  (in pkg/PKGBUILD)"; bad=1; }
done < <(grep -oE '\$r/[A-Za-z0-9_./*@-]+' pkg/PKGBUILD | sed 's|^\$r/||; s|/$||' | sort -u)
[ $bad = 0 ] && echo "all repository paths exist"
exit $bad
