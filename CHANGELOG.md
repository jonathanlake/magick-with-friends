# Changelog — Magick With Friends

Dev-session patch notes, newest first. One entry per working session (dated). Player-facing
features, fixes, and notable under-the-hood work, with PR numbers for traceability. This is a
human-readable log of *what changed and why it mattered* — not a substitute for `DESIGN.md`
(decisions/roadmap) or `CLAUDE.md` (structure/rules).

---

## 2026-06-10 (milestone 2: spine/game restructure · milestone 1: online verified)

*The directory tree now tells the truth: framework/ is the product, games/magick/ is the fixture*

### 📐 Direction

- **Real online is PROVEN (milestone 1 ✅).** A remote friend joined a real session over the
  internet via **playit.gg** (a UDP tunnel the host runs — no port forwarding, no code changes).
  Recorded as the working transport answer; still gathering during normal play: latency feel,
  smoothing under real jitter, mid-session disconnect behavior.
- **Spine/game restructure (milestone 2 ✅).** Everything game-agnostic moved under
  `framework/` (autoloads, components, debug harness, menu, console, GameConfig); everything
  spell-game under `games/magick/` (spells, reactions, director, player, enemies, projectiles,
  HUD, the arena level, the spell catalog autoload). All scene/script/preload/autoload paths
  rewritten; full headless gate green (`SMOKE: PASS`). The import-direction rule is now visible
  in the tree. Remaining named follow-ups: the `enemy_*` signals on GameEvents and the mixed
  `main.gd` composition root — both forced properly by the next prototype.

---

## 2026-06-10 (the framework reframe)

*The framework is the project now — the spell game is its test fixture*

### 📐 Direction

- **Project frame inverted: framework-first.** The durable goal is a reusable **host-client
  co-op multiplayer framework for Godot** (2–8 players, friend groups, proximity voice chat
  planned); the spell game was a starter idea, not a passion project, and is now the **test
  fixture** — kept to exercise the spine, frozen as a game (no new Forms, pickups, or
  fun-tuning). `DESIGN.md` rewritten around the new vision: framework decisions (frameworks
  are extracted not designed; import-direction rule; prototypes live in-repo and graduate
  out) + a milestone roadmap led by **real-online verification**, then restructure →
  late-join → lobby → spawn points → **proximity voice** → 8-player validation. The spell
  game's design decisions are preserved in a frozen Fixture section (they explain the code).
- **CLAUDE.md follows:** "Build this game" → "Build the framework"; a new non-negotiable
  **import-direction rule** (spine never references game nouns, with today's known debts
  named: `spell_catalog` in autoloads/, `enemy_*` signals on GameEvents, the mixed `main.gd`,
  the fixture-leaning HUD); file map entries tagged FIXTURE; stale "roadmap item 7"
  references now point at framework milestone 1. Docs-only — no code changed.

---

## 2026-06-09 (remote-player movement smoothing)

*No more sea-sick jitter watching a teammate run*

### 🛡️ Stability & Netcode

