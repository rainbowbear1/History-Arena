# History Arena data format

Levels and questions are plain JSON files, so new content can be added without touching code.
Run the tests (below) after every content change; they report the exact file, entry and problem.

## Levels — `data/levels.json`

```json
{ "version": 1, "levels": [ { "id": 1, "title": "Сақтар дәуірі", ... }, ... ] }
```

| Field | Type | Meaning |
|---|---|---|
| `id` | whole number | Level number. Must run 1, 2, 3… in file order. |
| `title` | text | Arena name shown in level select. |
| `stars` | 1–5 | Difficulty shown to the player. |
| `boss` | true/false | Boss level (shown as "BOSS"). Optional, default false. |
| `theme` | theme name | Look of the arena from `data/themes.json` (sky, fog, props, soldiers). |
| `protagonist` | character id or `""` | Historical protagonist preselected on the character screen (free choice stays available). Optional. |
| `question_file` | `res://` path | Question file for this arena. The level stays locked until this file exists. |
| `time_per_question` | seconds | Time limit per task. |
| `target_speed` | number | Multiplier for target movement speed. |
| `extra_decoys` | whole number | Extra fake-answer targets added on top of the 4 options. |
| `enemies` | whole number | Enemies active in the arena. |
| `revive_hp` | 1–100 | HP restored by a correct medical-help answer (50 / 40 / 30 by difficulty). |
| `revivals` | whole number | How many times medical help can be offered in one run. |
| `pass_percent` | 0–100 | Score needed (as % of the maximum) to pass and unlock the next level. |

All fields drive the gameplay (`pass_percent` decides passing and stars, see Saved progress):

- **Timer:** `time_per_question` seconds per task, doubled for matching and chronology. Running out
  counts as a wrong answer (−10 HP, correct answer revealed). The timer stops between tasks and
  while paused.
- **Targets:** sway speed is multiplied by `target_speed`.
- **Decoys:** `extra_decoys` wrong answers, taken from other questions in the same level, are added
  on the top row for `single_choice` and `fill_blank` tasks (image tasks need the top row for the
  picture). Dates get date decoys, and a decoy never restates an option in another form ("552" next
  to "552 ж.").
- **Enemies:** `enemies` enemy soldiers hold posts on the flanks; they do not chase the player. One
  shared volley clock (every 12 − 1.5·s seconds, at least 3.5 s) picks one enemy, which aims for
  0.9 s (a red "!") and fires an arrow or bullet at where the player stood: step aside to dodge, or
  shoot the enemy first. With `stars` = s: HP 1 + s/2, damage 3 + s, reduced by the character's
  `defense` (at least 1). They only act while a task is being answered, return 6 s after being
  killed, and give no points (so the score cannot be farmed).
- **Wrong answers** trigger a visible reaction shot from an enemy (or a distant soldier) and a red
  screen flash; the HP loss is still the usual 10.
- **Boss:** a `boss` level adds one large boss enemy (12 HP, 12 damage) on the rampart's flank that
  does not come back once defeated. In the shooting gallery (`enemy_mode: gallery`) enemies are up
  to three sliding panels plus a gold boss panel; they block shots but never attack.
- **Fewer resources:** ability uses drop by one for every two stars above 1 (never below 1), on top
  of the smaller `revive_hp` and `revivals` on later levels.

### HP and medical help
The player has one pool of 100 HP; every mistake costs 10 HP. At 0 HP the "СІЗ ЖЕҢІЛДІҢІЗ!" screen
offers one historical question as medical help (up to `revivals` times per run). It asks a
`single_choice` or `fill_blank` question from the same level — never the task the player just failed,
preferring a question missed earlier, then one not asked yet. A correct answer restores `revive_hp`
HP and the player retries the task they failed (answers reshuffled; matching/chronology start over),
keeping their score and completed tasks. A wrong answer means no medical help, leaving Restart and
Levels. These numbers are preliminary and will be tuned after playtesting with timers and enemies.

## Saved progress — `user://progress.json`

Written by `progress_store.gd` (in the browser, `user://` is stored in IndexedDB). It holds, per
level, the best score, best stars, whether it was passed and the number of attempts, plus the last
50 attempts. Each attempt record is what is uploaded to Cloud Firestore (`docs/online.md`):

```json
{ "level": 1, "character": "tomyris", "score": 1100, "max_score": 1300, "correct": 11, "wrong": 2,
  "playtime_sec": 187, "stars": 2, "passed": true, "completed": true, "revivals_used": 0,
  "finished_at": 1794700000 }
```

- `max_score` = number of tasks × 100. `wrong` counts every mistake (wrong shots, wrong pairs or
  order, time-outs). `playtime_sec` excludes time spent paused.
- **Stars:** below `pass_percent` → 0 (not passed); passed → 1; 80 % → 2; 95 % without medical
  help → 3.
