#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
bad=0
shells=() pythons=()
for f in install.sh iso/build.sh iso/airootfs/usr/local/bin/* system/*.sh system/bin/* system/prime-run \
         system/plymouth/*.sh system/bluetooth/* system/update-guard/*.sh system/update-guard/initcpio-* system/gaming/*.sh config/quickshell/scripts/*.sh tools/*.sh; do
    [ -f "$f" ] || continue
    case "$(head -1 "$f")" in
        *python*) pythons+=("$f") ;;
        *) shells+=("$f") ;;
    esac
done
pythons+=(system/lib/*.py tools/*.py config/quickshell/scripts/*.py)
packaging=(pkg/PKGBUILD pkg/vyntaris.install)

for f in "${shells[@]}" "${packaging[@]}"; do bash -n "$f" || bad=1; done
shellcheck -S warning "${shells[@]}" || bad=1
shellcheck -S warning -s bash -e SC2034,SC2154 "${packaging[@]}" || bad=1
python3 -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' "${pythons[@]}" || bad=1
pyflakes "${pythons[@]}" || bad=1
tools/check-contrast.py || bad=1
tools/check-controls.py || bad=1

[ "$bad" = 0 ] && echo "$(( ${#shells[@]} + ${#packaging[@]} )) shell scripts and ${#pythons[@]} Python files: clean"
exit "$bad"
