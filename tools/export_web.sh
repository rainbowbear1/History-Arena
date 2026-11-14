#!/usr/bin/env bash
# Exports the web build and adds the Game Hub bridge next to index.html.
# Usage: tools/export_web.sh <path-to-godot-console-exe> [output-dir]   (default: build/web)
set -euo pipefail

GODOT="${1:?path to the Godot 4.7.2 executable}"
OUT="${2:-build/web}"

mkdir -p "$OUT"
[ -e build/.gdignore ] || : > build/.gdignore
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html"
cp web/hub-bridge.js "$OUT/hub-bridge.js"
echo "Exported to $OUT (bridge: web/hub-bridge.js)"
