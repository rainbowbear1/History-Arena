# Online features: Google sign-in and the leaderboard

History Arena runs on its own Firebase project: **Firebase Authentication** (Google provider) for
sign-in and **Cloud Firestore** for results and the leaderboard. There is no server of our own and
no secret in the game or the repository. (The shared Game Hub can be reconnected later; see the end
of this page.)

## Architecture
```
 Player's browser (GitHub Pages, HTTPS)                         Google / Firebase
 ┌───────────────────────────────────────────────────────┐
 │ index.html                                            │
 │   firebase-config.js   public web-app identifiers     │
 │   firebase-bridge.js   window.HistoryArenaHub ────────┼──► Firebase Authentication (Google popup)
 │         ▲                Firebase JS SDK 13.1.0 ──────┼──► Cloud Firestore
 │         │ JavaScriptBridge (JSON strings)             │        firestore.rules decide every
 │   Godot: backend.gd ── web_bridge_transport.gd        │        read and write on the server
 │          progress_store.gd (per-account local save)   │
 └───────────────────────────────────────────────────────┘
```
- `backend.gd` (autoload `Backend`): sign-in state, guest mode, session restore, leaderboard, and an
  **outbox** of finished runs (`user://outbox.json`). Each queued run is tagged with the account
  that played it and is only sent while that account is signed in; a failed upload stays queued.
  Guest runs are never uploaded.
- `progress_store.gd`: each Google account has its own progress file on the device
  (`user://progress_<uid>.json`); after sign-in, best scores saved online are merged in, so progress
  follows the player to another computer.
- **Progress is never silently overwritten.** Guest progress stays in the guest file on the device
  and is not changed by signing in; each Google account starts from its own file. Merging online
  results only ever raises a level's best score or stars, never lowers it.
- **Sign-in messages:** closing the Google window says "sign-in cancelled"; a blocked pop-up, an
  unauthorised domain or a network error is named (in Kazakh or English).
- `web_bridge_transport.gd`: calls the bridge and waits for each Promise separately (30 s timeout).
- `web/firebase-bridge.js`: the only code that talks to Firebase. Firebase keeps the session in the
  browser (IndexedDB), so reloading the page keeps the player signed in.

## Bridge contract — `window.HistoryArenaHub`
All values crossing the bridge are JSON strings.

| Member | Returns |
|---|---|
| `configured` | `true` when `firebase-config.js` is filled in |
| `waitForUser()` | Promise → `{"uid","name"}` of a restored session, or `""` |
| `getCurrentUser()` | `{"uid","name"}` or `""` |
| `signInWithGoogle()` | Promise → `{"uid","name"}`; rejects with a message (popup closed/blocked, domain not authorised…) |
| `signOut()` | Promise |
| `submitResult(payloadJson)` | Promise → `{"ok": true, "total": n}` or `{"ok": false, "error"}` |
| `getMyProgress()` | Promise → `{"ok", "levels": {"1": {"score","stars"}, …}, "total"}` |
| `getLeaderboard(limit)` | Promise → `{"ok", "rows": [{"name","total","me"}], "me": {"total","rank"}}` |

The result payload is one finished run: `level`, `character`, `score`, `max_score`, `correct`,
`wrong`, `playtime_sec`, `stars`, `passed`, `completed`, `revivals_used`, `finished_at`, `game_id`,
`client_version`. **It contains no user id**: the bridge always uses the signed-in Firebase user,
and the rules check that against the verified ID token.

## Data in Firestore
| Path | Contents | Who can read | Who can write |
|---|---|---|---|
| `players/{uid}` | `name` (Google name), `s1`…`s10` best score per level, `t1`…`t10` best stars, `total` = s1+…+s10, `last` (attempt id), `updated` (server time) | any signed-in Google player | only that player, through the checks below |
| `players/{uid}/attempts/{id}` | every finished run (payload + server time) | only that player | only that player; create once, never edit or delete |

