# Тарих Аренасы (History Arena)

A browser FPS quiz about the history of Kazakhstan (Godot 4.7.2, web export). The player shoots the
enemy soldier whose placard carries the right answer, across ten historical arenas from the Saka era
to independent Kazakhstan. University project: CYB26, Technical Assignment No. 3.

> **Status of Google sign-in: NOT FINISHED.** The game side is ready (login screen, guest mode,
> result outbox, JavaScript bridge contract), but real Google sign-in and the shared leaderboard need
> the Game Hub team's backend. Until they provide `hub-bridge.js`, the login screen says so and offers
> guest play; results are kept on the device. See `docs/hub-integration.md`.

## What the game does
| Assignment requirement | In the game |
|---|---|
| 10 arenas, rising difficulty, level 10 BOSS | Saka → Huns → Turkic Khaganate → Otyrar → Golden Horde → Kazakh Khanate → Dzungar wars → 18th–19th c. → 20th c. → Independence (shooting gallery + boss panel) |
| 10 characters with HP, speed, weapon, ability, defense | Character screen; each level preselects its historical protagonist, free choice kept |
| Shoot the correct answer: +100, wrong −10 HP | Enemy soldiers hold answer placards; a wrong answer shows an enemy landing a shot |
| 6 task types | single choice, fill-in-the-blank, matching, chronology, map (Natural Earth map), image (licensed photos) |
| Difficulty: faster targets, less time, more decoys, enemies, fewer resources | Timer 30 s → 10 s, sway speed ×1.0 → ×2.5, up to 4 decoys, enemy soldiers that aim and fire dodgeable shots, fewer ability uses and medical help |
| "Жан біткенде" medical help | At 0 HP: one history question; correct → +50/40/30 HP and retry the task, wrong → restart |
| Results saved (score, level, correct, wrong, playtime) | Saved on the device with stars and unlocks; queued for the Game Hub |
| Google login, leaderboard | **Waiting for the Game Hub backend** (see above) |

## Run, test, build
```
godot --path .                                   # open/run (Godot 4.7.2)
godot --headless --path . --import               # first time, or after adding assets
godot --headless --path . --script res://tests/run_tests.gd   # 668 checks; exit code = failures
tools/export_web.sh <path-to-godot> build/web    # web build + Hub bridge file
```
Serve `build/web/` over HTTP(S) to play (threads are off, so no special headers are needed).
Settings → **Демо режимі** opens every level (for presentations); **Прогресті тазалау** resets progress.

## Architecture
```
startup_screen  →  main_menu  →  level_select  →  character_select  →  main.tscn (arena)
 (Google/guest)    (settings,                      (protagonist        ├─ quiz_manager.gd   task flow, HP, timer, score, results
                    credits)                        preselected)       ├─ tasks/*.gd        one handler per task type
                                                                       ├─ answer_target     soldier/placard targets
Autoloads                                                              ├─ environment_builder  theme: sky, props, background battle
  GameState          selected level / character                        ├─ enemy_spawner + enemy  posts, volleys, gallery panels
  LevelDatabase      data/levels.json                                  ├─ player.gd         movement, weapon, ability key
  CharacterDatabase  data/characters.json                              └─ revival_panel     medical help
  ProgressStore      user://progress.json (stars, unlocks, history)
  Backend            sign-in state, outbox → web_bridge_transport → window.HistoryArenaHub (Game Hub)
```
Content is data, not code: `data/levels.json` (difficulty, theme, protagonist), `questions/*.json`
(tasks), `data/characters.json`, `data/themes.json`. Formats: `docs/data-format.md`.

### Why this algorithm helps learn history
- **Six task types** practise different skills: recall (single choice, fill-in), connections
  (matching people ↔ events, events ↔ years), ordering (chronology), geography (map), and recognising
  monuments and artefacts (image).
- **Immediate feedback:** a missed answer reveals the correct one; the medical-help question prefers
  questions the player got wrong earlier, so mistakes are revisited; the failed task is retried.
- **Spaced difficulty:** each era adds less time, faster targets and plausible decoys (dates among
  dates), so later levels reward real knowledge over guessing.
- **Fair scoring:** points only come from answers (enemies give none), so the shared leaderboard
  reflects history knowledge.

## Documentation
| File | Contents |
|---|---|
| `docs/defense-plan.md` | Status against the assignment, milestones, risks, dependencies |
| `docs/demo-script.md` | Step-by-step defense demonstration (12 required points) |
| `docs/deploy.md` | Hosting the web build, pre-defense checklist |
| `docs/hub-integration.md` | Game Hub bridge contract, result payload, server-side checks, what we need |
| `docs/data-format.md` | Levels, questions, characters, themes, saved progress |
| `docs/content-review.md` / `docs/history-review-checklist.md` | Every task with its answer; accuracy checklist |
| `docs/vision.md` | Long-term creative direction |
| `assets/CREDITS.md` | Map and image sources and licences (also shown in-game under **Авторлар**) |

## Security notes
- No passwords, API keys or secrets in the game or repository; the old hard-coded login was removed.
- The Hub bridge may only contain public client configuration; results must be validated server-side
  (rules in `docs/hub-integration.md`), and the player id comes from the Hub session, never the client.
- `.godot/` (which holds export credentials) and build outputs are git-ignored.