- **Remote players glide instead of stuttering.** A teammate's position replicates in snapshots that
  Godot applies with no interpolation, so on your screen they teleported between packets — fine
  standing/aiming, sea-sick when they ran. Now, on remote copies only, the visible model is decoupled
  and **eased toward the synced position + facing each frame** (frame-rate independent, snaps on
  respawn/teleport). The body stays authoritative — collision and host hit-resolution use the true
  position; only the cosmetic visual lags (~0.3 m at run speed, tunable via `remote_smoothing_rate`).
  Enemies are unchanged for now (their slow, distant motion hides the same stutter — a deferred
  follow-up). (#55)
- **Why the simple fix.** Chose the community-standard "lerp the visual toward the synced value" over
  a hand-rolled snapshot-interpolation buffer (over-engineered for co-op PvE) and over adopting netfox
  (same one-tick result for *just* smoothing, but a structural migration). netfox / lag-compensation /
  NAT-relay stay a separate, deliberate "adopt a foundation" decision for later.

---

## 2026-06-07 (cast timing + FP/TP split)

*Instant in first-person, gesture-timed for everyone else*

### ✨ Features

- **Casting feels instant, and looks right to others.** First-person and third-person are now
  decoupled (the standard FP-viewmodel split). The moment you press cast you get **instant** feedback —
  muzzle flash + your straight tracer — so there's zero delay. Meanwhile the **networked bolt others
  see + the damage** fires at a designer-set **release point** mid-gesture (`oneshot_release_time_sec`,
  tuned by scrubbing the clip), so to teammates the bolt leaves the staff at the natural moment. (The
  caster never sees the networked bolt — it's hidden for them — so there's no double.)
- **The staff muzzle is now an editor-placed marker.** Instead of a blind offset, there's a draggable
  `Marker3D` (`StaffMuzzle/Tip`) bone-attached to the staff hand — drag it onto the orb in the viewport
  and the bolt launches from exactly there. (Code falls back to the old offset if the marker's absent.)

---

## 2026-06-07 (casting fixes)

*Fixing two regressions/gaps the two-window playtest caught*

### 🛡️ Stability & Netcode

- **Cast animation plays again.** The upper-body filter shipped last round silently broke the cast
  gesture: `filter_enabled` loaded from the `.tscn` but the per-bone filter entries didn't, leaving an
  empty filter that masked the cast off the whole body. The filter is now set in **code** (verifiable
  headlessly), so the cast plays on the torso/arms while the legs keep running.
- **Bolt leaves the actual staff (third person).** The networked bolt spawned from a camera-relative
  point (near the head), so to teammates it looked like it came from the face. It now spawns from the
  mage's **staff bone** (a `BoneAttachment3D` on the hand), so other players see it leave the staff.
  First-person aim is unchanged (still the dead-center local tracer).

---

## 2026-06-07 (casting polish)

*Two-window playtest follow-ups*

### ✨ Features

- **First-person shots go dead-center.** The bolt used to leave the side-mounted staff and angle in
  toward the crosshair (it only converged downrange). Now the caster sees a **straight cosmetic bolt
  from screen-center through the crosshair**, while the real (networked) bolt — hidden for the caster
  — still flies from the **staff** so teammates see it leave the staff. The standard FP/TP dual-visual
  split; the hidden networked bolt still does all the damage.
- **Cast while running without skating.** Casting used to freeze the legs (the full-body cast clip
  replaced locomotion), so you slid around mid-cast. The cast one-shot is now **bone-filtered to the
  upper body** — torso/arms/head/staff play the cast while the legs keep running/idling underneath.

---

## 2026-06-06 (casting feedback + console)

*Playtest-prep polish from user feedback*

### ⚙️ Under the Hood

- **Clients can open the dev console now.** It mounts on every peer and gates by role: the host keeps
  the full command set, a client gets `help`/`clear` (host-only commands print "host only"), with a
  `_HOST_ONLY` seam ready for future client-side commands. Each peer's console suspends only its own
  input while open (already per-peer).
### ✨ Features

- **Players cast with a gesture now.** The mage plays a `Spellcast_Shoot` one-shot over locomotion
  when a cast actually fires — same BlendTree+OneShot shape the skeleton already uses for its attack.
  Replicated owner→all (cosmetic), so teammates see you cast.
- **Spells come out of the staff, not your face.** A `Muzzle` Marker3D on the staff (under the camera)
  is now the projectile + muzzle-flash origin, instead of a point in front of the camera. The shot
  still **lands on the crosshair** — a camera raycast finds the real target (wall/enemy/floor) and the
  bolt aims from the muzzle to that point, so it converges dead-center at any range instead of drifting
  off the offset origin. Origin is read on the casting peer and passed to the host spawn.
- **Characters tilt to where they're looking (up/down).** The mage now pitches its upper body to the
  player's look-angle — so teammates can read where you're aiming and up/down casts look right (before,
  the model stood flat while the bolt flew up). Built as a `SkeletonModifier3D` on the `spine` bone
  (legs stay planted), driven by a new replicated `aim_pitch` (same owner-authors / mode-1 pattern as
  the facing yaw). Enemies can opt in later; the tilt itself is verified in the two-window run.

### 🛡️ Stability & Netcode

- **DoT no longer strobes the screen.** A fire burn deals ~10 damage ticks/sec, and each one fired a
  fresh first-person red flash — so a single DoT machine-gunned the screen. The self-damage pulse is
  now throttled (one calm pulse per ~0.4s window, tunable), so a fresh hit still reads instantly but a
  sustained burn doesn't flicker.

---

## 2026-06-06 (scope pass)

*Trimmed the slice toward the playtest, after two external reviews*

### ⚙️ Scope & Sequencing

- **Console `give [all]`** — a host dev command that rolls a random spell onto a player (reuses the
  spell catalog + the wand's equip-sync). The slice's stand-in for drop-based acquisition, enough to
  playtest the random keep/swap loop without building the full pickup system.
- **Cut the cascade A/B from the slice** — blend is the decided engine so it can't move it, and the
  comparison is a noisy signal; parked until a content question makes it pressing.
- **Pulled the real-online / latency test up next to the playtest** — it was gated under "beyond the
  slice (only if it proves fun)," but latency killing cast feel is *why* it might not be fun, so that
  gating was circular. Named client cast-latency the #1 slice risk; the first real test must be a
  real connection on two machines, not zero-latency two-window.
- **Legibility bar clarified** — it measures in-world legibility, so the playtest runs with no
  "killed by X" HUD (printing the answer contaminates the test); caster attribution is a deferred
  option, not a slice feature.
- **Trimmed the "reusable spine / sandbox" framing to one line** so it stops acting as a default
  tiebreaker for architecture work before a second game justifies it.

---

## 2026-06-06 (continued)

*Player controller migration + review fixes + docs (#40–#42)*

### ✨ Features

- **Player is now a `CharacterBody3D`** (was `RigidBody3D`). Crisper, more standard first-person feel,
  and the **airborne wall-stick is gone** — `move_and_slide` slides you along walls instead of pinning
  you. Movement is a clean velocity model (asymmetric-gravity jump + `move_toward` accel/decel). The
  emergent rigid-body shoving goes away by design; knockback/ragdoll become deliberate scripted
  effects later. (#42)

### 🛡️ Stability & Netcode

- **Enemy "run-in-place" fixed.** A blocked/stacked skeleton authored its locomotion speed from the
  *commanded* velocity (before `move_and_slide`), so it played the run cycle while standing still; now
  read from the resolved velocity. Plus a death-pose reset and an attack-RPC guard. (#41)
- **Smoke gate now exercises enemies.** Since the wave director boots paused, the headless gate never
  spawned an enemy — it now spawns one and asserts its AnimationTree is active, so enemy
  spawn/AI/animation regressions get caught pre-PR. (#41)

### ⚙️ Under the Hood

- **Docs refresh** — brought `CLAUDE.md` / `DESIGN.md` / `CHANGELOG` current through the animation
  subsystem, visual scenes, reactions, and the start-gate; recorded (now implemented) the
  CharacterBody3D decision. (#40)

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
