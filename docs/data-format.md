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
| `pass_percent` | 0–100 | Score needed (as % of the maximum) to pass the level (stars). |
| `unlock_score` | whole number | Total score (sum of every level's best) that opens this level; 0 for level 1. |
| `music` | `res://` path | Optional. Music that loops while the level is played; nothing plays until the file exists (level 10 reserves `res://assets/music/independence.ogg` for an original track). |

All fields drive the gameplay (`pass_percent` decides passing and stars, see Saved progress):

- **Timer:** `time_per_question` seconds per task, doubled for matching and chronology. Running out
  counts as a wrong answer (−10 HP, correct answer revealed). The timer stops between tasks and
  while paused.
- **Targets:** sway speed is multiplied by `target_speed`.
- **Answer formation:** up to four answers stand in one row on the ground, 3.6 m apart, labels above
  the heads. Five or six use the ground row (three, labels hanging below the feet) and the rampart
  behind (the rest, labels above the heads); matching puts the left items on the rampart and the
  right items on the ground. A label is never wider than the gap to its neighbours (long text wraps),
  labels of a row never overlap and stay on screen, and aiming at a label counts as aiming at its
  soldier (tested at 800x600 to 1920x1080 with long Kazakh and English answers).
- **Decoys:** up to `extra_decoys` extra wrong answers join the formation for `single_choice` and
  `fill_blank` tasks (not for image tasks). They come
  **only from that task's own `extra_answers`**, never from other questions; a task with fewer (or
  no) extra answers simply shows fewer targets. Levels: 0 extra on 1–4, 1 on 5–6, 2 on 7–10 (at most
  six answers on screen; the assignment's table, p. 9, is marked "to be refined in testing").
- **Task order:** every attempt (including Retry) asks the level's tasks in a new random order,
  each exactly once; answer positions are shuffled too.
- **Enemies:** up to `enemies` active enemy soldiers (never more than 3; levels use 0, 0, 1, 1, 2,
  2, 3, 3, 3, 0). Each task starts with a wave: missing enemies march in from the arena edge to free
  posts on the flanks, never the posts of the previous wave. A killed enemy is replaced at most once
  per task, 8 s later and at another post, so the line can be cleared. Toughness is counted in hits
  of the player's own weapon: 1 hit on 1–2 stars; on harder levels the first hit plus as many more as
  the weapon fires in 0.5 s (3 stars) or 1 s (4–5 stars). So the machine gun needs a burst of about
  7 hits, bows 2–3, and the musket and rifle, whose long reload makes a miss costly, one aimed shot.
  A slim health bar over the head shows the share of health left (a pale strip drains after each
  hit); a killed enemy stops fighting at once, topples over and sinks away. One shared volley clock (every
  12 − 1.5·s seconds, at least 3.5 s) picks one enemy at its post, which aims for 0.9 s (a red "!")
  and fires at where the player stood: step aside to dodge, or shoot first. Damage 3 + s, reduced by
  the character's `defense` (at least 1). Enemies act only while a task is being answered and give
  no points (so the score cannot be farmed). The shooting gallery (level 10) has none.
- **Shooting gallery (level 10, `gallery.gd`):** an arcade booth instead of a battlefield. Answer
  plaques ride three horizontal tracks at different heights and depths, neighbouring tracks moving
  opposite ways; a plaque leaving the stage slides behind a curtain and comes back on the other
  side, and plaques on one track keep the same distance, so labels never bunch up. Labels are
  printed on the plaques. Answers take turns on the tracks; matching puts left items on the top
  track and right items on the bottom one. A flock of three tin ducks crosses the foreground: ducks
  carry no answer, stop a shot that hits them (no penalty) and leave gaps. Speeds rise by up to 35 %
  over the level; the last three tasks add a second flock. 16 s per task to allow for the movement.
- **Background battle:** allies beside the player fire harmless arrows or bullets at the distant
  enemy line, which fires back now and then; background soldiers never hurt the player.
- **Wrong answers** trigger a visible reaction shot from an enemy (or a distant soldier) and a red
  screen flash; the HP loss is still the usual 10.
- **Boss:** a `boss` level adds one large boss enemy (12 HP, 12 damage) on the rampart's flank that
  does not come back once defeated. In the shooting gallery (`enemy_mode: gallery`) enemies are up
  to three sliding panels plus a gold boss panel; they block shots but never attack.
- **Fewer resources:** ability uses drop by one for every two stars above 1 (never below 1), on top
  of the smaller `revive_hp` and `revivals` on later levels.

### HP and medical help
The player has one pool of 100 HP; every mistake costs 10 HP. At 0 HP the "СІЗ ЖЕҢІЛДІҢІЗ!" screen
offers one historical question as medical help (up to `revivals` times per run). It comes from a
**separate bank**, `questions/medical.json` (35 bilingual single-choice questions on literature, music,
culture, the Second World War and modern history that the level banks do not ask), picked at
random: never twice in one run, and not one of the last 12 help questions asked this session, so a
question that was just failed is not offered again after Restart. A correct answer restores
`revive_hp` HP and the player retries the task they failed (answers reshuffled; matching/chronology
start over), keeping their score and completed tasks. A wrong answer means no medical help,
leaving Restart and Levels. These numbers are preliminary and will be tuned after playtesting with timers and enemies.

## BOSS — `"boss"` in `data/levels.json` (id 11)

A separate 50-task endurance run, not part of the ten-level campaign and never counted in the total
score or the leaderboard total. It takes five tasks from every level's verified bank, ordered by era
and, within an era, from easier to harder. Over the run the timer shrinks to `time_floor` (55 %) of
`time_per_question` and targets speed up by `speed_ramp` (+60 %); three enemies fight throughout.
The player starts with `medkits` (2) medkits, gets one more every `medkit_every` (10) tasks, and
uses one with **H** for `medkit_hp` (35) HP; medical help works as on the levels. Scoring at least
`pass_percent` (60 %) defeats the BOSS.

- **Reveal:** the first time level 10 is passed, the results screen is followed by «BOSS АШЫЛДЫ!» /
  "BOSS UNLOCKED", and the level screen shows a red BOSS tile centred beneath level 8.
- **Level 10** is a normal 5/5 level (the arcade gallery); it is no longer marked BOSS.

## New Game and Unlock Everything
- **Settings → «Жаңа ойын» / New Game** (two presses) restarts the campaign on this device: level
  results, unlocks, BOSS results and history of the current profile. It never deletes anything online
  (leaderboard rows, attempts, achievements) and never removes Unlock Everything.
- **«Барлығын ашу» / Unlock Everything** (formerly Demo mode) opens every level, the BOSS and every
  character. It is locked until the player has defeated the BOSS once; that entitlement is kept in its
  own file (`progress[_uid]_entitlements.json`) and, for a Google account, in Firestore
  `achievements/{uid}`, so it survives New Game, sign-out and sign-in. **Administrators** have it at
  once: an administrator is a Google account with a document `admins/{uid}` in Firestore, which only
  the project owner can create (see `docs/online.md`); the game only reads it, never a local flag.
- Settings explains the difference: campaign progress lives on the device; online results and
  permanent achievements belong to the account.

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
- **Unlocks (total score):** the total is the sum of each level's **best** score, so a replay only
  counts when it beats that level's best and farming one level cannot inflate it (online, the same
  sum is the leaderboard total). A level opens when the total reaches its `unlock_score` and then
  stays open (saved in `unlocked`; levels opened under the old pass-the-previous-level rule stay
  open). Proposed thresholds (provisional, awaiting playtest approval), levels 1–10: 0, 750, 1500, 2350,
  3200, 4050, 4900, 5750, 6650, 7600 (lowered by up to 150 after the November question overhaul changed
  the task counts) —
  each is at or below the sum of the pass marks of all earlier levels (so passing every level at its
  pass mark is enough), and from level 3 on above what any single earlier level gives. They are
  computed without the "double score" ability (+100–200 per level), which only gets there sooner.
  Settings →
  "Демо режимі" opens every level that has questions (for presentations); "Прогресті тазалау"
  (pressed twice) clears everything.
