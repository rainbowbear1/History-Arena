#!/usr/bin/env bash
# Exports the web build and adds the online bridge (Firebase) next to index.html.
# Usage: tools/export_web.sh <path-to-godot-console-exe> [output-dir]   (default: build/web)
set -euo pipefail

GODOT="${1:?path to the Godot 4.7.2 executable}"
OUT="${2:-build/web}"

mkdir -p "$OUT"
[ -e build/.gdignore ] || : > build/.gdignore
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html"
cp web/firebase-config.js web/firebase-bridge.js "$OUT/"
: > "$OUT/.nojekyll"  # GitHub Pages: serve the files as they are.
if ! grep -q 'apiKey: "[^"]' "$OUT/firebase-config.js"; then
  echo "Note: web/firebase-config.js is empty, so this build runs offline (guest play only)."
fi
echo "Exported to $OUT"
