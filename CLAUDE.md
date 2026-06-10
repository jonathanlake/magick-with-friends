# CLAUDE.md — Magick With Friends

Architecture reference for AI-assisted development. Read this before touching any file.

**Game vision, design decisions, build roadmap, and status live in `DESIGN.md`.** DESIGN is
**decision-led** (what/why); this file is **structure-led** (how the code is organized + the
dev workflow): rules, file map, the non-obvious Godot gotchas. Expect some overlap — when a fact
is in both, the *decision* lives in `DESIGN.md` and the *implementation detail* lives here.
Two **reference-led** docs trace specific systems end-to-end with real function names:
`docs/NETWORKING.md` (transport, authority, replication, RPCs, lifecycles, edge cases) and
`docs/SPELLS.md` (the blend system, class-by-class). Reach for those to answer "what happens
when X?"; reach for this file for rules and gotchas.

In one line: a **reusable host-client co-op multiplayer framework** for Godot (the
"friendslop framework" — 2–8 players, friend groups) plus its **test fixture**: a 3D
first-person horde game whose combat is the BLEND spell system (Form × Element → one fused
cast). The fixture is **frozen as a game** — it exists to exercise the spine. Where this doc
describes a system the code doesn't implement yet, it's marked roadmap.

**Build the framework.** (Reframed 2026-06-10 — supersedes the old "Build this game" frame;
the reframe note atop `DESIGN.md` is canonical.) The product is the reusable co-op spine;
**Magick With Friends is the test fixture** — no new Forms, pickups, or fun-tuning; fixture
work only when it blocks a framework milestone. "Keeps the spine reusable" **is** now a
tiebreaker. The roadmap is framework milestones (`DESIGN.md`), led by real-online verification.

---

## Git Workflow

- **New branch per task.** Always create `claude/[short-description]` before making any
  changes. Never commit directly to main.
- **Always fetch main first.** Before creating any branch, run
  `git fetch origin main && git reset --hard origin/main` to guarantee the branch starts
  from the actual current state of main. Skipping this causes merge conflicts on every PR.
- **Open a PR when done.** Every task ends with a pull request against main.
- **One feature per PR.** Keep PRs narrowly scoped and independently reviewable/playable.
- **Validate before every code PR.** Run the headless check (see "Headless Validation"
  below); do not open the PR if it reports parse/scene errors.
- **End-of-task confirmation.** After pushing, always report: branch name, whether it's
  been pushed to remote, and a list of files changed.
- **Keep the reference docs true.** A PR that changes networking behavior updates
  `docs/NETWORKING.md` in the same PR; one that changes spell behavior updates
  `docs/SPELLS.md`. Code is truth — a doc/code mismatch is a doc bug.

---

## Rules (Non-Negotiable)

- **GDScript only.** No C#. Ever.
- **3D only.** No 2D. Jolt physics, `CharacterBody3D`/`RigidBody3D`/`StaticBody3D` nodes.
- **Jolt physics engine.** Set in `project.godot`. Do not switch to default Godot physics.
- **No C# toolchain.** No `.csproj`, no `dotnet`, no NuGet.
- **Do not modify UIDs** in `.tscn` or `.gd.uid` files manually (the editor generates them).
- **@export everything tunable.** Any value a non-coder might want to change must be `@export`.
- **Players and enemies are `CharacterBody3D`** (kinematic, `move_and_slide`-driven). `RigidBody3D`
  is fine for props. **Physics-chaos — ragdolls, knockback, slips — is the embraced tone**, but with
  kinematic bodies it's **deliberate scripted** effects (manual velocity / a ragdoll on death), not
  emergent rigid-body jank.
- **Component pattern.** Behavior goes in component nodes, not monolithic scripts.
- **Event bus pattern.** Cross-system communication goes through `GameEvents` signals.
  No direct node references across unrelated systems.
- **Swappable transport.** All network peer creation lives in `NetworkManager.host_game()`
  and `NetworkManager.join_game()` only. No other file may import or reference
  `ENetMultiplayerPeer` (or any future transport class) directly.
- **Import direction (spine → game, never the reverse).** Nothing under `framework/` may gain
  **new** references to game nouns (spells, waves, enemies); game code (`games/<name>/`)
  imports the spine. The directory split IS the rule made visible (milestone 2). Two known
  debts remain, named follow-ups — don't deepen them: `framework/autoloads/game_events.gd`
  still carries fixture `enemy_*` signals, and `main.gd`/`main.tscn` are the mixed composition
  root (split when the next prototype forces game/level selection).

---

## Architecture Overview

### NetworkManager — Swappable Transport Layer

`NetworkManager` (`framework/autoloads/network_manager.gd`) is the **only** file that knows which
transport is in use. The rest of the codebase calls `host_game() -> Error` /
`join_game(ip, port) -> Error` / `disconnect_game()` / `kick_peer(id)` (host-only) and listens
to its signals (`connection_succeeded`, `connection_failed`, `server_disconnected`,
`peer_connected(id)`, `peer_disconnected(id)`). A failed host create (port already bound)
returns the error — the caller must stay on the menu, never enter the game peerless. The
server caps transport connections at `max_players - 1` (the host holds the remaining slot).

