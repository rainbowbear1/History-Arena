# Online features: Google sign-in, leaderboards and the teacher dashboard

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
- `web/firebase-bridge.js`: the only code in the game that talks to Firebase. Firebase keeps the
  session in the browser (IndexedDB), so reloading the page keeps the player signed in.
- `web/admin.html`: the teacher dashboard, a separate page next to the game that signs in with the
  same Google provider and only reads (see "Administrators and the teacher dashboard").
- A run the security rules refuse (e.g. while the published rules are older than the game) is kept
  in the outbox for a later session but no longer holds up the runs queued after it.

## Bridge contract — `window.HistoryArenaHub`
All values crossing the bridge are JSON strings.

| Member | Returns |
|---|---|
| `configured` | `true` when `firebase-config.js` is filled in |
| `waitForUser()` | Promise → `{"uid","name"}` of a restored session, or `""` |
| `getCurrentUser()` | `{"uid","name"}` or `""` |
| `signInWithGoogle()` | Promise → `{"uid","name"}`; rejects with a message (popup closed/blocked, domain not authorised…) |
| `signOut()` | Promise |
| `touchProfile()` | Promise → `{"ok"}`; records the sign-in in `profiles/{uid}` |
| `submitResult(payloadJson)` | Promise → `{"ok": true, "total": n}` or `{"ok": false, "error", "rejected"}` (`rejected` = the rules refused it) |
| `getMyProgress()` | Promise → `{"ok", "levels": {"1": {"score","stars"}, …}, "total"}` |
| `getEntitlements()` | Promise → `{"ok", "bossDefeated", "bossBest", "trophy", "admin"}` |
| `recordBossVictory(score)` | Promise → `{"ok"}`; only for BOSS victories queued by builds from before trophies |
| `getLeaderboard(limit, board)` | Promise → `{"ok", "rows", "me"}`; `board` `"campaign"` (rows `{"name","total","trophy","me"}`) or `"allinone"` (rows `{"name","correct","answered","acc","time","completed","trophy","me"}`); `me` adds `rank` (0 = no result) |

The result payload is one run: `level` (1–10 campaign, 11 BOSS, 12 All-in-One), `character`,
`score`, `max_score`, `correct`, `wrong`, `playtime_sec` (active play), `stars` (for the BOSS: the
trophy 0–3), `passed`, `completed`, `revivals_used`, `finished_at`, `game_id`, `client_version`, and
for All-in-One `answered`; `abandoned: true` marks a run left before its end. **It contains no user
id**: the bridge always uses the signed-in Firebase user, and the rules check that against the
verified ID token. `submitResult` files a run by its level: a campaign run raises `players/{uid}`, a
winning BOSS run raises `achievements/{uid}`, an All-in-One run may replace `allinone/{uid}`, and an
abandoned run is stored as an attempt only — always in one transaction with the attempt record.

## Data in Firestore
| Path | Contents | Who can read | Who can write |
|---|---|---|---|
| `players/{uid}` | `name` (Google name), `s1`…`s10` best score per level, `t1`…`t10` best stars, `total` = s1+…+s10, `last` (attempt id), `updated` (server time) | any signed-in Google player (campaign leaderboard) | only that player, through the checks below; administrators may delete it |
| `players/{uid}/attempts/{id}` | every run, including BOSS, All-in-One and runs left early (payload + server time `created`) | that player and administrators | only that player, create once, never edit; only administrators may delete |
| `achievements/{uid}` | `bossDefeated` (always true), `bossBest`, `trophy` (1 bronze, 2 silver, 3 gold; 0 = an old victory without run details), `bestCorrect`, `firstDefeated`, `updated`, `run` (the winning attempt) | any signed-in player (trophies on the leaderboards) | only that player: permanent, nothing is ever lowered, no delete |
| `allinone/{uid}` | All-in-One personal best: `name`, `correct`, `answered`, `wrong`, `acc` (correct per thousand answered), `time` (active seconds), `score`, `completed`, `pool` (tasks in the pool), `key` (ranking), `run`, `updated` | any signed-in player (All-in-One leaderboard) | only that player, and only with a better run |
| `profiles/{uid}` | `name`, `firstSeen`, `lastSeen` (server times of the first and latest sign-in) | that player and administrators | only that player, at sign-in |
| `admins/{uid}` | any fields (e.g. `role: "teacher"`) | only that account (to learn it is an admin) | **nobody from the game or the dashboard**; the project owner creates it in the console |

No e-mail address or photo is stored. The campaign leaderboard ranks players by `total`; the
All-in-One leaderboard by `key` = correct × 10⁸ + acc × 10⁵ + (99999 − time), i.e. most correct
answers, then accuracy, then the shorter active time, so character score bonuses never decide it.
Both show the top 20 and the player's own best and rank, with each player's highest BOSS trophy.

**Play time and activity.** `playtime_sec` is the arena's active time: it does not run in menus,
on the results screen or while paused, and a long frame (a hidden browser tab) adds at most 0.25 s.
Runs left early (Restart, Levels) after at least 5 s are uploaded as `abandoned` attempts so their
time counts; a tab closed in the middle of a run is not recorded. A player's total play time is the
sum over their attempts; the last activity is the latest of their attempts, sign-ins and updates.
Activity from before this version was never recorded, and nothing is back-filled.

## Administrators and the teacher dashboard
`admin.html` (published next to the game, e.g. `https://rainbowbear1.github.io/History-Arena/admin.html`)
uses the same Firebase project and Google sign-in as the game — no separate password. After sign-in
it checks `admins/{uid}`; administrators get a searchable, sortable table of every player (campaign
progress, best score per level, total, BOSS status, highest trophy, All-in-One best, total play
time, last activity, CSV download) and a details view with per-level results and the full attempt
history. Access is enforced by `firestore.rules` (`isAdmin()` = an `admins/{uid}` document exists for
the signed-in Google account), not by the page: for anyone else every read fails. Administrators
can read but not change results, and the game also gives them Unlock Everything.

