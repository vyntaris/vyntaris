#!/usr/bin/env bash
set -euo pipefail
out="$1"; flavor="${2:-mocha}"; accent="${3:-blue}"
mkdir -p "$out"

L=176
"${SPLASH_RENDER:-/usr/lib/vyntaris/splash-render}" "$out" "$flavor" "$accent" "$L"

cat > "$out/island.plymouth" <<PLY
[Plymouth Theme]
Name=Island
Description=The Vyntaris mark arriving out of warp, its planet going round the orbit ($flavor, $accent)
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/island
ScriptFile=/usr/share/plymouth/themes/island/island.script
PLY

echo "theme written to $out ($flavor / $accent)"
