# Deploying History Arena (Firebase + GitHub Pages)

**This project:** Firebase `history-arena-709c8`; GitHub repository
<https://github.com/rainbowbear1/History-Arena> (remote `origin`, added 18 Nov 2026, nothing pushed
yet); planned site <https://rainbowbear1.github.io/History-Arena/> and teacher dashboard
<https://rainbowbear1.github.io/History-Arena/admin.html>.

The web build is static files (`index.html`, `index.js`, `index.wasm` ~38 MB, `index.pck` ~1.8 MB,
`firebase-config.js`, `firebase-bridge.js`, `admin.html`, `fonts/`). Threads are off, so GitHub Pages
needs no special headers. Every path in the build is relative (checked: `index.html` and
`admin.html` reference only `index.js`, `firebase-*.js`, `fonts/…`), so it works under the
`/History-Arena/` sub-path. Firebase sign-in does not depend on the path, only on the domain being
in **Authorized domains**.

## 1. Firebase project (done once; steps kept for reference)
1. <https://console.firebase.google.com> → **Create a project**. The free **Spark** plan is enough;
   no Cloud Functions or other paid services are used.
2. **Build → Authentication → Sign-in method → Google → Enable.**
3. **Authentication → Settings → Authorized domains → Add domain:** `rainbowbear1.github.io`
   (only the domain, without `/History-Arena`). Present already: `localhost`,
   `history-arena-709c8.firebaseapp.com`, `history-arena-709c8.web.app`.
4. **Build → Firestore Database → Create database** → *Production mode*.
5. **Firestore → Rules:** replace the text with the contents of `firestore.rules` → **Publish**.
   (Or with the Firebase CLI: `firebase login`, then
   `firebase deploy --only firestore:rules --project history-arena-709c8`.)
   **The rules in the repository are newer than the published ones** (BOSS runs and trophies,
   All-in-One, profiles, administrators, runs left early). Publish them together with the new game
   build, after the emulator tests pass; until then the live rules refuse the new kinds of records
   (the game keeps them queued and sends them later).
6. **Project settings → Your apps → Web** → copy `apiKey`, `authDomain`, `projectId`, `appId` into
   `web/firebase-config.js` (done; they are public, see `docs/online.md`).
7. No Firestore index needs to be created: every query uses a single field (`total`, `key`,
   `trophy`) or reads a whole collection / collection group.

## 2. Build
```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd     # must end with "0 failed"
(cd tests/firebase && npm install && npm test)                  # security rules, all pass
tools/export_web.sh <path-to-godot-4.7.2-console> build/web
```

## 3. GitHub Pages (only after your approval)
1. `origin` is already `https://github.com/rainbowbear1/History-Arena.git`.
2. `tools/publish_pages.sh` puts `build/web` on a local `gh-pages` branch (one commit, replaced on
   every release). It refuses to publish without a filled-in Firebase config.
3. Push:
   ```
   git push -u origin main
   git push origin --tags
   git push --force origin gh-pages
   ```
   Note: every commit's author e-mail becomes public on GitHub. To hide it, the history would have to
   be rewritten to a GitHub `noreply` address *before* the first push (a separate decision).
4. GitHub → repository **Settings → Pages → Build and deployment → Deploy from a branch →
   `gh-pages` / `(root)`** → Save. After a minute the game is at
   `https://rainbowbear1.github.io/History-Arena/`.

## 4. Check the deployed site
Verified locally (18 Nov 2026) against the Firebase emulators in a browser with the real bridge:
a campaign result, a BOSS victory with its trophy, an All-in-One best, a run left early and a
sign-in record stored; a tampered BOSS trophy refused; both leaderboards and the entitlements read
back with trophies; the teacher dashboard showing a demo class to an administrator and "No access"
plus the UID to anyone else. The Google pop-up itself can only be checked on the real site:
- [ ] Opens in Chrome and Edge over HTTPS; the login screen shows an active **Google арқылы кіру**
      and the notice that progress and activity are recorded.
- [ ] Sign in with a real Google account; the menu shows your Google name.
- [ ] Reload the page (F5): you go straight to the menu, still signed in.
- [ ] Finish a level; results say «Нәтиже онлайн рейтингке жіберілді»; **Рейтинг → Науқан** lists you.
- [ ] Defeat the BOSS: the results show the trophy; it appears beside your name on both boards.
- [ ] Play **Бәрі бірге** (All-in-One) a little and lose or finish: **Рейтинг → Бәрі бірге** lists you.
- [ ] Open `admin.html`, sign in: without an admin record it shows "No access" and your UID; add the
      UID under `admins` (see `docs/online.md`) and reload: the class table appears.
- [ ] **Шығу** (Sign out), reload: the login screen appears; guest play works and is not uploaded.
- [ ] If sign-in says the domain is not authorised, re-check step 1.3. If the popup is blocked,
      allow pop-ups for the site.
- [ ] Hard-refresh (Ctrl+F5) after every new release so the old `.pck` is not cached.