**Deleting players.** In a player's details, **«Ойыншыны өшіру» / Delete player** (after a
confirmation) deletes all of that player's records: every attempt, `players/{uid}` (campaign
leaderboard), `achievements/{uid}` (BOSS victory and trophy), `allinone/{uid}` and `profiles/{uid}`.
**«Барлық ойыншыны өшіру» / Delete all players** does the same for every listed player after the
administrator types «ӨШІРУ» / DELETE. Neither touches `admins/`, so administrators keep their access.
Deletion cannot be undone (export a CSV first if needed). It removes only what is stored online: the
progress kept in the player's own browser stays, and a deleted player who signs in and plays again
reappears with the results of their new runs only. Only administrators may delete (`allow delete:
if isAdmin()`); players cannot delete anything, not even their own records.

**Adding your teacher as administrator** (after the updated rules are published):
1. The teacher opens `admin.html` and signs in with their Innotech Google account. The page answers
   "No access" and shows **their UID**; they send it to you. (Alternatively, after their first
   sign-in: Firebase Console → **Authentication → Users** → find their e-mail → copy the **User UID**.)
2. Firebase Console → **Firestore Database** → **Start collection** `admins` (the first time) or open
   `admins` → **Add document** → **Document ID** = that UID → add a field `role` (string) `teacher`
   → **Save**.
3. The teacher reloads `admin.html`. To remove access, delete that document.
No e-mail address is used for authorization; only the UID document counts, and only the project
owner (in the console) can create one.

## What the security rules enforce (`firestore.rules`)
- Every read or write needs a signed-in **Google** account (`sign_in_provider == google.com`).
- A player can write only documents under their own uid; the uid comes from the verified ID token,
  never from data sent by the game. Other players' attempts and profiles are readable only by
  administrators.
- Each leaderboard, achievement or All-in-One update must be made **in the same transaction as a new
  attempt record** and must match it: a campaign update may change only that attempt's level and may
  only **raise** its best to exactly the attempt's score, with `total` the sum; a trophy, best BOSS
  score and best correct count rise only to those of a winning BOSS run; an All-in-One best copies
  its run and its ranking key and must beat the previous key. Lowering, editing other levels or
  other players, deleting, or reusing an old attempt is rejected.
- Attempt records are checked: level 1–12, `max_score` = the level's task count × 100 (BOSS 5000,
  All-in-One the sum of the levels), score a multiple of 100 and at most `max_score + 200` (the
  "double score" ability), at least one second of play per solved task, only known fields, server
  timestamp. BOSS runs: at most 50 correct, score backed by correct answers, `stars` = the trophy for
  the correct count (bronze 30, silver 38, gold 45 of 50). All-in-One runs: answered ≤ pool,
  correct ≤ answered, `wrong` = answered − correct, no stars, `completed` only with the whole pool.
  An abandoned run can be neither completed nor carry stars.
- An old BOSS victory without run details may only keep the trophy as it is (never grant one).
- The stored name must equal the name in the Google ID token.
- At most one campaign result per player every 5 seconds.

These are tested by `tests/firebase/rules.test.mjs` against the Firestore emulator (29 tests),
including another account trying to overwrite, edit, delete or read someone's records, an ordinary
player trying to read the class, delete records or make themselves an administrator, an
administrator trying to change results, and an administrator deleting a player.

## Honest limitations (score tampering)
The game runs in the player's browser, and Firestore rules can check a result's shape and limits
but cannot replay the game. So:
- A player who edits the page's JavaScript can submit **any result their own account could reach**
  — at most the level maximum (+200) per level, a BOSS trophy matching the correct count they claim,
  an All-in-One result within the pool — without actually playing. They still cannot touch anyone
  else's records, exceed the limits, or hide that they did it: every best is backed by a write-once
  attempt record (score, play time, mistakes) that the teacher dashboard shows.
- **Play time and activity are reported by the browser too.** A modified page could report more or
  less play time than was played; runs in a tab that is closed mid-run are not recorded at all.
- The display name comes from the Google account; a player could rename their Google/Firebase
  profile.
- Real prevention would need server-side game validation (for example Cloud Functions that issue
  per-level question sets and verify answers, which needs the paid Blaze plan) and Firebase App
  Check to limit requests to the real site. Both are possible later; neither is needed for the
  assignment, and neither is used.

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
  leaderboard screens, trophies, All-in-One, abandoned runs, sign-in records, and that the rules' and
  the dashboard's limits match the question files.
- `tests/firebase` (`npm install`, `npm test`; needs Node 20+ and Java 21+): the security rules
  against the Firestore emulator.
- Browser against the emulators: `npm run emulators` in `tests/firebase`, serve `build/web` on
  localhost and open `http://localhost:<port>/?emulator=1` (emulator mode only works on localhost
  and uses a demo project, never the real one).
- Teacher dashboard against the emulators: with the emulators running, `node seed-demo.mjs` in
  `tests/firebase` fills them with a demo class; open `http://localhost:<port>/admin.html?emulator=1`,
  run `emulatorSignIn("teacher-demo", "Demo Teacher")` in the browser console, copy the UID the page
  shows, run `node seed-demo.mjs <UID>` and reload. (`emulatorSignIn` exists only in emulator mode.)

## Reconnecting the Game Hub later
The game only knows the `window.HistoryArenaHub` contract above. To join the shared Hub, either the
Hub provides a bridge file with the same methods (replace `firebase-bridge.js`), or the Hub reads
History Arena's Firestore data. Accounts match automatically if the Hub uses the same Firebase
project.
