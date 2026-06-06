# Changelog — Magick With Friends

Dev-session patch notes, newest first. One entry per working session (dated). Player-facing
features, fixes, and notable under-the-hood work, with PR numbers for traceability. This is a
human-readable log of *what changed and why it mattered* — not a substitute for `DESIGN.md`
(decisions/roadmap) or `CLAUDE.md` (structure/rules).

---

## 2026-06-06

*4 PRs merged (#36–#39) — visual scenes + the animation subsystem + the round start-gate*

### ✨ Features

- **Characters animate now.** Players play an idle↔run blend; skeleton enemies idle↔run, **face**
  their target, and **swing** on melee. Built on one reusable `LocomotionAnimator` + an AnimationTree
  per visual scene (a OneShot layers the enemy attack over locomotion). (#37, #39)
- **Separate visual/rig scenes.** The model + AnimationTree live in committed `player_visual.tscn` /
  `enemy_visual.tscn` that each entity instances — the normal Godot pattern, editable in-editor.
  Replaced the earlier runtime model-load/capsule-fallback machinery (dropped `CharacterVisual`). (#36)
- **Round start-gate.** The horde no longer spawns from boot — the wave director boots **paused** and
  the host types **`start`** in the dev console to begin, so you can set up first. (#38)

### 🛡️ Stability & Netcode

- **Remote-animation jitter, fixed twice.** First the locomotion speed was sampled on the render
  clock while the body moves on the physics clock (a stair-stepped signal) — moved to
  `_physics_process`. Then the deeper one: deriving speed by differentiating a *replicated* position
  is jittery because remote positions arrive in held network snapshots — so we now **replicate the
  speed/facing driver** itself (the owning peer authors it) and animate locally from that steady
  value. The idiomatic Godot multiplayer rule: replicate the driver, never the animation state. (#37)

### ⚙️ Under the Hood

- **Cleared 3 GDScript warnings** (unused-signal, integer-division, incompatible-ternary) — benign,
  but the debugger panel is quiet again so real issues stand out. (#38)

---

## 2026-06-05 (continued)

*6 PRs merged (#30–#35) — combat got real, models came in, docs reframed*

### ✨ Features

- **BLEND became real combat.** A 2×2 **Form × Element** spell matrix with **entity reactions** —
  lightning chains between nearby units (allies included), fire applies a burn DoT — resolved
  host-central in `systems/reactions/`, index-stable via a new `SpellCatalog` autoload. (#33)
- **KayKit character models.** Swapped the placeholder capsules for the **Mage** (player) and
  **Skeleton** (enemy) art packs, with the hit-flash reworked to tint textured multi-surface meshes
  via a material overlay. (#34)
- **Dev console `enemies` toggle.** `enemies off | on | clear` to pause/clear the horde while
  testing. (#35)

### ⚙️ Under the Hood

- **Docs.** Started this `CHANGELOG`; an accuracy/de-duplication pass across `CLAUDE.md` / `DESIGN.md`;
  and a light **reframe** naming the reusable multiplayer spine vs. the spell-game built on it. (#30–#32)

---

## 2026-06-05

*9 PRs merged (#21–#29) · 3 reviews/audits · 2 bugs caught mid-build*

### ✨ Features

- **Damage hit-flash (players + enemies).** Entities momentarily flash a color when they take
  damage. Built as a reusable, game-agnostic `HitFlashComponent` (drop it on any entity in any
  future level/game), and the enemy's old hand-rolled flash was rebuilt onto it — one
  implementation for both. Visible to teammates; host-authoritative + cosmetic-only. (#27)
- **First-person self-damage screen-flash.** A red screen-pulse when *you* take a hit — because in
  first-person you can't see your own body flash. Routed through a new
  `GameEvents.local_player_damaged` signal (so audio/controller-rumble can hook in later). (#28)
- **Movement retuned + made honest.** Player speed normalized so `max_speed` is the real binding
  cap (~12 u/s, ~3× enemy speed for kiting); removed misleading scene overrides that did nothing. (#26)

### 🛡️ Stability & Netcode

- **Verified per-peer authority propagation.** Investigated and *disproved* a claimed "fatal"
  netcode bug — added an in-game `[AUTH]` diagnostic and confirmed each client correctly owns its
  own player. The remaining online gap is cross-machine transport (NAT/relay/latency), not
  authority; docs corrected to match. (#24)
- **Crash & edge-case hardening** (from a full code review): wave spawner no longer crashes on
  mid-spawn teardown; dev console no longer leaves input frozen if closed at the wrong moment;
  killing an enemy no longer spams network errors. (#21)

### ⚙️ Under the Hood

- **Collision layers.** Replaced the "everything on layer 1" placeholder with named layers
  (world / players / enemies / projectiles) + explicit masks — tuned to keep the friend-slop
  shoving chaos while making projectile hits intentional. (#25)
- **Performance.** Enemy AI and the HUD stopped doing wasteful per-frame work (full tree scans,
  redundant node lookups, per-frame string rebuilds). (#22)
- **Architecture tidy-up.** Live enemy count flows through the event bus instead of being polled;
  players carry a real `peer_id` instead of having it parsed out of node names (a latent foot-gun,
  removed in both enemy melee and projectiles); de-duplicated the HUD overlay-fade code. (#23)
- **Docs.** Refreshed `CLAUDE.md`'s file map to match reality (several "roadmap" systems were
  actually built; the event bus and new component weren't listed). (#29)

### 🐛 Bugs caught mid-build

- **Hit-flash wired to nothing** — a Godot gotcha where typed-node `@export`s silently resolve to
  `null` from a hand-authored scene. Caught with a headless probe; fixed with explicit `NodePath`
  resolution.
- **Self-damage flash worked on the client but not the host** — a host/client timing asymmetry
  (the host pre-applies damage before the value-sync). Diagnosed, fixed, and verified headlessly.

### 🔍 Reviews & audits (no code, but shaped the work)

- High-effort **code review** of the prior feature cluster → 10 findings → PRs #21–#23.
- Analysis of an external (Gemini) **critique** → confirmed the good points (collision layers),
  debunked the loud-but-wrong one (the "fatal authority bug") → PRs #24–#25.
- Full **architecture audit** (6 categories, top-5 risks ranked) → the worthwhile fix became #26;
  the rest were consciously deferred to their right milestones (spell-sync-to-host → acquisition PR;
  interpolation → online milestone; spawn points → beyond-slice).