- A run that ends in defeat (no medical help left, or a wrong medical-help answer) is saved with
  `completed: false` and 0 stars.

## Themes — `data/themes.json`

One entry per era: `sky_top`, `sky_horizon`, `ground`, `fog_color`, `fog_density`, `sun_color`,
`sun_energy`, `sun_pitch`, `sun_yaw`, `ledge` (rampart colour) and `ledge_style` (`earth`, `mound` (burial mound, steppe eras), `gallery` (level 10: arcade booth with counter, curtains, bunting, bulbs and a shañyraq emblem), `fortress`,
`palisade`, `sandbags`, `rock`, `stand`), `placard` (unused since answers moved to screen labels), `target_style`
(`soldier`: outlined soldiers with floating answer labels; `gallery`: plaques on the gallery tracks), `props` (list of `[kind, count]`: kurgan, hill, mountain, yurt, tent, banner,
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
| `unlock` | `{"level": N}` or `{"passed": N}` | Optional. The character opens when level N opens, or once level N has been passed. Schedule (approved 16 Nov 2026): Томирис 1, Мөде 2, Күлтегін 3, Қайырхан 4, Керей 5, Қасым 6, Қабанбай 7, Абылай 8, Әлия 9, Мәншүк after passing 9. Locked characters are greyed out, say how they open and cannot be started with; demo mode opens all. |

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
| `difficulty` | no (expected) | 1 introductory, 2 moderate, 3 demanding. The audit checks that the average rises from levels 1–3 to 4–6, 7–9 and 10, that levels 4–6 have at most a fifth level-1 tasks and levels 7–10 none. |
| `en` | no (expected) | English version: the same fields (`question`, `answers`, `extra_answers`, `pairs`, `items`, and `locations` as a list of names) **in the same order**, so the correct answer is found by position. Ids and answer mapping are shared by both languages. |

**Content rules** (checked by `question_audit.gd`, report: `godot --headless --path . --script
res://tools/audit_questions.gd`). A run asks every task of a level, so within a level:
- no two prompts are near duplicates (60 % shared word stems);
- no two choice tasks have the same correct answer;
- no prompt, matching pair or chronology event states another task's answer (its year, or all
  significant words of it); wrong options may repeat freely;
