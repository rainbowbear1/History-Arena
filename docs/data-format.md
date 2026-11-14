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
| `question_file` | `res://` path | Question file for this arena. The level stays locked until this file exists. |
| `time_per_question` | seconds | Time limit per task. |
| `target_speed` | number | Multiplier for target movement speed. |
| `extra_decoys` | whole number | Extra fake-answer targets added on top of the 4 options. |
| `enemies` | whole number | Enemies active in the arena. |
| `lives` | whole number ≥ 1 | Lives at the start of the level. |
| `revivals` | whole number | How many times the medical-help task can restore a life. |
| `pass_percent` | 0–100 | Score needed (as % of the maximum) to pass and unlock the next level. |

`lives` and `revivals` are used now. The timer, speed, decoys, enemies and pass mark are validated
and will be used by the gameplay as later milestones land.

### Lives and medical help
Each life holds 100 HP and every mistake costs 10 HP. When HP runs out the player loses a life and
HP refills. When the last life is lost the "СІЗ ЖЕҢІЛДІҢІЗ!" screen offers one historical question
as medical help (up to `revivals` times per run). It asks a `single_choice` or `fill_blank` question
from the same level, preferring one the player got wrong. A correct answer gives back one life with
full HP and play continues with the next task, keeping the score; a wrong answer means no medical
help, leaving Restart and Levels.

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
Pins show numbers 1–4, not names. Put the map image at `assets/maps/kazakhstan.png` (2:1 aspect,
e.g. 2048×1024); until then a plain placeholder board is shown.

### 5. `image` — identify the period of an image or artifact
`image`: `res://` path to an image in the project. `answers` and `correct` as in `single_choice`.

### 6. `fill_blank` — fill in the missing word
`question` must contain `___` where the blank is. `answers` and `correct` as in `single_choice`.

## Running the tests

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

The exit code is the number of failed checks; `0` means everything passed.
