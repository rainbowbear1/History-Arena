# Deploying the web build

The build is static files (`index.html`, `.js`, `.wasm`, `.pck`, `hub-bridge.js`), about 40 MB
(the engine `.wasm` is ~38 MB; game data ~1.8 MB). Threads are disabled, so no COOP/COEP headers
are needed and any static HTTPS host works.

## Build
```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd     # must end with "0 failed"
tools/export_web.sh <path-to-godot-4.7.2> build/web
```
`build/` is git-ignored. Check that `build/web/hub-bridge.js` exists.

## Where to host (pick one, agree with the Hub team)
1. **On the Game Hub's domain (recommended):** e.g. `https://<hub-domain>/games/history-arena/`.
   The Hub session is then shared automatically and the Hub team controls `hub-bridge.js`.
2. **GitHub Pages:** put the contents of `build/web/` in a `gh-pages` branch (or a separate repository)
   and enable Pages. Ask the Hub team to add the Pages domain to the authorised OAuth domains.
3. **itch.io:** upload `build/web` as a zip, "This file will be played in the browser". Google sign-in
   inside itch.io's iframe is not recommended; use options 1 or 2 for the defense.

Google OAuth requires **HTTPS** and an **authorised domain**; plain `http://localhost` works only for
local testing.

## Connecting the Game Hub
Replace `build/web/hub-bridge.js` (or `web/hub-bridge.js` before exporting) with the Hub team's
implementation of the contract in `docs/hub-integration.md`. Never deploy `tests/web/hub-bridge.mock.js`.

## Pre-defense checklist
- [ ] Tests pass (`0 failed`) on the commit you deploy; note the commit hash.
- [ ] Fresh export uploaded; old files replaced (hard-refresh with Ctrl+F5 to avoid cached `.pck`).
- [ ] Opens in Chrome and Edge without console errors; login screen appears.
- [ ] Guest play → level 1 → a correct and a wrong answer → results screen.
- [ ] Settings → Демо режимі opens all levels; Авторлар shows the image credits.
- [ ] If the Hub bridge is connected: sign in, finish a level, see the result on the Hub leaderboard.
- [ ] Repository pushed (by you) with README, docs and tests; no secrets in it.
