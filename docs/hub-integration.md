# Game Hub integration (Google sign-in and results)

History Arena does **not** have its own authentication or database. It uses the shared Game Hub
(CYB26-01) so that one Google account is the same player in the Hub and in every game. This page
is the contract between the game and the Hub team.

## Architecture
```
 Player's browser
 ┌──────────────────────────────────────────────────────────────┐
 │ index.html (History Arena web build)                          │
 │   <script src="hub-bridge.js">   ← written by the Hub team    │
 │        window.HistoryArenaHub  ── Hub's auth SDK (Google) ────┼──► Hub backend
 │                ▲                                              │    (Firebase or Supabase,
 │   Godot game   │ JavaScriptBridge (JSON strings)              │     chosen by the Hub team)
 │   backend.gd ──┘   web_bridge_transport.gd                    │      • Google OAuth
 │   progress_store.gd (local save)  outbox (pending uploads)    │      • server-side checks
 └──────────────────────────────────────────────────────────────┘      • leaderboard
```
- `backend.gd` (autoload `Backend`): sign-in state, guest mode, and an **outbox** of finished runs
  saved in `user://outbox.json`. Runs are uploaded in order once a Hub player is signed in; a failed
  upload stays queued.
- `web_bridge_transport.gd`: calls `window.HistoryArenaHub` and waits for its Promises (30 s timeout).
- `web/hub-bridge.js`: currently a **not-configured stub**. `tools/export_web.sh` copies it next to
  `index.html`. The Hub team replaces it with the real implementation.
- Without a configured bridge the login screen offers **guest play**; results stay on the device
  (and in the outbox).

Sign-in sharing: if the game is hosted **on the Hub's domain** (e.g. `https://<hub>/games/history-arena/`),
an existing Hub session is reused automatically (`getCurrentUser`). On another domain the player
signs in again with the same Google account; the same auth project gives the same user id.

## Bridge contract — `window.HistoryArenaHub`
All values crossing the bridge are **JSON strings**.

| Member | Returns | Notes |
|---|---|---|
| `configured` | boolean | `true` when the bridge is connected to the Hub backend. |
| `getCurrentUser()` | string: user JSON, or `""` | Restores an existing session without a popup. |
| `signInWithGoogle()` | Promise → user JSON | Rejects with a message on failure/cancel. Must be callable from a click (popup) or use the redirect flow. |
| `signOut()` | Promise | |
| `submitResult(payloadJson)` | Promise → `{"ok": true}` or `{"ok": false, "error": "..."}` | One attempt per call; the game retries failures later. |

User JSON: `{"uid": "<stable Hub user id>", "name": "<display name>", "email": "<email>"}` — `uid`
is required; the game shows `name`.

## Result payload (one finished run)
```json
{
  "game_id": "history-arena",
  "client_version": "0.9.0",
  "level": 4,
  "character": "al_farabi",
  "score": 1100,
  "max_score": 1300,
  "correct": 11,
  "wrong": 3,
  "playtime_sec": 241,
  "stars": 2,
  "passed": true,
  "completed": true,
  "revivals_used": 0,
  "finished_at": 1794700000
}
```
| Field | Meaning |
|---|---|
| `level` | 1–10 |
| `score` | +100 per solved task; the "double score" ability can add up to +100 per use (at most 3 uses) |
| `max_score` | number of tasks × 100 (12–15 tasks per level) |
| `correct` / `wrong` | solved tasks / every mistake (wrong shot, wrong pair/order, time-out) |
| `playtime_sec` | seconds played, pauses excluded |
| `stars` | 0–3; `passed` = stars ≥ 1 |
| `completed` | `false` when the run ended in defeat |
| `finished_at` | Unix time from the player's device — **not trusted**; the server should store its own time |

The player's identity is **not** in the payload: the Hub must take it from the authenticated
session (ID token / auth context), never from the request body.

## Server-side checks we recommend (anti-cheat, rate limiting)
The browser can be modified, so the Hub backend (a Cloud Function / Edge Function, not a direct
table write) should reject a result unless:
- the request carries a valid Hub session; `uid` comes from the token;
- `game_id == "history-arena"`, `1 <= level <= 10`, numbers are whole and non-negative;
- `max_score` equals the known task count × 100 for that level (12, 13, 14 or 15 tasks);
- `score <= max_score + 300` and `score` is a multiple of 100;
- `correct <= max_score / 100`;
- `playtime_sec >= correct` (every solved task shows at least one second of feedback);
- `stars` agrees with the score and the level's pass mark;
- at most one result per player every 20 seconds (basic rate limiting).
Leaderboard rows should be computed by the server from accepted results (best score per level,
total, highest level passed), never written by the client.

## What we need from the Hub team
1. **Provider:** Firebase or Supabase, and the auth project shared by all six games.
2. **The real `hub-bridge.js`** implementing the contract above (or the public client config, so we
   can write it with them), using only public client configuration — no secrets in the game.
3. **Hosting:** the HTTPS URL where History Arena will live (ideally under the Hub's domain), and that
   domain added to the authorised OAuth domains.
4. **Results endpoint:** the server-side function that receives `submitResult`, with the checks above.
5. **Leaderboard/profile format:** confirm the fields the Hub shows (place, student, game, score,
   level) and how History Arena's best scores are combined.
6. **Test account or staging environment** to verify sign-in and uploads before the defense.

## Testing
- Unit tests (`tests/run_tests.gd`) use a fake transport: guest mode, queueing, ordered upload,
  failed uploads, session restore and sign-out.
- Browser test: `tests/web/hub-bridge.mock.js` is a **fake** bridge (made-up test user, results kept
  in `window.__submitted`). Copy it over `hub-bridge.js` in a local build only. Never deploy it.
