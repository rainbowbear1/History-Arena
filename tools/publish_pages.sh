#!/usr/bin/env bash
# Puts an exported web build on the local `gh-pages` branch as a single commit, ready for GitHub
# Pages ("Deploy from a branch" -> gh-pages, / (root)). Nothing is pushed: the script prints the
# push command for you to run.
# Usage: tools/export_web.sh <godot> build/web && tools/publish_pages.sh [build-dir]   (default: build/web)
set -euo pipefail

BUILD="${1:-build/web}"
PAGES="build/pages"

[ -f "$BUILD/index.html" ] || { echo "No export in $BUILD; run tools/export_web.sh first." >&2; exit 1; }
if ! grep -q 'apiKey: "[^"]' "$BUILD/firebase-config.js"; then
  echo "web/firebase-config.js is empty: the published game would have no Google sign-in." >&2
  exit 1
fi

SOURCE="$(git rev-parse --short HEAD)"
git worktree remove --force "$PAGES" 2>/dev/null || true
rm -rf "$PAGES"
# A fresh orphan branch each time: the site keeps one commit, so the repository does not grow by
# ~40 MB per release. (Publishing replaces the previous gh-pages commit; push with --force.)
git worktree add --detach "$PAGES" >/dev/null
git -C "$PAGES" checkout --orphan gh-pages-new >/dev/null 2>&1
git -C "$PAGES" rm -rf -q . >/dev/null 2>&1 || true
cp -r "$BUILD"/. "$PAGES"/
echo "* -text" > "$PAGES/.gitattributes"  # Publish the exported bytes exactly (no line-ending changes).
git -C "$PAGES" add -A
git -C "$PAGES" commit -q -m "Web build of $SOURCE"
git branch -f gh-pages "$(git -C "$PAGES" rev-parse HEAD)"
git worktree remove --force "$PAGES"
git branch -D gh-pages-new >/dev/null 2>&1 || true

echo "gh-pages now holds the web build of $SOURCE. To publish (after you approve):"
echo "  git push --force origin gh-pages"