**To swap ENet for Steam/relay:** replace the peer-creation lines inside `host_game()` and
`join_game()`. Nothing else changes — the `multiplayer.*` signal layer above the transport is
identical across backends. The file opens with a formal transport contract comment; read it
before adding any connection code. (Full API + signal tables: `docs/NETWORKING.md` §2.)

### Multiplayer Model

ENet host/client. One player is the server (host, peer ID `1`); others are clients. This is the
**implementation home for the authority model decided in `DESIGN.md`** — other sections defer
here for the *how*. (Traced lifecycles — join, damage→death→respawn, every disconnect path —
plus the full replication/RPC tables and edge-case matrix live in `docs/NETWORKING.md`.)

- **Input authority:** Each player is `multiplayer_authority` over their own `Player` node and
  `PlayerInputSynchronizerComponent`. Input is gathered locally only on the authority peer,
  then synced to all. (Today no remote system *consumes* the synced input — movement arrives as
  replicated position; the replication is kept deliberately as a seam — see the component note
  in the File Map.)
- **Physics / simulation authority:** Each player **simulates its own character** on its
  owning peer (movement runs there); position replicates **from the owning peer** to all via
  `MultiplayerSynchronizer`. **Health / damage / death are host-authoritative** — resolved on
  the host and pushed to all peers via a reliable RPC value-sync (never health-over-
  `MultiplayerSynchronizer`, which can desync).
- **Spawn authority:** Host's `MultiplayerSpawner` in `main.tscn` handles all spawning.
  Clients fire `peer_ready.rpc_id(1)` → host spawns their player via `spawn_function`.
- **RPCs:** `@rpc("any_peer", "call_remote", "reliable")` for client→host; `@rpc("authority",
  "call_local", "reliable")` for host→all broadcasts.

The **same host-authoritative model governs everything net-new** — enemies, the wave spawner,
projectiles/spell effects, world reactions, pickups, run state. Clients send intent (input,
interact/cast requests); the host owns the simulation and replicates outward. Cast *feel* on
clients is **local cosmetic feedback only** (muzzle flash) — never client-authoritative
damage. (Rationale for the per-player-vs-host split is in `DESIGN.md`.)

### Node Ownership Pattern

```
Main (Node) — no authority set, runs on all peers
└── Player_{peer_id} (first-person body) — authority = peer_id
    ├── PlayerInputSynchronizerComponent — authority = peer_id (gathers input locally, syncs out)
    └── MultiplayerSynchronizer — authority = peer_id (syncs position from owning peer outward)
```

The `Player` node is named by peer ID (`str(peer_id)`). This is how Godot's high-level
multiplayer finds and routes to the right node.

### Replication Modes

Godot 4 `MultiplayerSynchronizer` replication modes used here:

- **Mode 1** (`REPLICATION_MODE_ALWAYS`) — syncs every physics frame. Used for `global_position`
  and the **animation drivers**: player `aim_yaw` + `aim_pitch` + `anim_speed`, enemy `face_yaw` +
  `anim_speed` (the owning peer authors them; every peer animates/faces/tilts from the replicated
  value — see Animation).
- **Mode 2** (`REPLICATION_MODE_ON_CHANGE`) — syncs only when value changes. Used for the
  synced input fields in `PlayerInputSynchronizerComponent`.

**Remote-body visual smoothing.** `global_position` (mode 1) is applied with **no interpolation** —
Godot snaps it, so a remote body teleports between snapshots. On **remote (non-authority) player
copies** the visible `Visual` is therefore **decoupled** (`top_level = true`, set in code) and its
position + facing are **eased toward** the replicated body each frame (`remote_smoothing_rate`,
frame-rate-independent `1 - exp(-rate*delta)`, with a snap-guard for respawn/teleport). The **body
stays snapped** (collision + host hit-resolution use the true position); only the cosmetic Visual
lags; the **owner's Visual is untouched** (its staff-muzzle world read must stay exact). This is the
community-standard "lerp the visual toward the synced value" fix — a deeper snapshot buffer / netfox /
velocity sync (a Beyond-the-slice item in `DESIGN.md`) was considered and deferred.

### SceneReplicationConfig NodePath Syntax

Property paths use the format `"<node_path>:<property>"`:

