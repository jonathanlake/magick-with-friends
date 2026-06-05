# Changelog — Magick With Friends

Dev-session patch notes, newest first. One entry per working session (dated). Player-facing
features, fixes, and notable under-the-hood work, with PR numbers for traceability. This is a
human-readable log of *what changed and why it mattered* — not a substitute for `DESIGN.md`
(decisions/roadmap) or `CLAUDE.md` (structure/rules).

---

## 2026-06-05

*9 PRs merged (#21–#29) · 3 reviews/audits · 2 mid-flight bugs squashed*

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