- no prompt contains its own answer, unless a wrong option shares the same words.
Words are compared by their first five letters so Kazakh endings do not hide a repeat.
Distractors should come from the same era and region: rulers of the same century, real
neighbouring states, close dates.

Examples of every type: `tests/fixtures/all_types.json`.

### 1. `single_choice` — one correct answer
`answers`: exactly 4 unique texts. `correct`: one of them.
`extra_answers` (optional, also for `fill_blank`): 1–4 hand-written wrong answers used as decoys on
harder levels. Each must be the same kind as `correct` (a date if the answer is a date, no digits
otherwise), must not restate an option ("1456 ж." beside "1456"), and should be plausible for the
question: rulers beside rulers, rivers beside rivers. Leave it out when no sensible one exists.

### 2. `matching` — pair up two columns (person ↔ event, state ↔ year, term ↔ definition)
`pairs`: 2–4 objects `{ "left": ..., "right": ... }`. Left texts unique, right texts unique.

### 3. `chronology` — put events in order
`items`: 3–5 unique texts **in the correct order**. The game shuffles them.

### 4. `map` — find a place on the map of Kazakhstan
`locations`: exactly 4 objects `{ "name": ..., "x": 0–1, "y": 0–1 }`, at least 0.05 apart, where x/y are positions
on the map image (0,0 = top-left, 1,1 = bottom-right). `correct`: one of the names.
Markers show numbers 1–4, not names. The map (`assets/maps/kazakhstan.svg`, Natural Earth) opens as a
HUD overlay under the question (`map_overlay.gd`); while it is open the mouse moves a reticle over
the map instead of turning the camera, a shot hits the marker under the reticle, and enemies hold
their fire. Wrong pins should be **nearby** plausible places (a neighbouring city or region), not the
other end of the country.
Get x/y with `python tools/build_map.py --point <lat> <lon>` and keep `lat`/`lon` in the entry
for review (the tests check that x/y match them).

### 5. `image` — identify the period of an image or artifact
`image`: `res://` path to an image in the project. The photo is shown in a HUD panel under the
question (`image_panel.gd`, aspect ratio kept, at most 42 % × 30 % of the screen) with its author and
licence; the answer soldiers stay in the arena with their labels below their feet. Use only images with a licence that allows reuse, and add
them to `assets/CREDITS.md` and the in-game credits (`main_menu.gd`). `answers` and `correct` as in `single_choice`.

### 6. `fill_blank` — fill in the missing word
`question` must contain `___` where the blank is. `answers` and `correct` as in `single_choice`.

## Languages — `locale.gd`, `locale/en.json`

Kazakh is the default; the **KZ / EN** switch is in the top-right corner of the main menu and the
choice is saved in `user://settings.cfg`. Interface text goes through Godot's TranslationServer:
scene texts translate automatically and code wraps its strings in `tr()`. The English strings are
in `locale/en.json`, keyed by the Kazakh text (the fallback locale is `kk`, so a text without an
English entry stays Kazakh). Level titles, character cards and ability names are translated the
same way. Questions carry their English text in each task's `en` block; `Locale.localize_question()`
swaps it in by position when the game loads a level, so ids, scoring and the correct answer do not
depend on the language. The tests check that every interface text has an English entry and that
every task is fully English with its correct answer in the same place.

## Running the tests

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

The exit code is the number of failed checks; `0` means everything passed.
