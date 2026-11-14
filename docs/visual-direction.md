# Visual direction (planned, not implemented yet)

Gameplay comes first; this is the art direction to apply once the required systems are done.
Until then the arena keeps its simple box targets.

## Levels 1–9: historical soldiers
- Answer targets become **low-poly historical soldiers** of the level's era
  (Saka warriors, Hun horsemen, Turkic warriors, Otyrar defenders, Golden Horde, Kazakh batyrs,
  Dzungar-era fighters, 18th–19th century, 20th century).
- Each soldier carries its **answer label above its head**, readable from the player's spawn point.
- The existing target states still apply: selected (gold), done (green), wrong (red flash).
- Shooting a soldier replaces the current board tilt with a short hit reaction.

## Level 10 (Independence era): peaceful shooting gallery
- No soldiers. Level 10 is a **peaceful shooting gallery**: answers on gallery targets
  (boards, plates or ribbons) in a celebratory, modern Kazakhstan setting.
- It must still work as the assignment's required **BOSS** challenge: hardest settings in
  `data/levels.json` (shortest timer, fastest targets, most decoys, fewest lives) and a boss-style
  round. "Enemies" there should be gallery hazards or moving obstacles rather than people.

## Constraints
- Keep it light enough for the web build (GL Compatibility renderer, low-poly meshes, small textures).
- Labels must stay readable on phone-sized screens for the mobile demo.
- Only use art we made or that has a licence allowing use and redistribution; record sources and
  licences in the repository.
