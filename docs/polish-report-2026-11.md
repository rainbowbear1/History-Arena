# Post-playtest refinement — report (15 November 2026)

Work done after the full playtest of M12–M16, as milestones M17–M24 on `main` (not pushed). The
state before this work is tagged `checkpoint-before-polish` (3eb991f).

## Milestones

| # | Commit | What changed |
|---|---|---|
| M17 | `fb6e037` | Question-bank overhaul: all ten banks rewritten (same-era distractors, no leaks, no repeated facts, harder later levels, new Independence content), difficulty 1–3 and English text on every task, automatic audit (`question_audit.gd`), separate medical-help bank, map pins may be nearby places. Firestore score caps and the provisional unlock thresholds follow the new task counts. |
| M18 | `8e5a633` | Answer formations for 3–6 answers and matching: one ground row up to four, ground + rampart for five or six; labels in bands above heads / below feet, never wider than the gap to the neighbour, never overlapping; aiming at a label counts as aiming at its soldier. |
| M19 | `6c0ee65` | Map as a HUD overlay with numbered markers and a mouse-driven reticle; photos in a framed HUD panel with credit; 3D boards removed. |
| M20 | `7734f9f` | Medical help asks from `questions/medical.json` (35 tasks), random, never twice per run, not the last 12 asked (so a failed one is not repeated after Restart). |
| M21 | `d48c0fd` | Enemy health bars (one slim bar with a draining trail), collapse-and-sink death, toughness `1 + floor(TTK / cooldown)`; the photo turns see-through when a soldier is behind it. |
| M22 | `da473c0` | Independence level as an arcade shooting gallery: three moving tracks in alternating directions, plaques that loop behind curtains, tin ducks that block shots without penalty, speed ramp and a finale flock, booth decor, optional per-level music slot. |
| M23 | `0c43fbe` | KZ / EN switch in the main menu (saved), Godot TranslationServer for the interface (`locale/en.json`), English questions swapped in by position; character cards no longer give answers away; button padding, menu spacing, feedback pop. |
| M24 | `9c42df9` | Rounder soldiers (tapered limbs, shaped torso, round head and hands) and round gun barrels. |

## Tests

- `tests/run_tests.gd`: **855 checks, 0 failed** (812 before this work, plus new checks for the audit,
  localization, layouts at five window sizes, HUD map and photo, medical bank, enemy bars and death,
  weapon toughness, the gallery).
- `tests/firebase` (security rules on the emulator): **9 / 9 passed** after updating the score caps.
- `tools/audit_questions.gd`: 0 problems in all ten levels and the medical bank. Average difficulty by
  band: 1.97 (levels 1–3), 2.13 (4–6), 2.37 (7–9), 2.53 (10).
- Web export: built after every milestone; the build at `9c42df9` was loaded in a browser: startup →
  guest → menu → EN switch (live) → level select → character select → level 1 in English, no errors
  except the embedded preview refusing pointer lock.
- Performance (1280×720, same machine, against the checkpoint): level 7 keeps 588 draw calls
  (triangles 12k → 26k), the gallery 128 → 183 draw calls; both hold the 60 fps cap.

## Questions

- Every change, per level and id, with before/after text: `docs/question-overhaul-2026-11.md`
  (10 kept, 24 rewritten, 96 replaced, 2 removed, 3 new; 132 → 133 level tasks + 35 medical).
- Every task with its answer and decoys: `docs/content-review.md`.
- Points that need a historian's eye (debated dates, attributions, modern politics):
  `docs/history-review-checklist.md`.

## Screens checked (rendered with `tools/screenshots.gd`, real window)

Six-answer formation (level 7), four matching pairs at 1024×768 (level 9), HUD map (Semey) and photo
(Abai) on level 8, enemy health bar, the gallery (choice and matching), English menu and gallery,
the main menu and level select after the button polish, rounded soldiers on level 6.

## Known remaining issues

- Not played with mouse and keyboard by me (the preview cannot lock the pointer); please playtest,
  especially the map reticle, the gallery's moving plaques and duck timing.
- The map overlay hides the arena while it is open; enemies hold fire then, but the player cannot
  see them approach.
- Labels of the bottom gallery track can sit behind the passing ducks (by design, briefly).
- Fonts: still Godot's built-in font (it covers all Kazakh letters). A custom display/body pair is
  waiting on your approval to download (see below).
- Character progression is not implemented yet (proposal below).
- XVIII–XIX and XX century arenas still use the wall-style backdrop; no Orbulak vantage point.
- Google sign-in still untested with real accounts; the Firebase project and GitHub repository are
  still to be created by you. Nothing was pushed or deployed.

## Needs your approval

1. **Unlock thresholds** (still provisional, lowered slightly because the task counts changed):
   0, 750, 1500, 2350, 3200, 4050, 4900, 5750, 6650, 7600.
2. **Character unlocks** — proposed: a character opens when the level of its era opens, so a
   strong player who opens two levels at once also gets two characters (no extra grind):
   Tomyris (from the start), Modu (level 2), Kul Tegin (3), Qayir Khan (4), Kerey Khan (5),
   Qasym Khan (6), Kabanbay Batyr (7), Abylai Khan (8), Aliya Moldagulova (9), Manshuk Mametova (10).
   Every level's suggested hero is open by the time the level is. Locked characters stay visible
   with "opens with level N"; demo mode opens all.
3. **Fonts** — permission to download two OFL fonts from Google Fonts (github.com/google/fonts), check
   their Kazakh glyphs (Ә Ғ Қ Ң Ө Ұ Ү Һ І) and use them: a display face for titles and a
   body face for questions and labels (candidates: PT Sans / PT Serif, Fira Sans, Noto Sans).
4. **Level 10 timer** raised from 10 s to 16 s per task to allow for moving targets.
5. The rewritten historical content (checklist above).
