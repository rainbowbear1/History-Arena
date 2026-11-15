# Defense plan (defense on 24 / 26 November 2026)

Goal: a stable, convincing first version that meets the assignment (Technical Assignment No. 3,
pages 3 and 7–10), not the full vision in `docs/vision.md`.

## Status on 15 November
| Assignment requirement | Status |
|---|---|
| FPS quiz-shooter core (shoot the target with the right answer) | Done |
| 10 arenas with rising difficulty (★–★★★★★, level 10 BOSS) | Done (M7): all 10 levels have 12–15 tasks; awaiting your accuracy review |
| 10 characters with HP, speed, weapon, ability, defense | Done (select screen, stats applied, 6 abilities) |
| 6 task types (single choice, matching, chronology, map, image, fill-in) | Done (M7): Natural Earth map, 8 licensed images, every type used across the game |
| Difficulty: faster targets, less time, more decoys, enemies, fewer resources | Done (timer, speed, decoys, enemies, boss, fewer ability uses) |
| HP −10 per mistake, +100 per correct answer | Done |
| "Жан біткенде" medical help | Done (single HP pool, help restores 50/40/30 HP, retry the task) |
| Results saved (score, level, correct, wrong, playtime), progress | Done: on the device per account (M6) and in Cloud Firestore (M11) |
| Google login, profile, leaderboard | M11 (15 Nov, priorities changed: independent of the Game Hub): Firebase Authentication (Google), Firestore leaderboard, security rules, tested on emulators; **goes live after your Firebase project setup** (docs/deploy.md) |
| Security items (OAuth, no secrets in frontend, validation, rate limiting, leaderboard anti-cheat) | Firestore rules: own account only, score caps, write-once attempts, 5 s rate limit; no secrets; old toy login removed from Git history; limits in docs/online.md |
| GitHub repository, deployed build | GitHub Pages ready (`tools/publish_pages.sh`); **waiting for your repository and approval to push** |

## Mandatory vs optional
**Mandatory before the defense**
1. Persistent results, stars and level unlocks; results screen with correct/wrong/time (M6).
2. Questions for levels 4–10 using all six task types, plus a map and images for the map/image tasks (M7).
3. Google sign-in and an online leaderboard (Firebase, M11), with an offline guest fallback.
4. A reliable web build, hosted over HTTPS, and a GitHub repository (M10).

**Optional, only if time allows** (in this order)
- Per-level presentation: background soldiers instead of chasing enemies, a reaction shot on wrong
  answers, per-level colours/fog/props, designated protagonist preselected (M8).
- One showcase level (Otyrar is the strongest candidate: fog, walls, gate ending).
- Touch controls for phones. Camera switching, hands/weapon models: after the defense.

## Milestones and target dates
| Milestone | Content | Target |
|---|---|---|
| M6 Progress & results | Save file, stars, unlocks, results screen, fade-to-white ending, demo unlock/reset in Settings | 15–16 Nov |
| M7 Content | Levels 4–10 question files (~13 tasks each, all six types), map board image, image tasks | 16–19 Nov (needs your review) |
| M8 Presentation | Done: low-poly soldiers, ten themed environments, enemies at posts with dodgeable shots, reaction shot, gallery level 10 | 15 Nov |
| M9 Auth & Hub | Login screen with Google, backend adapter, API contract, offline fallback; real connection when the Hub is ready | 17–21 Nov (parallel) |
| M10 Defense build | Prepared: README (architecture, status), docs/demo-script.md, docs/deploy.md; **remaining: hosting, GitHub push, Hub bridge (your/Hub team actions)** | 15 Nov → 21–23 Nov |

## Critical path
Content for levels 4–10 (M7) → your accuracy review → final build. The Hub integration (M9) runs
in parallel but depends on classmates; the game must remain fully demonstrable offline if it slips.

## Risks
| Risk | Mitigation |
|---|---|
| Historical mistakes in new questions | You (or the teacher) review every new file; questions only use well-established facts |
| Hub backend not ready or undecided | Backend adapter with an offline implementation; API contract document for the Hub team |
| Google sign-in popups blocked inside the game canvas | Use the redirect flow or an HTML button over the canvas |
| Google OAuth needs HTTPS and an authorised domain | Host on HTTPS (Hub domain, GitHub Pages or itch.io); agree the domain with the Hub team |
| Levels locked during the demo | Demo mode in Settings unlocks all levels; reset progress button |
| Images without a clear licence | Use public-domain/CC images with recorded credits, or simple self-made images |
| Late changes breaking the build | Automated tests + export check before every commit; one commit per milestone |

## Dependencies on others
- **You:** a Firebase project (docs/deploy.md step 1) and its public web config; a GitHub repository.
- **Game Hub team (later, optional):** reconnecting through the same bridge contract (docs/online.md).
- **You:** review of new questions; the choice between designated protagonists and free character
  choice (see `docs/vision.md`); scenarios for levels still marked "undecided"; a GitHub repository.
