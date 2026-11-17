# Deploying History Arena (Firebase + GitHub Pages)

The web build is static files (`index.html`, `index.js`, `index.wasm` ~38 MB, `index.pck` ~1.8 MB,
`firebase-config.js`, `firebase-bridge.js`). Threads are off, so GitHub Pages needs no special
headers. All paths are relative, so the game works under `https://<user>.github.io/<repo>/`.

## 1. Firebase project (once, in the Firebase Console)
1. <https://console.firebase.google.com> → **Create a project** (e.g. `history-arena`). Google
   Analytics is not needed. The free **Spark** plan is enough.
2. **Build → Authentication → Get started → Sign-in method → Google → Enable.** Choose the project
   support e-mail → Save.
3. **Authentication → Settings → Authorized domains → Add domain:** `<user>.github.io`
   (`localhost` is already there).
4. **Build → Firestore Database → Create database** → *Production mode* → a location near the players
   (e.g. `europe-west1` or `asia-south1`; it cannot be changed later).
5. **Firestore → Rules:** replace the text with the contents of `firestore.rules` → **Publish**.
   (Or with the Firebase CLI: `firebase login`, then
   `firebase deploy --only firestore:rules --project <project-id>`.)
6. **Project settings (gear) → General → Your apps → Web (`</>`)** → nickname `history-arena-web`,
   no Hosting → Register. Copy the `firebaseConfig` values into `web/firebase-config.js`
   (`apiKey`, `authDomain`, `projectId`, `appId`). They are public; see `docs/online.md`.

## 2. Build
```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd     # must end with "0 failed"
(cd tests/firebase && npm install && npm test)                  # security rules, all pass
tools/export_web.sh <path-to-godot-4.7.2> build/web
```

## 3. GitHub Pages
1. Create an empty GitHub repository (e.g. `history-arena`) and add it as `origin`.
2. `tools/publish_pages.sh` puts `build/web` on a local `gh-pages` branch (one commit, replaced on
   every release). It refuses to publish without a filled-in Firebase config.
3. Push (only when you approve): `git push -u origin main` and `git push --force origin gh-pages`.
4. GitHub → repository **Settings → Pages → Build and deployment → Deploy from a branch →
   `gh-pages` / `(root)`** → Save. After a minute the game is at `https://<user>.github.io/<repo>/`.

## 4. Check the deployed site
Already verified locally (17 Nov 2026) against the Firebase emulators in a browser: session restore
after reload, a result stored under the player's UID, best score and total read back, the
leaderboard screen showing the stored row, a second write within 5 s refused by the rules, and
sign-out surviving a reload. The Google pop-up itself can only be checked on the real project:
- [ ] Opens in Chrome and Edge over HTTPS; the login screen shows an active **Google арқылы кіру**.
- [ ] Sign in with a real Google account; the menu shows your Google name.
- [ ] Reload the page (F5): you go straight to the menu, still signed in.
- [ ] Finish a level (Settings → Демо режимі helps); results say «Нәтиже онлайн рейтингке жіберілді».
- [ ] **Рейтинг** lists you with your total and rank; Firestore → `players` has your row.
- [ ] Sign in with a second Google account (other browser or a private window): both appear in the
      leaderboard; each sees only their own progress.
- [ ] **Шығу** (Sign out), reload: the login screen appears; guest play works and is not uploaded.
- [ ] If sign-in says the domain is not authorised, re-check step 1.3. If the popup is blocked,
      allow pop-ups for the site.
- [ ] Hard-refresh (Ctrl+F5) after every new release so the old `.pck` is not cached.
