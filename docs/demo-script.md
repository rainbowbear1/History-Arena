# Defense demo script (10–15 minutes)

Follows the 12 points from the assignment ("Қорғау кезінде студент не көрсетуі керек?").
Rehearse once with the exact build and browser you will use.

## Before you start (5 minutes before)
- [ ] Open the hosted build (or `build/web` served locally) in Chrome or Edge, full screen, sound off.
- [ ] Main menu → **Баптаулар** → turn on **Демо режимі** (all levels open). Optionally reset progress
      first with **Прогресті тазалау** (press twice) so the stars you earn are fresh.
- [ ] Have these open in tabs: the GitHub repository, `README.md` (architecture), the Firebase Console (Firestore → `players`).
- [ ] Mouse connected (the game needs mouse + keyboard). Click inside the game once to lock the mouse.

## The demonstration
| # | Required point | What to do | What to say |
|---|---|---|---|
| 1 | Google sign-in | Press *Google арқылы кіру* and sign in with a Google account; the menu shows your Google name. Reload the page: still signed in. | "Sign-in uses Firebase Authentication with Google, so every player is a real, unique account; the session survives a reload. The game holds no secrets; results wait in an outbox until the server accepts them." (`docs/online.md`) |
| 2 | Choose a character | Ойнау → level 1 → the character screen. Hover a few characters, then pick Томирис. | "Each level suggests its historical protagonist; any of the 10 can be chosen. HP, speed, weapon, ability and defense really change play." |
| 3 | Several levels 1–10 | Play a task in level 1, then quickly open level 4 (Отырар: fog, walls), level 9 (WWII snow) and level 10 (shooting gallery, BOSS). | "Ten eras, each with its own setting; difficulty grows: less time, faster targets, decoys, more enemies, fewer resources." |
| 4 | Core mechanic | Shoot the soldier with the right answer. Show a matching task (top row, then bottom) and a chronology task; show a map or image task. Press **E** for the ability. | "Six task types, all answered by shooting." |
| 5 | Life runs out | Answer wrong on purpose until HP reaches 0 (a 90-HP character like Әлия Молдағұлова gets there fastest; each wrong answer is −10 and an enemy visibly lands a shot). | "Wrong answer: −10 HP and an enemy shot; enemies on the flanks also fire telegraphed shots you can dodge." |
| 6 | Historical task for medical help | On «СІЗ ЖЕҢІЛДІҢІЗ!» answer the medical-help question correctly. | "It asks a question you missed earlier, never the one you just failed." |
| 7 | Correct / wrong algorithm | Point at the result: +50 HP and the failed task comes back. (Optionally show a wrong medical answer → Restart/Levels.) | Correct +100 · wrong −10 · 0 HP → medical help → correct = HP back + retry, wrong = no help. |
| 8 | Results are saved | Finish a short level or show the results screen; go to the level list (stars, best score); reload the page and show they are still there. | "Score, correct, wrong, playtime and stars are saved per attempt; the same record is stored in Cloud Firestore under the player's account, and best results follow the player to another computer." |
| 9 | Rating | Main menu → **Рейтинг**: players, totals, your best and rank. Optionally show the `players` rows in the Firebase Console. | "Firestore security rules check every write on the server: only your own account, only scores a level allows, best scores only rise, every best is backed by a write-once attempt record. What rules cannot stop is documented in docs/online.md." |
| 10 | Mobile version | Open the GitHub Pages link on a phone (try it before the defense): sign in and open **Рейтинг**. | "The game itself is a mouse-and-keyboard FPS; the phone shows sign-in and the leaderboard; full play on phones would need touch controls (future work)." |
| 11 | Repository | Open the GitHub repository: commits per milestone, tests, docs. | "Every milestone was tested (683 Godot checks + 9 security-rule tests) before it was committed." |
| 12 | Architecture | Show the diagram in `README.md`. | Scenes → quiz manager → task handlers; data files for levels/questions/characters/themes; autoloads for progress and the online backend (Firebase bridge, rules). |

## The question you will be asked
*"Неліктен дәл осы алгоритмді таңдадыңыз және ойын механикасы Қазақстан тарихын меңгеруге қалай көмектеседі?"*
Use the "Why this algorithm helps learn history" section of `README.md`: six task types train
different skills; mistakes are shown and revisited (medical help, retries); difficulty and decoys
reward real knowledge; points come only from answers, so the leaderboard measures history.

## If something goes wrong
- **Mouse not captured:** click inside the game. **Esc** opens the pause menu.
- **A level seems locked:** Settings → Демо режимі.
- **Browser blocks the page:** use the locally served copy (`python -m http.server 8080` in `build/web`).
- **Google sign-in fails during the demo:** check pop-ups are allowed and the site is in Authorized domains; otherwise use guest play and show the rule tests (`tests/firebase`).