No e-mail address or photo is stored. The leaderboard ranks players by `total` (sum of each
level's best score); the leaderboard screen shows the top 20, the player's own total and rank.

## What the security rules enforce (`firestore.rules`)
- Every read or write needs a signed-in **Google** account (`sign_in_provider == google.com`).
- A player can write only `players/{their own uid}`; the uid comes from the verified ID token, never
  from data sent by the game.
- Each leaderboard update must be made **in the same transaction as a new attempt record**, may
  change only that attempt's level, may only **raise** that level's best to exactly the attempt's
  score, and `total` must equal the sum. Lowering, editing other levels or other players, deleting,
  or reusing an old attempt is rejected.
- Attempt records are checked: level 1–10, `max_score` = that level's task count × 100, score a
  multiple of 100 and at most `max_score + 200` (the "double score" ability), at least one second
  of play per solved task, only known fields, server timestamp.
- The stored name must equal the name in the Google ID token.
- At most one result per player every 5 seconds.

These are tested by `tests/firebase/rules.test.mjs` against the Firestore emulator, including
another account trying to overwrite, edit, delete or read someone's results.

## Honest limitations (score tampering)
The game runs in the player's browser, and Firestore rules can check a result's shape and limits
but cannot replay the game. So:
- A player who edits the page's JavaScript can submit **any score their own account could reach**
  — at most the level maximum (+200) per level, at most one result per 5 seconds — without
  actually playing. They still cannot touch anyone else's row, inflate beyond the maximum, or hide
  that they did it: every best is backed by a write-once attempt record (score, playtime, mistakes)
  that the project owner can inspect in the Firebase Console.
- The display name comes from the Google account; a player could rename their Google/Firebase
  profile.
- Real prevention would need server-side game validation (for example Cloud Functions that issue
  per-level question sets and verify answers, which needs the paid Blaze plan) and Firebase App
  Check to limit requests to the real site. Both are possible later; neither is needed for the
  assignment.

## Which values are public and which must stay private
**Public (safe in the repository and in the browser):** everything in `web/firebase-config.js` —
`apiKey`, `authDomain`, `projectId`, `appId` (and `storageBucket`, `messagingSenderId` if you copy
them). The Firebase "API key" only identifies the project; it does not grant access. Access is
controlled by `firestore.rules`, the enabled sign-in providers and the **Authorized domains** list.

**Private (never in the repository, never in the game):**
- service-account keys (`*-firebase-adminsdk-*.json`) and any Admin SDK credentials;
- the Google OAuth **client secret** (stays inside the Firebase/Google Cloud Console);
- `firebase login` tokens / CI tokens (`FIREBASE_TOKEN`), Google account passwords;
- export signing keys (`.godot/`, `export_credentials.cfg`).
`.gitignore` excludes the usual files; `git grep -n "private_key\|client_secret"` should stay empty.

Optional hardening in Google Cloud Console → APIs & Services → Credentials: restrict the browser API
key to HTTP referrers `https://<user>.github.io/*` and `http://localhost:*`.

## Testing
- `tests/run_tests.gd` (Godot, headless): a fake transport covers guest mode, sign-in, session
  restore, per-account progress, merge of online bests, ordered and per-account uploads, the
  leaderboard screen, and that the rules' score limits match the question files.
- `tests/firebase` (`npm install`, `npm test`; needs Node 20+ and Java 21+): the security rules
  against the Firestore emulator.
- Browser against the emulators: `npm run emulators` in `tests/firebase`, serve `build/web` on
  localhost and open `http://localhost:<port>/?emulator=1` (emulator mode only works on localhost
  and uses a demo project, never the real one).

## Reconnecting the Game Hub later
The game only knows the `window.HistoryArenaHub` contract above. To join the shared Hub, either the
Hub provides a bridge file with the same methods (replace `firebase-bridge.js`), or the Hub reads
History Arena's Firestore data. Accounts match automatically if the Hub uses the same Firebase
project.
