# History Arena — long-term vision

This is the direction the game grows toward **after** the defense build. It is not a to-do list
for November; see `docs/defense-plan.md` for what is actually being built now.

## The idea
History Arena is not a conventional shooter where enemies chase the player. Each of the ten levels
is a **distinct historical setting** with its own **designated protagonist**. The player answers
history questions by shooting **highlighted soldiers or other fitting targets** that carry the
answers. Background soldiers make the scene feel like an ongoing historical event through light,
scripted movement; they do not constantly attack the player. A wrong answer triggers a fitting
reaction in the scene that explains the HP loss (for example, an enemy lands a shot).

Each level ends with an atmospheric moment, such as a fade to white, before the results screen.

## Level ideas
| # | Era | Protagonist / scenario (draft) |
|---|---|---|
| 1 | Saka | Tomyris on horseback leading a small force, luring pursuing Persians into an ambush; the player aims backward and shoots highlighted pursuers. |
| 2 | Xiongnu (Huns) | Modu Chanyu fighting alongside his archers. |
| 3 | Turkic Khaganate | Undecided. |
| 4 | Otyrar | Dry, foggy siege; the player defends near or on the fortress walls. The ending shows the betrayal and the opening of the gates. |
| 5 | Golden Horde | Undecided. |
| 6 | Kazakh Khanate | Undecided. |
| 7 | Dzungar wars | An Orbulak-inspired defensive battle: the player on high ground with allied soldiers. |
| 8 | 18th–19th centuries | Undecided. |
| 9 | 20th century | Undecided. |
| 10 | Independence | A peaceful recreational shooting gallery; the BOSS challenge is an intense shooting competition. |

Historical details of each scenario must be checked before they are built; none of the above is
final content.

## Art direction
- Lightweight, stylized **low-poly** look (in the spirit of Dani's games), with recognizable
  historical environments, characters and equipment.
- Answer carriers become low-poly soldiers of the era with their **answer label above the head**,
  readable from the player's position. Existing target states stay: selected (gold), done (green),
  wrong (red flash).
- Level 10 has no soldiers: gallery targets (boards, plates, ribbons) in a celebratory modern setting.
  It must still work as the assignment's BOSS level.
- Later: switching between first- and third-person cameras, and visible hands and weapon in first person.

## How it maps onto the current game
The ten levels reuse one quiz-shooter engine. What changes per level is data and presentation:
environment, protagonist, weapon, background soldiers and the ending. The quiz rules (six task
types, −10 HP per mistake, medical help, scoring, stars) stay the same everywhere.

**Tension with the assignment to keep in mind:** the assignment asks the player to *choose* one of
ten characters, each with HP, speed, weapon, ability and defense. A designated protagonist per
level must therefore stay compatible with character choice (for example: the level's protagonist
is preselected, and free choice remains available).

## Constraints
- Must stay light for the web build (GL Compatibility renderer, low-poly meshes, small textures).
- Labels must stay readable on phone-sized screens for the mobile demo.
- Only use art we made or that has a licence allowing use and redistribution; record sources and
  licences in the repository.
