# Importing questions from TXT files

Teammates can write questions in a plain UTF-8 text file instead of JSON. One tool,
`tools/questions_txt.py` (Python 3, no extra packages), converts in both directions and checks the
format; the game's own audit and tests then check the content. The format and examples are in
`docs/question-template.txt`.

## The format in short

```
ID: otyrar-15                (optional: numbered automatically, e.g. otyrar-16)
TYPE: single_choice          (single_choice, fill_blank, matching, chronology, map, image)
DIFFICULTY: 2                (optional, 1-3)
Q: Kazakh question
Q_EN: English question
A: *correct | wrong | wrong | wrong
A_EN: *correct | wrong | wrong | wrong      (same order, same * as A)
EXTRA: decoy | decoy                        (optional, levels 5-10 show them)
EXTRA_EN: decoy | decoy
```

- `fill_blank`: the question contains `___` in both languages.
- `matching`: 2–4 `PAIR: left = right` lines and as many `PAIR_EN` lines.
- `chronology`: 3–5 `ITEM` lines, **earliest first**, and as many `ITEM_EN` lines.
- `map`: four `PLACE: name | latitude | longitude` lines (mark the right one with `*`) and four
  `PLACE_EN: name` lines. The tool computes the map position; places must be at least ~2.6° apart.
- `image`: `IMAGE: abai.jpg` — only pictures already in `assets/images` (they have licences).
- Blank line between questions; lines starting with `#` are comments.

## Workflow

1. **See the current bank as text** (a good starting point):
   `python tools/questions_txt.py export otyrar > otyrar.txt`
2. **Check a teammate's file** (writes nothing; errors name the line):
   `python tools/questions_txt.py check otyrar_new.txt`
3. **Import** — replaces `questions/otyrar.json` (the old version stays in git):
   `python tools/questions_txt.py import otyrar_new.txt --level otyrar`
   Level names: saka, huns, turkic, otyrar, golden_horde, kazakh_khanate, dzungar, xviii_xix,
   xx_century, independence, and `medical` for the medical-help bank.
4. **Content audit** (leaked answers, repeated facts, difficulty by level):
   `godot --headless --path . --script res://tools/audit_questions.gd`
5. **Tests**: `godot --headless --path . --script res://tests/run_tests.gd`. If a level now has a
   different number of tasks, two checks tell you what to update: the per-level maximum score in
   `firestore.rules` (tasks × 100) and possibly the unlock thresholds in `data/levels.json`.
6. Look at the new tasks in the game in both languages (main menu → KZ / EN), then commit.

`export` followed by `import` reproduces every current bank exactly (checked for all eleven files).