- `".:global_position"` — `.` is the root node (resolved via the synchronizer's `root_path`).
  Use this to sync a property on the root itself.
- `".:movement_vector"` — same pattern in `PlayerInputSynchronizerComponent` (`root_path = "."`).
- `"Player:global_position"` — **wrong**. It looks for a *child node named "Player"*; after
  spawning, the player node is renamed to the peer ID, so the path never resolves.

**Rule:** always use `".:property"` for properties on the root node. Never use the
scene-editor node name in a replication path — it breaks after spawning renames the node.

### MultiplayerSynchronizer Authority Timing

Call `set_multiplayer_authority()` in `_enter_tree()`, **not** `_ready()`. The child
`MultiplayerSynchronizer`s need to register with the correct authority on tree entry; set in
`_ready()`, they've already registered under the wrong peer and Godot logs "has no network ID".

```gdscript
func _enter_tree() -> void:
    set_multiplayer_authority(input_multiplayer_authority)  # set before children register
```

`set_multiplayer_authority(id)` defaults to `recursive = true`, so child synchronizers inherit it.

### GameConfig / GameManager

`GameConfig` (`framework/resources/game_config.gd`) is a `Resource` holding session-level settings
(`max_players`, `respawn_time`). It is not an autoload — plain data; expect run-level fields.

`GameManager` (`framework/autoloads/game_manager.gd`) is an autoload `Node` owning a `GameConfig`
(`GameManager.config`) + the local `player_name`. The host sets config before starting the
server; all systems read from `GameManager.config`. Natural home for future run/wave state.

### First-Person Camera (current)

The player ships a **first-person** rig (camera on the player body). **Casting aims forward** from the
camera. **FP and TP are decoupled** (the standard FP-viewmodel-vs-world-model split): pressing cast
commits it (`WandComponent.begin_cast()` takes the cooldown), plays the `Spellcast_Shoot` gesture on
all peers, and **immediately** fires the caster's first-person feedback — the muzzle flash + a local
straight `SpellTracer` (`WandComponent.fire_fp_cast()`) — so the shooter feels zero delay. The
**networked** bolt (what others see + the damage) fires later, at the gesture's RELEASE frame:
`oneshot_release_time_sec` after the trigger the Visual emits `oneshot_released` and the owner calls
`WandComponent.fire_cast()` → host spawn. (Release timing is a code timer, not an in-clip Call Method
Track — those are unreliable on imported-glb clips played through an AnimationTree.) The networked bolt
**spawns from the model's actual staff** — a `BoneAttachment3D` on `handslot.r` exposed via
`LocomotionAnimator.staff_muzzle_position()`, **preferably an editor-placed `Marker3D`** (drag it onto
the orb; `staff_muzzle_marker_path`), falling back to the code-built attachment + `staff_muzzle_offset`.
It tracks even though the caster's own Visual is hidden (hiding a node doesn't stop the AnimationTree
posing the skeleton). The **FP/TP dual-visual** split: the networked bolt's mesh is **hidden for the
caster** (`projectile.gd`) so they only see their local tracer; the hidden networked bolt still does all
the damage. The tracer is cosmetic-only, never networked. No ground-cursor in the slice.
The climbing/parkour camera path has been **removed**.

### Animation (LocomotionAnimator + AnimationTree)

Players and enemies use KayKit models (gitignored `/assets/`) animated through one reusable
`framework/components/locomotion_animator.gd` on each **visual scene root** (`player_visual.tscn` /
`enemy_visual.tscn`):

- **Tree shape.** The animator reads an `AnimationTree`. Both player and enemy use the SAME shape now:
  a **BlendTree** = a BlendSpace1D "Loco" (Idle↔Run by speed) feeding an **AnimationNodeOneShot** whose
  shot is a one-off action clip — enemy = the melee attack (`1H_Melee_Attack_Chop`), player = the cast
  gesture (`Spellcast_Shoot`). `blend_param` / `oneshot_request_param` exports point at the right nested
  params (`parameters/Loco/blend_position`, `parameters/OneShot/request`).
- **Replicate the DRIVER, never the animation.** The idiomatic Godot multiplayer rule (and the cause
  of a real jitter bug we fixed): **don't differentiate a replicated `global_position`** to get speed
  — a remote body's position arrives in held network snapshots, so differentiating it sawtooths the
  blend (run↔idle, worst at a weapon tip on a long lever). Instead the **owning peer authors its real
  speed** and the animator blends from that. The owner writes `anim_speed` (planar velocity) — and a
  facing yaw (`aim_yaw` player / `face_yaw` enemy) — these **replicate (mode 1)**, and every peer
  `feed_speed()`s the animator + rotates the visual from the steady value. Sample on the **physics
  clock** (not `_process`), the same clock the body moves on.
- **One-shots** fan out cosmetically via `authority, call_local` RPC → every peer `fire_oneshot()`s.
  Enemy attack: the host calls `play_attack_anim.rpc()` (host owns the enemy). Player cast: the OWNING
  peer calls `play_cast_anim.rpc()` when a cast actually fires (the player node's authority IS its
  owner, so the same RPC shape works) — the local FP caster's Visual is hidden, so it's remotes that
  see the gesture.
