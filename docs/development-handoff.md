# History Arena — development handoff (18 November 2026)

> **Update, later on 18 Nov (milestones 28–32, after the "final development specifications"):**
> checkpoint tag `checkpoint-before-final-spec` (= `ff36bc1`), then
> M28 BOSS phases + source labels, M29 All-in-One (replaces the Endless idea) with its own
> leaderboard, M30 BOSS trophies, M31 teacher dashboard `web/admin.html` + activity tracking
> (`profiles/{uid}`, abandoned runs), M32 rule tests, secret audit, `origin` =
> `https://github.com/rainbowbear1/History-Arena.git` (nothing pushed), Pages docs.
> Tests: 984 Godot checks, 27 emulator rule tests, all passing. Still waiting on the user: publishing
> the new `firestore.rules`, adding `rainbowbear1.github.io` to Authorized domains, the teacher's
> UID in `admins/`, approval to push and deploy. The sections below describe the state before these
> milestones where they differ; `docs/online.md`, `docs/data-format.md` and `docs/deploy.md` are current.

Written at the end of a long development session so that a fresh session can continue without the
conversation history. Everything below describes the repository at commit `ed470e5` on `main`
(plus this document's own commit). **Read "Rules for continuing" before changing anything.**

## 1. Project in one paragraph

**Тарих Аренасы / History Arena** is a Godot 4.7.2 first-person quiz shooter about the history of
Kazakhstan, exported to the web (GL Compatibility, single-threaded). The player shoots the soldier
(or gallery plaque) carrying the correct answer. Ten campaign levels from the Saka era to
independence, a separate 50-task BOSS run, ten playable characters, six task types, Kazakh/English,
Google sign-in and a Firestore leaderboard. University assignment CYB26, Technical Assignment No. 3
(course INN 102 «Қазақстан тарихы»); the defense is on 24/26 Nov 2026 and the teacher wants it
finished around 17–19 Nov. The Game Hub integration is **postponed**: the game is standalone.

## 2. Status: implemented vs planned

### Implemented and tested
| Area | What exists | Main files |
|---|---|---|
| Campaign | 10 levels, data-driven (`data/levels.json`), total-score unlocking, stars, results | `quiz_manager.gd`, `progress_store.gd`, `level_select.gd`, `level_database.gd` |
| Task types | single choice, fill-in-the-blank, matching, chronology, map (HUD overlay with reticle), image (HUD photo panel) | `tasks/*.gd`, `map_overlay.gd`, `image_panel.gd` |
| Answer layout | 1–4 answers in one ground row; 5–6 split ground/rampart; banded screen labels that never overlap; aiming at a label counts | `answer_labels.gd`, `answer_target.gd` |
| Level 10 | Arcade shooting gallery: three moving tracks, tin ducks, speed ramp, finale flock; 5/5 difficulty | `gallery.gd`, `environment_builder.gd` (`_gallery_stage`) |
| BOSS | Level id 11 (own `"boss"` entry in `levels.json`): 50 tasks (5 per era, era then difficulty order), shrinking timer, faster targets, 3 enemies, medkits on **H**; revealed with "BOSS АШЫЛДЫ!" after level 10 is first passed; red tile beneath level 8; never counted in totals | `quiz_manager.gd` (`load_boss_questions`, `use_medkit`, `_show_boss_results`), `boss_reveal.gd`, `level_select.gd` (`_add_boss_tile`) |
| New Game | Settings → «Жаңа ойын»: resets campaign progress of the current profile on this device only | `main_menu.gd`, `progress_store.gd` (`reset`) |
| Unlock Everything | Settings → «Барлығын ашу» (old demo mode): opens all levels, BOSS, characters. Locked until the BOSS is defeated once, or for admins | `progress_store.gd` (`can_unlock_everything`, entitlements file), `backend.gd` (`sync_entitlements`) |
| Characters | 10 characters, era-based unlocks (Manshuk after passing level 9), abilities on **E** | `data/characters.json`, `character_select.gd`, `abilities.gd` |
| Enemies | Waves (max 3), weapon-scaled toughness, health bars, collapse animation | `enemy_spawner.gd`, `enemy.gd`, `health_bar.gdshader` |
| Weapons | Recurve bow (aimed at the crosshair, 0.12 s draw), flintlock musket, scoped rifle, pan-fed MG; arrows, pooled muzzle flash and tracers | `player.gd`, `projectile.gd` |
| Medical help | At 0 HP: one question from `questions/medical.json` (never repeated in a run, not the last 12 asked); correct → HP restored and the failed task retried | `quiz_manager.gd` (`pick_revival_question`), `revival_panel.gd` |
| Questions | 133 campaign tasks + 35 medical, bilingual (`en` block), difficulty 1–3, audited (repeats/leaks) and checked against the INN 102 syllabus | `questions/*.json`, `question_validator.gd`, `question_audit.gd` |
| TXT import | Teammates' questions as plain text ↔ JSON, with line-numbered errors | `tools/questions_txt.py`, `docs/question-import.md`, `docs/question-template.txt` |
| Languages | Kazakh default, English via main-menu KZ/EN switch, saved in `user://settings.cfg` | `locale.gd` (autoload `Locale`), `locale/en.json` |
| Fonts | Fira Sans (text, buttons), PT Serif Bold (headings, `Heading` theme variation); OFL; full Kazakh alphabet | `assets/fonts/`, `ui_theme.tres` |
| Online | Real Firebase Auth (Google popup) + Firestore leaderboard, per-UID results, outbox for offline runs, session restore, sign-out | `web/firebase-bridge.js`, `web/firebase-config.js`, `web_bridge_transport.gd`, `backend.gd`, `leaderboard.gd`, `startup_screen.gd` |
| Entitlements online | `achievements/{uid}` (BOSS victory, permanent), `admins/{uid}` (read-only for clients) — **code and rules written, rules NOT deployed** | `web/firebase-bridge.js` (`getEntitlements`, `recordBossVictory`), `firestore.rules` |

### Not implemented (planned, no code yet)
- **Endless / "All-in-One" mode** — mentioned by the user; no specification received, nothing built.
- **Trophies** — not built.
- **Teacher admin dashboard** — not built. Only the admin *role* exists (`admins/{uid}` read in
  `sync_entitlements`; currently it only grants Unlock Everything).
- Game Hub integration — postponed by the user.
- Orbulak vantage point, more distinct XVIII–XIX / XX century arenas — ideas only (`docs/vision.md`).

The user said the specification for Endless Mode, trophies and the dashboard would come in a later
prompt; it has **not** been received. Ask for it before building any of them, and plan their
Firestore collections and rules together with the undeployed `achievements`/`admins` rules so that
the live rules are published once.

## 3. Architecture

```
startup_screen.tscn ─► main_menu.tscn ─► level_select.tscn ─► character_select.tscn ─► main.tscn (arena)
 (Google / guest)       (KZ/EN, settings,   (10 tiles + BOSS     (era-locked cards)       QuizManager + Player + HUD
                         leaderboard,        tile, total score)                            Environment, Enemies, Gallery
                         credits, sign out)
Autoloads (project.godot): GameState, LevelDatabase, CharacterDatabase, ProgressStore, Backend, Locale
```

- **Data-driven**: levels `data/levels.json` (plus the `"boss"` entry), characters
  `data/characters.json`, era looks `data/themes.json`, questions `questions/*.json`
  (format: `docs/data-format.md`; formatter `tools/qjson.py`).
- **Arena** (`main.tscn`): `quiz_manager.gd` runs the task flow (timer, HP, scoring, results, medical
  help, BOSS logic); a task script per type builds targets; `answer_labels.gd` draws screen labels;
  HUD overlays (`image_panel.gd`, `map_overlay.gd`) are created at runtime under `HUD`;
  `environment_builder.gd` dresses the arena from the theme; `gallery.gd` exists only on level 10.
- **Progress** (`progress_store.gd`): `user://progress.json` for guests,
  `user://progress_<uid>.json` per Google account; entitlements in `<file>_entitlements.json` (never
  cleared by New Game); BOSS results are kept apart from level results (never in the total).
- **Online** (`backend.gd`): sign-in state, outbox `user://outbox.json`, pending BOSS victories
  `user://boss_pending.json`, entitlement sync after sign-in. It talks only to
  `window.HistoryArenaHub` (JS) through `web_bridge_transport.gd`; tests use a `FakeTransport`.
- **Localization**: UI strings are Kazakh keys translated through TranslationServer (`tr()`,
  automatic for scene texts); fallback locale `kk` (set in `project.godot`; comments in that file must
  start with `;`, not `#`). Questions switch language through `Locale.localize_question()` (English
  swapped in by position, so ids and correct answers are shared).

## 4. Firebase

- **Project:** `history-arena-709c8` (owner: the user). Web config is committed in
  `web/firebase-config.js` (public identifiers only: apiKey, authDomain, projectId, appId — not
  secrets). No service-account key or other secret is in the repository; never add one.
- **Auth:** Google provider enabled. Authorized domains (checked 18 Nov): `localhost`,
  `history-arena-709c8.firebaseapp.com`, `history-arena-709c8.web.app`. **`<github-user>.github.io`
  still has to be added** before GitHub Pages deployment. `127.0.0.1` is not authorized — test locally
  on `http://localhost:<port>/`.
- **Verified by the user (manually, 17–18 Nov):** real Google sign-in and sign-out, live score
  submission, leaderboard display, records preserved across sign-out/sign-in, New Game does not
  delete Firestore data.
- **Firestore data:** `players/{uid}` (name, s1–s10 best scores, t1–t10 stars, total, last, updated),
  `players/{uid}/attempts/{id}` (write-once runs); new and **not live yet**: `achievements/{uid}`,
  `admins/{uid}`. Details and the "add a teacher as admin" steps: `docs/online.md`.
- **Security rules** (`firestore.rules`): uid always from the verified token; one result per 5 s;
  bests only rise; scores capped per level (`maxScore`, must match task counts × 100 — the Godot
  tests check this); achievements permanent with a rising best; admins not writable by clients.
  **Live state:** the user published the rules as they were *before* commit `3d3a920` (players +
  attempts only). The `achievements`/`admins` additions are committed locally and tested on the
  emulator but **must not be published without the user's approval**. Until then BOSS victories
  stay pending on the device (sent automatically later) and admin status cannot be read.
- **Known limit:** scores and BOSS victories are reported by the browser; rules keep them plausible
  but cannot prove a run happened (would need Cloud Functions, not on the free plan).

## 5. Tests and checks

Paths on the development machine:
- Godot (console): `C:\Users\Жангир\Desktop\videogame\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- Java for the Firebase emulators: `C:\Program Files\Java\jdk-21.0.10` (set `JAVA_HOME` and `PATH`)

| Check | Command (from the project folder) | Last result |
|---|---|---|
| Import (after adding assets) | `godot --headless --path . --import` | ok |
| Game tests | `godot --headless --path . --script res://tests/run_tests.gd > out.txt` — exit code = failures | **918 checks, 0 failed** (run twice) |
| Question audit | `godot --headless --path . --script res://tools/audit_questions.gd` | 0 problems in 11 banks |
| Firestore rules (emulator) | `cd tests/firebase && npm test` | **13 passed** |
| Web export | `bash tools/export_web.sh <godot> build/web` | ok (build/web is git-ignored) |
| Screenshots | `godot --path . --script res://tools/screenshots.gd -- levels=7 size=1280x720 [task=<id>] [lang=en] [menu] [select]` (needs a real window) | used for visual checks |
| TXT round trip | `python tools/questions_txt.py export <bank>` / `check` / `import --level` | all 11 banks round-trip exactly |

Practical notes learned the hard way:
- Write test output to a file; piping Godot through `grep` buffered output and once hid a hang.
- New `--script` tools must start work with `run.call_deferred()` (autoloads are not ready in
  `_initialize`) and must type variables explicitly where GDScript cannot infer them.
- Never kill all Godot/Java processes by name (the session's safety check denies it). Stop only the
  PIDs you started; emulator `npm run emulators` leaves a `java` (Firestore) and `node` (Auth) child
  holding ports 8080/9099 after the task is stopped.
- The in-app browser pane cannot open the Google popup or capture the mouse, and throttles when
  hidden; use it for loading/menus/Firestore checks only. The user does real-mouse playtests.
- Bash heredocs with Python sometimes mangled backslashes and quotes: write edit scripts to a file
  (forward-slash paths) and run them.
- The level-10 gallery and BOSS tests are timing-sensitive; tests set `player.bow_draw_time = 0`.

## 6. Git

- Branch `main` only; **no remote configured**; nothing has ever been pushed. No `gh-pages` branch
  exists yet (`tools/publish_pages.sh` creates it locally from `build/web`).
- Working tree clean at `ed470e5` before this document. 42 commits.
- **Checkpoint tags:** `checkpoint-before-polish` (= `3eb991f`, end of M16),
  `checkpoint-before-endgame` (= `79026fb`, before the syllabus audit and BOSS work).
- Milestones: M1–M10 (base game, docs), M11 Firebase, M12–M16 playtest fixes, M17–M24 post-playtest
  refinement (`docs/polish-report-2026-11.md`), M25–M27 unlocks/fonts/weapons/TXT import, then:
  MG lag fix `8ea7b26`, bow orientation `8c72d6d`, sign-in messages `94e37d0`, Firebase config
  `79026fb`, syllabus audit `27f4bae`, BOSS/New Game/Unlock Everything `3d3a920`, reveal fix
  `90f3473`, test fix `ed470e5`.
- History was scrubbed of an old toy login on 15 Nov. A pre-scrub backup
  `Documents\history-arena-before-scrub.bundle` (outside the repo) still contains it: the user should
  delete it and must never share it.

## 7. Open items and decisions waiting on the user

1. **Spec for Endless/All-in-One mode, trophies and the teacher dashboard** (not received).
2. **Approval to publish the updated `firestore.rules`** (achievements + admins).
3. **Admin accounts**: which teachers; their UIDs go into `admins/{uid}` via the console.
4. **GitHub username and repository name**, add `<user>.github.io` to Authorized domains, then
   approval to push `main` and `gh-pages` (`docs/deploy.md`).
5. **Unlock thresholds** `0/750/1500/2350/3200/4050/4900/5750/6650/7600` are still provisional (never
   formally approved; the user asked to keep level unlocking generous).
6. **Historical review** of the content by the user/teacher: `docs/history-review-checklist.md`,
   `docs/syllabus-audit-2026-11.md` (sources per replaced task).
7. Teammates' replacement questions (TXT) may still arrive; import with `tools/questions_txt.py`.
   If task counts change, update `firestore.rules` `maxScore` and possibly the thresholds (tests say).
8. Optional: level-specific music file `assets/music/independence.ogg` (slot exists; user will compose).

## 8. Rules for continuing (from the user)

- **Never push, deploy, publish Firebase rules or change live Firebase without explicit approval.**
- Create a checkpoint (tag) before major modifications; one clearly named commit per milestone, after
  the tests pass; run the emulator rule tests after any rules change.
- Do not invent historical facts, credentials or backend endpoints; verify new facts with sources;
  do not do large question overhauls without approval; keep KZ/EN consistent.
- Do not claim online features work until verified; report remaining blockers honestly.
- Preserve existing gameplay, progression, languages, Firebase integration and the gallery level;
  no new major features without a specification.
- Commit attribution line: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## 9. Documentation map
| File | Contents |
|---|---|
| `README.md` | Overview, assignment table, run/test/build commands |
| `docs/data-format.md` | Levels, BOSS, questions, characters, themes, saved progress, languages |
| `docs/online.md` | Firebase architecture, bridge contract, Firestore data, rules, admins |
| `docs/deploy.md` | Firebase setup, GitHub Pages steps, live-site checklist |
| `docs/question-import.md`, `docs/question-template.txt` | TXT question workflow |
| `docs/syllabus-audit-2026-11.md` | INN 102 audit: retained/revised/replaced with reasons and sources |
| `docs/question-overhaul-2026-11.md`, `docs/content-review.md` | Earlier overhaul log; every task with answers |
| `docs/history-review-checklist.md` | Points for the historian/teacher to verify |
| `docs/polish-report-2026-11.md` | M17–M27 milestone report |
| `docs/defense-plan.md`, `docs/demo-script.md`, `docs/vision.md` | Defense plan, demo script, long-term ideas |
| `assets/CREDITS.md` | Licences of images, map and fonts |