- **Unlocks:** level 1 is open; each level opens when the previous one is passed. Settings →
  "Демо режимі" opens every level that has questions (for presentations); "Прогресті тазалау"
  (pressed twice) clears everything.
- A run that ends in defeat (no medical help left, or a wrong medical-help answer) is saved with
  `completed: false` and 0 stars.

## Themes — `data/themes.json`

One entry per era: `sky_top`, `sky_horizon`, `ground`, `fog_color`, `fog_density`, `sun_color`,
`sun_energy`, `sun_pitch`, `sun_yaw`, `ledge` (rampart colour) and `ledge_style` (`earth`, `fortress`,
`palisade`, `sandbags`, `rock`, `stand`), `placard` (answer placard colour), `target_style`
(`soldier` or `gallery`), `props` (list of `[kind, count]`: kurgan, hill, mountain, yurt, tent, banner,
balbal, stele, tower, wall, dome, rock, palisade, birch, tree, sandbags, flag, booth, monument),
`enemy_look` / `ally_look` (soldier `coat`, `pants`, `skin`, `trim`, `headgear` = none/pointed/fur/
helmet/turban/cap/steel_helmet/kalpak, `headgear_color`, `weapon` = none/bow/spear/sword/rifle,
`shield`, `robe`), `background` (`allies`, `enemies`, `motion` = fight/march/idle) and optional
`enemy_mode: gallery`. Answer soldiers wear `enemy_look`; colours are `#rrggbb`.

## Characters — `data/characters.json`

```json
{ "version": 1, "characters": [ { "id": "tomyris", "name": "Томирис", ... }, ... ] }
```

| Field | Type | Meaning |
|---|---|---|
| `id` | text | Unique id, stored as the player's choice. |
| `name`, `title`, `description` | text | Shown on the character select screen. |
| `hp` | 50–200 | Size of the HP pool (wrong answers still cost 10 HP). |
| `speed` | 3–10 | Movement speed in m/s (the old default was 6). |
| `defense` | 0–60 | Percent of **enemy shot** damage blocked. Answer mistakes always cost 10 HP. |
| `weapon.name` | text | Shown in the HUD. |
| `weapon.cooldown` | seconds > 0 | Time between shots. |
| `weapon.damage` | whole number ≥ 1 | Damage to enemies per hit. |
| `weapon.model` | bow/musket/rifle/mg | First-person weapon model. Optional. |
| `weapon.auto` | true/false | Optional. Hold the mouse button to keep firing. |
| `ability.id` | see below | Special ability on the E key. |
| `ability.uses` | whole number ≥ 1 | Uses per level. |

Abilities (`abilities.gd`): `fifty_fifty` (removes two wrong answers; single-answer and map tasks),
`slow_time` (targets and enemies slowed for 8 s), `extra_time` (+10 s on the task timer),
`shield` (blocks the next damage), `heal` (+25 HP, up to the maximum), `double_score`
(next solved task gives double points). An ability that cannot help right now is refused
without spending a use.

## Questions — `questions/*.json`

A question file is a JSON array. Every entry has:

| Field | Required | Meaning |
|---|---|---|
| `question` | yes | Prompt shown to the player. |
| `type` | no | One of the six types below. Missing means `single_choice`. |
| `id` | no (recommended) | Unique text id within the file, e.g. `"saka-01"`. Used for statistics later. |
| `explanation` | no | Short fact shown after answering. |

Examples of every type: `tests/fixtures/all_types.json`.

### 1. `single_choice` — one correct answer
`answers`: exactly 4 unique texts. `correct`: one of them.

### 2. `matching` — pair up two columns (person ↔ event, state ↔ year, term ↔ definition)
`pairs`: 2–4 objects `{ "left": ..., "right": ... }`. Left texts unique, right texts unique.

### 3. `chronology` — put events in order
`items`: 3–5 unique texts **in the correct order**. The game shuffles them.

### 4. `map` — find a place on the map of Kazakhstan
`locations`: exactly 4 objects `{ "name": ..., "x": 0–1, "y": 0–1 }`, at least 0.08 apart, where x/y are positions
on the map image (0,0 = top-left, 1,1 = bottom-right). `correct`: one of the names.
Pins show numbers 1–4, not names. The board shows `assets/maps/kazakhstan.svg` (Natural Earth).
Get x/y with `python tools/build_map.py --point <lat> <lon>` and keep `lat`/`lon` in the entry
for review (the tests check that x/y match them).

### 5. `image` — identify the period of an image or artifact
`image`: `res://` path to an image in the project. Use only images with a licence that allows reuse, and add
them to `assets/CREDITS.md` and the in-game credits (`main_menu.gd`). `answers` and `correct` as in `single_choice`.

### 6. `fill_blank` — fill in the missing word
`question` must contain `___` where the blank is. `answers` and `correct` as in `single_choice`.

## Running the tests

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

The exit code is the number of failed checks; `0` means everything passed.