- **Upper-body cast** (player): the cast OneShot is **bone-filtered to the upper body** so the legs
  keep running underneath (no skating). The filter is set in **code** (`LocomotionAnimator._ready` →
  `set_filter_path` for each track in the `oneshot_filter_paths` export, e.g. `Rig/Skeleton3D:spine`),
  NOT in the `.tscn` — the `AnimationNodeOneShot` filter sub-properties **don't reliably deserialize
  from a hand-authored scene** (`filter_enabled` loads but the entries don't, leaving an empty filter
  that masks the cast off the *whole* body — that regression is why the cast briefly stopped playing).
  Checked tracks = the OneShot drives them; unchecked legs/hips stay on Loco. Verify headless with
  `is_path_filtered`.
- **Look-pitch** (player): the upper body tilts up/down to where the player aims. The owner authors
  `aim_pitch` (= camera pitch), it **replicates (mode 1)** like `aim_yaw`, and every peer
  `feed_pitch()`s the animator → a `SpinePitchModifier` (a `SkeletonModifier3D`, built/attached in code
  to the model's `Skeleton3D`) rotates the `spine` bone *after* the AnimationTree, so the torso/head/
  staff tilt while the legs (parented under `hips`, a sibling) stay planted. Opt-in per visual via the
  `spine_pitch_bone` export (empty on the enemy = no-op, same as the OneShot pattern). NOTE: a
  `SkeletonModifier3D`'s on-screen effect is **not observable from the headless smoke gate** (it lands
  in the post-mixer skeleton pass the harness can't sample) — verify it in the two-window run; axis/
  sign/clamp are tunable via `max_pitch_deg` / `invert_pitch`.
- **Looping** on Idle/Run is set in the glb **import dock** (author action, not code); the attack clip
  stays **non-looping** so the OneShot ends and returns to locomotion.

### Spell System — BLEND (fixture combat core — frozen as a game)

A spell fuses two swappable slots **on cast** → **one fused effect** (NOT a sequence/program;
see `DESIGN.md` for the blend rationale and the legibility north star). The class-by-class
reference — every property, the cast pipeline, hit/reaction resolution, how to add content —
is `docs/SPELLS.md`:

- **Form** — delivery shape, where the mechanical distinctness lives (the ~7-Form ceiling + the
  candidate list is a *decision* — see `DESIGN.md`). *Slice:* Projectile, AoE burst.
- **Element** — thin damage + reaction layer, via a small reaction table. *Slice:* Fire, Lightning.
- **Modifier** — optional; Split / Bounce / Homing **omitted in the slice** (they erode the
  per-cast legibility blend exists to protect).

Implemented as `@export`-driven Resources under `games/magick/spells/` (`Spell` / `SpellForm` /
`SpellElement` / `BlendSpell`), cast by a `WandComponent` on the player holding the
`(Form, Element)` pair and enforcing `cast_delay_sec`. `Spell` exposes a `cast_on_host()` seam so
an authored `CascadeSpell` (a deferred cascade experiment — cut from the slice, see `DESIGN.md`)
could slot in without reworking the wand.

**Host-authoritative** (see Multiplayer Model): casts originate on the authority peer; the host
spawns + resolves them (damage incl. friendly fire, reactions) and replicates out. **Reactions**
are two cheap layers (NOT a pixel sim): entity status (lightning chains to nearby units incl.
allies; fire burns + spreads — built) and `Area3D` world volumes (oil, water — never built,
**frozen** with the fixture). **Acquisition** (keep-or-swap pickups) was **cut by the framework
reframe** — the dev-console `give [all]` stand-in remains. Frozen design rationale lives in
`DESIGN.md` → the Fixture section.

---

## File Map

```
framework/                    ══ THE SPINE (game-agnostic; the future addon/repo-split unit) ══
  autoloads/
    game_events.gd            — Global signal bus. Add signals here, not in random scripts.
                                Has `enemy_died`, `enemy_count_changed(count)` + `alive_enemy_count`
                                (register_enemy/unregister_enemy), and `local_player_damaged` (FP
                                hit cue, via `emit_local_player_damaged()`). Fuller vocabulary is
                                DESIGN.md backlog. NOTE: the `enemy_*` signals are fixture nouns on
                                a spine autoload — an import-direction debt (named follow-up).
    game_manager.gd           — Autoload Node. Owns GameConfig + local player_name.
    network_manager.gd        — Transport abstraction. ONLY file that touches ENet/Steam/relay.
  components/
    health_component.gd/.tscn — max_health (export, default 100), current_health, damage(int),
                                died + damaged signals. Reused by players and enemies.
    hit_flash_component.gd/.tscn — Reusable damage flash. @export target_root_path / flash_color /
                                flash_duration_sec / health_component_path / skip_on_lethal.
                                Auto-wires to a HealthComponent's `damaged`; host fans the cosmetic
                                flash to all peers via an `any_peer` RPC (deliberate — see RPC
                                Pattern exception: player nodes are client-owned).
    stamina_component.gd/.tscn — Two-pool resource + `depleted` signal. Unused — reserved for a
                                future mana/oxygen-style pool.
    player_input_synchronizer_component.gd/.tscn
                              — Extends MultiplayerSynchronizer. Gathers input on the authority
                                peer, replicates it (mode 2). Syncs `movement_vector` (WASD) +
                                `is_jump_pressed`. NOTE: the synced fields are consumed ONLY by
                                the owning peer today — remote copies simulate nothing from input
                                (movement replicates as position). The mode-2 replication is kept
                                on purpose as the seam for host-side input validation or
                                client-side prediction if real-latency playtests demand them
                                (DESIGN.md authority decision); don't "optimize" it away.
    locomotion_animator.gd    — Reusable script on a visual scene root. Drives a locomotion
                                BlendSpace1D (idle↔run) from a fed speed, fires a OneShot
                                (`fire_oneshot`) for a layered action, code-sets the OneShot's
                                upper-body filter (`oneshot_filter_paths`), and (opt-in) attaches a
                                SpinePitchModifier (`spine_pitch_bone`, fed by `feed_pitch`) + a
                                staff BoneAttachment3D (read via `staff_muzzle_position()`).
                                See Animation above. BUILT.
    spine_pitch_modifier.gd   — SkeletonModifier3D: tilts one bone up/down by a fed look-pitch,
                                after the AnimationTree. Attached in code by locomotion_animator.
    remote_visual_smoother.gd — Eases a remote copy's decoupled Visual toward the snapped body
                                (rate clamp, snap guard, respawn park). See Replication Modes.
  debug/
    debug.gd                  — Dev-only helper. DEBUG autoload, DISABLED by default. Two-window
                                autostart (`-- host/join debug_autostart`) + `-- smoke` driver.
  resources/
    game_config.gd            — Resource. max_players, respawn_time. Not an autoload.
  ui/
    main_menu/                — Host/join flow. Validates name, parses ip[:port] for both host
                                and join (default 127.0.0.1:3000), surfaces failures.
    console/                  — dev_console.gd: dev console (backtick). Mounted on EVERY peer in
                                main.gd, gated by role: HOST gets the full set (help / start /
                                give [all] / players / wave / enemies [off|on|clear] / clear); a
                                CLIENT gets help / clear, with a seam (`_HOST_ONLY`) for future
                                client-side commands. BUILT.

games/magick/                 ══ THE FIXTURE (frozen as a game; exercises the spine) ══
  spell_catalog.gd            — Autoload (game-owned). Index-stable Form/Element arrays +
                                `make_blend(f,e)` so every peer builds the SAME spell from
                                replicated indices. BUILT.
  spells/                     — Spell/SpellForm/SpellElement/BlendSpell resources +
                                WandComponent. BUILT.
  reactions/                  — reactions.gd: host-central resolver (Node under Main). Direct
                                damage + entity reactions (lightning chain incl. allies, fire
                                burn/DoT); cosmetic broadcasts. BUILT (Area3D world volumes
                                frozen with the fixture).
  director/                   — wave_director.gd: host-side escalating ring spawner (timer +
                                waves, alive cap). Boots PAUSED (`auto_start = false`) — the host
                                begins the round via the console `start`. BUILT.
  player/
    player.gd                 — First-person CharacterBody3D controller: run / jump / look /
                                cast / death-state. Authors replicated `aim_yaw` + `aim_pitch` +
                                `anim_speed`; on REMOTE copies decouples the Visual and smooths
                                it (RemoteVisualSmoother). Fixture-coupled via the wand/cast —
                                a generic-FP-controller module extraction is future work.
    player.tscn               — FP body, InputSync, MultiplayerSynchronizer, HealthComponent,
                                HitFlashComponent, Visual (player_visual.tscn, NameLabel under
                                it), capsule collider, camera. (WandComponent added in code.)
    player_visual.tscn        — KayKit Mage (.glb) + AnimationTree + LocomotionAnimator. BUILT.
  enemies/                    — enemy_base.gd/.tscn (host AI: steer/melee; replicated anim
                                drivers; attack-swing RPC) + enemy_visual.tscn (KayKit Skeleton).
  projectiles/                — projectile.gd/.tscn: host-spawned + host-resolved spell bolt
                                (mesh hidden for the caster — FP dual-visual). spell_tracer.gd:
                                the caster-only local cosmetic bolt. BUILT.
  hud/                        — DEV debug HUD (CanvasLayer): spell + HP + counts + FPS,
                                crosshair, death fade, host-left + self-damage overlays.
  levels/test_level.tscn      — Walled horde arena (CSG floor + 4 perimeter walls).

docs/
  NETWORKING.md               — Reference-led: the multiplayer spine traced end-to-end —
                                transport seam, authority tables, every replicated property,
                                the full RPC catalog, lifecycles, the edge-case matrix, and the
                                reusing-the-spine checklist.
  SPELLS.md                   — Reference-led: the BLEND system class-by-class — every @export,
                                the cast pipeline, hit + reaction resolution, how to add content.
  IDEAS.md                    — The game-idea backlog (capture > debate). Three lines per idea
                                (the clip / the loop / framework demands) + SEED→GRAY-BOXED→
                                PROMOTED/SHELVED statuses. Intake for DESIGN.md's cadence guard.

tools/
  smoke-test.sh               — Headless gameplay smoke test (see Headless Validation).

main.gd                       — MIXED composition root (spine spawner/peer_ready/damage skeleton
                                + fixture spawn_functions/forwarders). Splitting it per-game is a
                                named milestone-2 follow-up, forced by the next prototype.
main.tscn                     — World root: player/projectile/enemy MultiplayerSpawners,
                                Projectiles/Enemies containers, WaveDirector, + a level.
project.godot                 — Autoloads, input map (move_*, cast, jump), Jolt, 1920×1080,
                                D3D12. config_name = "Magick With Friends".
```

(For built-vs-planned status, the `BUILT` tags above + the `DESIGN.md` framework roadmap are
the source of truth.)

---

## Spine Status — What's Real Today

The reusable spine that is built and working (the framework's current inventory; the
spine-vs-fixture split is mapped in `docs/NETWORKING.md` §10):

- [x] Project scaffolding — Jolt, Forward Plus, 1920×1080, D3D12 on Windows
- [x] **`NetworkManager` autoload** — swappable transport layer; ENet today, Steam/relay ready
- [x] **Multiplayer connection flow** — host spawns self; clients send `peer_ready` RPC;
      max_players gate; despawn on disconnect; `MultiplayerSpawner` `spawn_function`
- [x] `PlayerInputSynchronizerComponent` (mode 2 input) + player `MultiplayerSynchronizer`
      (`global_position`, mode 1, spawn=true)
- [x] `HealthComponent` / `GameConfig` / `GameManager` / `GameEvents` autoloads + components
- [x] **IP input field** + name validation in the main menu (falls back to `127.0.0.1:3000`)
- [x] Floating name labels over players; KayKit Mage/Skeleton models with idle/run + attack animation
      (placeholder capsules retired)
- [x] **DEBUG autoload** — disabled-by-default two-window autostart (see below)
- [x] Two-player local multiplayer verified — host + client see each other move (first-person)
- [x] **Blend casting + friendly fire + death/respawn** — built and validated two-window

> **Online status:** only **same-machine two-window** is verified on this codebase. Per-peer
> authority *does* propagate correctly (repro in Known Issues); the open gap is **cross-machine
> transport** (NAT / relay / latency), not an authority fix. Full story + the test plan:
> **framework milestone 1** (`DESIGN.md` roadmap — real-online verification, canonical).

---

## DEBUG Autoload — Dev Workflow

`framework/debug/debug.gd` is registered as the `DEBUG` autoload in `project.godot` **without** the `*`
prefix, so it is **disabled by default**. It never runs in normal play or exported builds.

### Enabling for local two-window testing

1. **Enable the autoload** — Project Settings → Autoload → check `DEBUG` (or add `*` before
   `res://framework/debug/debug.gd` in `project.godot`).
2. **Configure Run Instances** — Debug → Customize Run Instances, two instances:

   | Instance | Arguments |
   |----------|-----------|
   | 1 (Host) | `-- host debug_autostart` |
   | 2 (Client) | `-- join debug_autostart` |

   The `--` separator is required — everything after it is read via `OS.get_cmdline_user_args()`.
   Role keywords accept aliases: `host`/`server` and `join`/`client` are interchangeable.
3. **Hit Play (F5).** Both windows launch. Host titles itself `HOST`, client `CLIENT`. The host
   opens on the leftmost monitor, the client on the primary monitor (single-screen = side-by-side).

### Disabling before shipping / returning to normal play

| Step | Enabled | Disabled |
|------|---------|----------|
| `project.godot` DEBUG line | `DEBUG="*res://framework/debug/debug.gd"` | `DEBUG="res://framework/debug/debug.gd"` |
| Run Instances Launch Arguments | `-- host/join debug_autostart` | **cleared** |

**Important:** Godot passes Launch Arguments even when "Override Main Run Args" is unchecked.
**Clear the Launch Arguments**, not just the autoload. Both steps are required.

**Rule:** Never commit `project.godot` with `DEBUG="*res://framework/debug/debug.gd"`. The `*` is dev-local only.

---

## Headless Validation (run before every code PR)

Godot 4.6 lives at
`C:\Users\Jon\Documents\Game Development\Engines\Godot 4.6\Godot_v4.6-stable_win64.exe`
— **local-specific** (machine/version-locked; override via `GODOT=…`, update on a version bump).

Before opening **any code PR**, validate headlessly and **do not open the PR if it reports
parse/scene errors**. `.godot/` is gitignored, so runs don't dirty the tree. **Three** checks —
no single one is complete (verified empirically):

1. **Parse-check each changed `.gd`** — catches syntax errors in **any** script, incl. brand-new
   files (which check 2 misses):
   ```
   "<godot>" --headless --path "<project>" --check-only --script "res://path/to/changed.gd"
   ```
   **Fail only on `Parse Error` lines.** `--check-only` doesn't load autoloads, so it *falsely*
   reports `Identifier not found: GameManager / NetworkManager / …` for any script using an
   autoload — **ignore those**.
2. **Import-check the project** — catches broken `.tscn`/resource refs and errors in **modified
   existing** scripts (it reloads changed files with autoloads). Does **not** reliably parse
   brand-new files in one run (that's check 1).
   ```
   "<godot>" --headless --editor --quit --path "<project>"
   ```
   **Fail on `SCRIPT ERROR` / `Parse Error` / `Failed to load`.**
3. **Gameplay boot smoke test** — confirms the project not only *loads* but *runs*: boots a
   headless **host** into the game (`Main`, host player spawned) and fails on any runtime error.
   Catches `_ready` / spawn / boot errors the load-checks miss, plus host-driven systems that
   run without input (e.g. the enemy/wave director).
   ```
   bash tools/smoke-test.sh
   ```
   Prints `SMOKE: PASS` / `FAIL` (exit 0/1; run it from **Git Bash**, bundled with Git for Windows).
   **Host-driven only** — it does not exercise input (casting/movement); that stays with the
   two-window playtest.

Together these catch the "won't parse / won't load / won't boot" bugs a no-Godot session would
ship blind. They are the cheap gate **before** the two-window playtest — not a replacement.

---

## Conventions

### Naming
- Scripts: `snake_case.gd` · Classes: `PascalCase` · Signals: `snake_case` past tense
  (`spell_cast`, `wave_started`) · Exported vars: `snake_case` with units (`cast_delay_sec`) ·
  Node names: `PascalCase`.

### Script Structure (within a .gd file)
```
class_name / extends → signals → @export vars → @onready vars → private vars →
_ready → _input → _process/_physics_process → public methods → private methods →
RPC methods (grouped at bottom, prefixed with intent)
```

### Component Pattern
A "component" is a `Node` (or `MultiplayerSynchronizer`) scene encapsulating one
responsibility. It does not reach up to its parent — it exposes signals/methods, and the
parent wires them in `_ready`.

### RPC Pattern
- Client → Host: `@rpc("any_peer", "call_remote", "reliable")` — host checks
  `multiplayer.get_remote_sender_id()`.
- Host → All: `@rpc("authority", "call_local", "reliable")` on a node the host owns.
- **Exception — host→all on a *client-owned* node uses `any_peer`.** `HitFlashComponent` lives on
  both host-owned enemy nodes *and* client-owned player nodes. When the host fans a flash to a
  **player** node it is **not** that node's authority, so an `"authority"` RPC would be rejected —
  it uses `@rpc("any_peer", "call_local", "reliable")`, guarded by `multiplayer.is_server()` on the
  trigger so only the host originates it. This is the one sanctioned deviation from the rule above;
  don't "fix" it back to `authority`.
- Player input is **never** sent via RPC — use `MultiplayerSynchronizer`.

### Scene Instancing
Use `preload("uid://...")` for scenes/scripts referenced in code. Never use string paths like
`"res://entities/player/player.tscn"` — UIDs survive file moves. (New hand-authored scenes may
reference by path until the editor assigns a uid on save.)

### Assets (KayKit models)
Character models (KayKit Mage / Skeleton, `.glb`) live in **gitignored `/assets/`** (local + cloud
backup — private solo repo). The committed visual scenes (`player_visual.tscn` / `enemy_visual.tscn`)
**instance** the `.glb`, so a fresh clone needs `assets/` copied in before those scenes load. The
headless gate assumes the assets are present locally.

### Physics (Jolt)
- **Players and enemies** are `CharacterBody3D` — set `velocity` then `move_and_slide()`; gravity via
  `get_gravity()`; `is_on_floor()` for grounded. Knockback = add to `velocity`. The player uses an
  asymmetric-gravity jump (rise/fall multipliers) + `move_toward` accel/decel; `move_and_slide` slides
  along walls (no airborne wall-stick).
- **Physics-chaos is a feature** of the friend-slop tone, but with kinematic bodies it's **scripted**
  (manual knockback velocity, a ragdoll swap on death). `RigidBody3D` is fine for purely-cosmetic props.
- Jolt is the engine (`project.godot`); test with Jolt enabled — its collision response differs.

### Camera Rig Pattern (First-Person)
See **First-Person Camera (current)** under Architecture Overview — camera on the body, casting
aims forward, no ground-cursor, client cast-feel is local cosmetic muzzle flash.

### Engine Behavior — Check Current Docs First
For engine/library/API behavior, check the **version-current Godot docs** (or community consensus)
**before** inventing a workaround. Godot's behavior shifts across minor versions, so stale intuition
is a real trap. **Treat a failed "this should be trivial" fix as the trigger to research — not to
add more complexity.** (Concrete example: the dev-console input "losing focus" after Enter wasn't a
focus bug at all — Godot 4.4 added `LineEdit.keep_editing_on_text_submit` defaulting to `false`;
two hand-rolled `grab_focus` workarounds failed before a doc check found the one-property fix.)

---

## Known Issues / Watch Out For

- **Player controller is `CharacterBody3D` (first-person).** Switched from RigidBody3D — crisper feel,
  and the airborne wall-stick is gone (move_and_slide slides along walls). Movement is velocity-model
  in `player.gd._physics_process` (gravity + jump on Y, `move_toward` accel/decel on the horizontal).
  Emergent rigid-body shoving is gone by design — knockback/ragdoll are now scripted (a follow-up).
- **Remote bodies snap; their *Visual* is what's smoothed.** A remote player's `global_position`
  replicates with no interpolation (Godot snaps mode-1 values), so the **body** teleports between
  packets *by design* — collision and host hit-resolution must use that true position. The visible
  stutter is hidden by easing the decoupled `Visual` toward it (see Replication Modes). **Don't "fix"
  the body snap by lerping the body** — that would desync collision/hits. Smooth the Visual, not the
  body. (Players done; remote enemies are a deferred follow-up.)
- **Cast feel is host-asymmetric.** The host feels instant casts; clients eat a round-trip. The
  local cosmetic muzzle flash masks it; read playtests knowing host feel ≠ client feel (rotate hosts).
- **Damage-value timing is host-asymmetric (distinct from cast feel above — that's latency, this is
  value timing).** `apply_player_damage` on the host pre-applies `hc.damage()` *before* it sends
  `_sync_health.rpc(...)`, so by the time the synced value lands the host's `current_health` is
  already the new (lower) value while clients still hold the old one. **Never gate a local cue on
  `value < current_health`** — it's false on the host and the cue silently no-ops there (exactly the
  bug behind "self-damage flash worked on clients but not the host"). Emit on the fact that a damage
  sync arrived, not on a before/after compare.
- **Typed-node `@export` resolves to `null` from a hand-authored `.tscn`.** A `@export var x:
  MeshInstance3D` (or any node type) only gets wired when set via the editor's node-picker; a
  NodePath typed into the `.tscn` by hand stays unresolved and the var reads `null` at runtime — no
  error, just a silently dead reference. Use `@export var x_path: NodePath` + `get_node_or_null(x_path)`
  in `_ready()` instead (how `HitFlashComponent` wires its mesh/health). The headless gate can't catch
  this — verify node wiring with a targeted probe.
- **Spawn height vs capsule:** keep spawn markers at `y≈1.0`+ so the capsule doesn't clip the floor.
- **Collision layers (named + explicit).** Four named layers in `project.godot`, mapping *slot →
  bit value*: `world` = slot 1 (bit 1), `players` = slot 2 (bit 2), `enemies` = slot 3 (bit 4),
  `projectiles` = slot 4 (bit 8). **Every `collision_layer`/`collision_mask` number below is a raw
  bit int** (what's stored in the `.tscn`, = `2^(slot-1)`), *not* a slot number — so `enemies` is
  `collision_layer = 4`, not 3. Assignments:
  - **world** (CSG floor + walls): `collision_layer = 1`, `collision_mask = 0` (static; bodies collide
    *into* it via their masks).
  - **player** (`player.tscn` CharacterBody3D): `collision_layer = 2`, `collision_mask = 7`
    (world+players+enemies — players + enemies block each other; grounded via `is_on_floor()`, no
    separate GroundCheck ray).
  - **enemy** (`enemy_base.tscn` CharacterBody3D): `collision_layer = 4`, `collision_mask = 7`
    (world+players+enemies — enemies collide with the arena, players, and each other so they don't stack).
  - **projectile** (`projectile.tscn` Area3D): `collision_layer = 8`, `collision_mask = 6`
    (players+enemies — friendly fire ON, hits both, **ignores world**). It despawns on
    Player/HealthComponent hits + lifetime, so walls don't stop a single-target bolt. **Bursts
    flip their mask to 7 at runtime** (`projectile.gd:setup`) so they detonate on floors/walls.
- **`input_multiplayer_authority` propagation (verified OK — not a bug).** Earlier notes calling
  this "host-only / broken cross-machine" were a misdiagnosis; it propagates correctly. **Repro:**
  enable the DEBUG autoload + run two-window — the `[AUTH]` line in `player.gd` prints each copy's
  authority from every peer's view (a client sees the host's player as `authority=1 is_mine=false`,
  its own as `is_mine=true`). *Why it works* and the still-untested cross-machine transport piece:
  framework milestone 1 (`DESIGN.md` roadmap — real-online verification, canonical — don't
  restate it here).
- `main_menu.gd` defaults to `127.0.0.1` and port `3000` (keep the port an `int` — ENet requires it).
- `multiplayer.connected_to_server` is only wired for the client path; the host transitions
  immediately — correct, don't add host-side handling.
- `class_name Player` must stay — `main.gd`'s `spawn_function` casts to `Player`.
