# CLAUDE.md — Magick With Friends

Architecture reference for AI-assisted development. Read this before touching any file.

**Game vision, design decisions, and the build roadmap live in `DESIGN.md`** — read that for
*what* we're building and *why*. This file is *how the code is structured and how to work on it*.

In one line: a **3D online co-op, first-person, horde** game; combat is the **BLEND spell
system** (Form × Element → one fused cast). It began as a generic multiplayer "friend slop"
framework; the networking spine carries over, movement/camera/combat are being (re)built.
Where this doc describes a system the code doesn't implement yet, it's marked roadmap.

---

## Git Workflow (Non-Negotiable)

- **New branch per task.** Always create `claude/[short-description]` before making any
  changes. Never commit directly to main.
- **Always fetch main first.** Before creating any branch, run
  `git fetch origin main && git reset --hard origin/main` to guarantee the branch starts
  from the actual current state of main. Skipping this causes merge conflicts on every PR.
- **Open a PR when done.** Every task ends with a pull request against main.
- **One feature per PR.** Keep PRs narrowly scoped and independently reviewable/playable.
- **Validate before every code PR.** Run the headless check (see "Headless Validation"
  below) and do not open the PR if it reports parse/scene errors.
- **End-of-task confirmation.** After pushing, always report: branch name, whether it's
  been pushed to remote, and a list of files changed.

---

## Rules (Non-Negotiable)

- **GDScript only.** No C#. Ever.
- **3D only.** No 2D. Jolt physics, `CharacterBody3D`/`RigidBody3D`/`StaticBody3D` nodes.
- **Jolt physics engine.** Set in `project.godot`. Do not switch to default Godot physics.
- **No C# toolchain.** No `.csproj`, no `dotnet`, no NuGet.
- **Do not modify UIDs** in `.tscn` or `.gd.uid` files manually (the editor generates them).
- **@export everything tunable.** Any value a non-coder might want to change must be `@export`.
- **Enemies are `CharacterBody3D`** (kinematic, `move_and_slide`-driven). The **player** is
  currently a first-person `RigidBody3D` (legacy); its controller model is an **open
  decision** (see `DESIGN.md`). **Physics-chaos — ragdolls, knockback, slips — is a *feature*
  of the friend-slop tone**, so `RigidBody3D` for the player is no longer ruled out.
- **Component pattern.** Behavior goes in component nodes, not monolithic scripts.
- **Event bus pattern.** Cross-system communication goes through `GameEvents` signals.
  No direct node references across unrelated systems.
- **Swappable transport.** All network peer creation lives in `NetworkManager.host_game()`
  and `NetworkManager.join_game()` only. No other file may import or reference
  `ENetMultiplayerPeer` (or any future transport class) directly.

---

## Architecture Overview

### NetworkManager — Swappable Transport Layer

`NetworkManager` (`autoloads/network_manager.gd`) is the **only** file that knows which
transport is in use. The rest of the codebase calls:

```gdscript
NetworkManager.host_game()          # start a server
NetworkManager.join_game(ip)        # connect as client
NetworkManager.disconnect_game()    # close the connection
```

And listens to its signals:

```gdscript
NetworkManager.connection_succeeded  # client: connected
NetworkManager.connection_failed     # client: failed to connect
NetworkManager.server_disconnected   # client: server went away
NetworkManager.peer_connected(id)    # any peer joined
NetworkManager.peer_disconnected(id) # any peer left
```

**To swap ENet for Steam/relay:** replace the two lines inside `host_game()` and
`join_game()` that create the peer. Nothing else changes. The `multiplayer.*` signal layer
above the transport is identical across all backends. The file opens with a formal transport
contract comment; read it before adding any connection code.

### Multiplayer Model

ENet host/client. One player is the server (host, peer ID `1`). Others are clients.

- **Input authority:** Each player is `multiplayer_authority` over their own `Player`
  node and `PlayerInputSynchronizerComponent`. Input is gathered locally only on the
  authority peer, then synced to all.
- **Physics / simulation authority:** Each player **simulates its own character** on its
  owning peer (movement runs there); position is replicated **from the owning peer** to all
  via `MultiplayerSynchronizer`. **Health/damage/death are host-authoritative** — resolved
  on the host and pushed to all peers via a reliable RPC value-sync (never health-over-
  `MultiplayerSynchronizer`, which can desync). See "Authority model" in `DESIGN.md`.
- **Spawn authority:** Host's `MultiplayerSpawner` in `main.tscn` handles all spawning.
  Clients fire `peer_ready.rpc_id(1)` → host spawns their player via `spawn_function`.
- **RPCs:** Use `@rpc("any_peer", "call_remote", "reliable")` for client→host calls. Use
  `@rpc("authority", "call_local", "reliable")` for host→all broadcasts.

**This same host-authoritative model governs everything net-new** — enemies, the wave
spawner, projectiles/spell effects, world reactions, item/spell pickups, and run state all
run on the host and replicate outward. Clients send intent (input, interact/cast requests)
via the authority/RPC patterns above; the host owns the simulation. Cast *feel* on clients
is provided by **local cosmetic feedback only** (muzzle flash) — never client-authoritative
damage or reactions.

### Node Ownership Pattern

```
Main (Node) — no authority set, runs on all peers
└── Player_{peer_id} (first-person body) — authority = peer_id
    ├── PlayerInputSynchronizerComponent — authority = peer_id (gathers input locally, syncs out)
    └── MultiplayerSynchronizer — authority = peer_id (syncs position from host outward)
```

The `Player` node is named by peer ID (`str(peer_id)`). This is how Godot's high-level
multiplayer finds and routes to the right node.

### Replication Modes

Godot 4 `MultiplayerSynchronizer` replication modes used in this project:

- **Mode 1** (`REPLICATION_MODE_ALWAYS`) — syncs every physics frame. Used for
  `global_position` (and, once added, `velocity`).
- **Mode 2** (`REPLICATION_MODE_ON_CHANGE`) — syncs only when value changes. Used for
  the synced input fields in `PlayerInputSynchronizerComponent`.

When adding replicated properties to the player, add `velocity` (mode 1) alongside
`global_position` for smooth client interpolation.

### SceneReplicationConfig NodePath Syntax

Property paths in `SceneReplicationConfig` use the format `"<node_path>:<property>"`:

- `".:global_position"` — the `.` refers to the root node (resolved via the
  synchronizer's `root_path`). Use this to sync a property on the root itself.
- `".:movement_vector"` — same pattern used by `PlayerInputSynchronizerComponent`
  (where `root_path = "."` so root = the synchronizer itself).
- `"Player:global_position"` — **wrong**. This looks for a *child node named "Player"*
  under the root. After spawning, the player node is renamed to the peer ID, so this
  path never resolves.

**Rule:** always use `".:property"` for properties on the root node. Never use the
scene-editor node name in a replication path — it breaks after spawning renames the node.

### MultiplayerSynchronizer Authority Timing

Call `set_multiplayer_authority()` in `_enter_tree()`, **not** `_ready()`. The
`MultiplayerSynchronizer` children need to register with the correct authority when they
first enter the scene tree. If authority is set in `_ready()`, the synchronizers have
already registered under the wrong peer and Godot logs "has no network ID" errors.

```gdscript
func _enter_tree() -> void:
    set_multiplayer_authority(input_multiplayer_authority)  # set before children register
```

`set_multiplayer_authority(id)` defaults to `recursive = true`, so all child
synchronizers inherit the authority automatically.

### GameConfig / GameManager

`GameConfig` (`resources/game_config.gd`) is a `Resource` subclass holding session-level
settings (currently `max_players`, `respawn_time`). It is not an autoload — it's plain data.
Expect it to grow run-level fields.

`GameManager` (`autoloads/game_manager.gd`) is an autoload `Node` that owns a `GameConfig`
instance (`GameManager.config`) and the local `player_name`. The host sets
`GameManager.config` values before starting the server. All game systems read from
`GameManager.config`. `GameManager` is the natural home for any future run/wave state.

### First-Person Camera (current)

The player ships a **first-person** rig (camera on the player body). Movement is
first-person and **casting aims forward** from the camera (where you look) — keep the aim
output simple (a forward raycast / muzzle spawn point), no ground-cursor in the slice.

The climbing/parkour camera path has been **removed**. The player movement-controller
decision (`RigidBody3D` vs `CharacterBody3D`) is open but does not change the first-person
camera.

### Spell System — BLEND (the combat core)

A spell is a **fusion of two parts**, held in two swappable slots and fused **on cast**:

- **Form** — the delivery shape, and where the mechanical distinctness lives. Ceiling ~7
  (projectile, beam, cone, wall, bubble, AoE burst, trap orb). *Slice:* Projectile, AoE burst.
- **Element** — a thin **damage + reaction** layer on top, driven by a small **reaction
  table**. Sparse — not every element needs every form. *Slice:* Fire, Lightning.
- **Modifier** — *optional.* Event-multiplying / trajectory-scrambling modifiers (Split,
  Bounce, Homing) erode the per-cast legibility that is the whole reason we picked blend →
  **omitted in the slice**, constrained later.

**One cast = one fused effect** (NOT a sequence/program — see the BLEND rationale in
`DESIGN.md`). Depth is **deliberately shallow**; no deep stat-tuning knobs. Implemented as
`@export`-driven Resources under `systems/spells/` (`Spell` / `SpellForm` / `SpellElement` /
`BlendSpell`), cast by a `WandComponent` on the player that holds the `(Form, Element)` pair
and enforces a per-cast `cast_delay`. `Spell` exposes a `cast_on_host()` seam so an authored
`CascadeSpell` (the roadmap A/B) can slot in without reworking the wand.

**Reactions are the emergent chaos**, in two cheap layers (NOT a per-pixel sim):

- **Entity reactions** (status): e.g. Lightning **chains** to nearby units *including
  allies*; Fire applies a **burning DoT** that spreads to adjacent units.
- **World reactions:** a few hand-placed `Area3D` **reactive volumes** with a material tag
  (oil, water). Lightning in water electrifies everyone inside; fire ignites oil and spreads.
  This is the *signature* environmental chaos — done with trigger volumes, **not** a
  falling-sand simulation (out of scope; see `DESIGN.md` → Future Considerations).

**Acquisition is random and keep-or-swap.** Forms/elements drop from enemies. Picking one up
is a **deliberate interact-to-swap** (proximity prompt → press interact) that **drops your
previous spell as a re-grabbable pickup** — a real "keep my Fire or take this Lightning?"
decision, never a silent walk-over overwrite.

All of the above is **host-authoritative**: casts originate on the authority peer, spawn and
resolve on the host (damage incl. friendly fire, reactions), and replicate out.

---

## File Map

```
autoloads/
  game_events.gd              — Global signal bus. Add signals here, not in random scripts.
                                Currently only a leftover `enemy_died` — see roadmap.
  game_manager.gd             — Autoload Node. Owns GameConfig + local player_name.
  network_manager.gd          — Transport abstraction. ONLY file that touches ENet/Steam/relay.

components/
  health_component.gd/.tscn   — max_health (export), current_health, damage(int), died signal.
                                Default max_health → 100 (slice) so friendly fire is funny,
                                not instant-death. Reused by players and enemies.
  stamina_component.gd/.tscn   — Two-pool resource + `depleted` signal. PARKOUR IS CUT and
                                this is OFF the player now; files kept, unused — reserved for
                                a future mana pool.
  player_input_synchronizer_component.gd/.tscn
                              — Extends MultiplayerSynchronizer. Gathers input on the
                                authority peer, replicates it (mode 2). Syncs `movement_vector`
                                (WASD) + `is_jump_pressed`. Cast is RPC-driven (not synced);
                                interact is roadmap.

entities/
  player/
    player.gd                 — First-person RigidBody3D controller: run / jump / look /
                                cast / death-state. Climbing/parkour removed. Controller
                                model (RigidBody3D vs CharacterBody3D) is an open decision.
    player.tscn               — FP body, InputSync, MultiplayerSynchronizer, HealthComponent,
                                mesh + capsule collider, NameLabel, GroundCheck, camera.
                                (WandComponent is added in code, not in the scene.)
  projectiles/                — projectile.gd/.tscn: host-spawned + host-resolved spell
                                projectile (Area3D). BUILT.
  enemies/                    — (roadmap — not built) EnemyBase (CharacterBody3D + Health + AI).
  pickups/                    — (roadmap — not built) Form/Element spell pickups (interact-to-swap).

systems/
  spells/                     — Spell/SpellForm/SpellElement/BlendSpell resources +
                                WandComponent. BUILT.
  reactions/                  — (roadmap — not built) reaction table + Area3D reactive volumes.
  director/                   — (roadmap — not built) host-side wave spawner (timer + waves).

resources/
  game_config.gd              — Resource. max_players, respawn_time. Not an autoload.

ui/
  main_menu/                  — Host/join flow. Validates name, parses IP:port (default 127.0.0.1:3000).
  hud/                        — DEV debug HUD (CanvasLayer): current-spell + HP readout,
                                crosshair, death fade overlay. (Proximity swap prompt is roadmap.)

debug/
  debug.gd                    — Dev-only autostart helper. DEBUG autoload, DISABLED by default.

main.gd                       — MultiplayerSpawner setup, peer_ready RPC, spawn_function.
main.tscn                     — World root: MultiplayerSpawner + a level instance.
test_level.tscn               — Dev sandbox arena (CSG). Now a movement/combat sandbox.
project.godot                 — Autoloads, input map (move_*, cast, jump), Jolt, 1920×1080,
                                D3D12. config_name = "Magick With Friends".
```

---

## What Carries Over From the Framework

The reusable spine that is real and working today:

- [x] Project scaffolding — Jolt, Forward Plus, 1920×1080, D3D12 on Windows
- [x] **`NetworkManager` autoload** — swappable transport layer; ENet today, Steam/relay ready
- [x] ENet host/join — both peers transition to the main scene on connect
- [x] **Multiplayer connection flow** — host spawns self; clients send `peer_ready` RPC;
      max_players gate; despawn on disconnect via `NetworkManager.peer_disconnected`
- [x] `MultiplayerSpawner` in `main.tscn` with a `spawn_function` (names by peer ID, sets
      authority, applies display name)
- [x] `PlayerInputSynchronizerComponent` — gathers input on the authority peer, syncs it (mode 2)
- [x] Player `MultiplayerSynchronizer` — replicates `global_position` (mode 1, spawn=true)
- [x] `HealthComponent` — `max_health`, `damage()`, `died` signal (component pattern)
- [x] `StaminaComponent` — two-pool resource + `depleted` signal (off the player, reserved for mana)
- [x] `GameEvents` autoload — event bus registered in `project.godot`
- [x] **`GameConfig` resource** + **`GameManager` autoload** — session settings + player name
- [x] **IP input field** + name validation in the main menu (falls back to `127.0.0.1:3000`)
- [x] Floating name labels over players; placeholder capsule meshes
- [x] **DEBUG autoload** — disabled-by-default two-window autostart (see below)
- [x] Two-player local multiplayer verified — host and client see each other move (first-person)
- [x] **Blend casting + friendly fire + death/respawn** — built and validated (see `DESIGN.md` roadmap)

---

## DEBUG Autoload — Dev Workflow

`debug/debug.gd` is registered as the `DEBUG` autoload in `project.godot` **without** the
`*` prefix, so it is **disabled by default**. It never runs in normal play or exported builds.

### Enabling for local two-window testing

1. **Enable the autoload** — Project Settings → Autoload → check `DEBUG` (or add `*` before
   `res://debug/debug.gd` in `project.godot`).
2. **Configure Run Instances** — Debug → Customize Run Instances, two instances:

   | Instance | Arguments |
   |----------|-----------|
   | 1 (Host) | `-- host debug_autostart` |
   | 2 (Client) | `-- join debug_autostart` |

   The `--` separator is required — everything after it is read via
   `OS.get_cmdline_user_args()`. Optionally offset window 2 (e.g. x=960) so they don't overlap.
3. **Hit Play (F5).** Both windows launch. Host titles itself `HOST`, client `CLIENT`.

### Disabling before shipping / returning to normal play

| Step | Enabled | Disabled |
|------|---------|----------|
| `project.godot` DEBUG line | `DEBUG="*res://debug/debug.gd"` | `DEBUG="res://debug/debug.gd"` |
| Run Instances Launch Arguments | `-- host/join debug_autostart` | **cleared** |

**Important:** Godot passes Launch Arguments even when "Override Main Run Args" is unchecked.
You must **clear the Launch Arguments**, not just uncheck the autoload. Both steps are required.

### Rule
Never commit `project.godot` with `DEBUG="*res://debug/debug.gd"`. The `*` is dev-local only.

---

## Headless Validation (run before every code PR)

Godot 4.6 lives at:
`C:\Users\Jon\Documents\Game Development\Engines\Godot 4.6\Godot_v4.6-stable_win64.exe`

Before opening **any code PR**, validate headlessly and **do not open the PR if it reports
parse/scene errors**. `.godot/` is gitignored, so runs don't dirty the tree. **Two** checks —
neither alone is complete (verified empirically):

1. **Parse-check each changed `.gd`** — catches syntax errors in **any** script, including
   brand-new files (which check 2 misses):
   ```
   "<godot>" --headless --path "<project>" --check-only --script "res://path/to/changed.gd"
   ```
   **Fail only on `Parse Error` lines.** `--check-only` does NOT load project autoloads, so it
   *falsely* reports `Compile Error: Identifier not found: GameManager / NetworkManager / …`
   for any script that uses an autoload — **ignore those**, they aren't real.
2. **Import-check the project** — catches broken `.tscn`/resource refs and errors in
   **modified existing** scripts (it reloads changed files *with* autoloads available). It
   does **not** reliably parse brand-new files in one run — that's what check 1 is for.
   ```
   "<godot>" --headless --editor --quit --path "<project>"
   ```
   **Fail on `SCRIPT ERROR` / `Parse Error` / `Failed to load`** in its output.
3. **Gameplay boot smoke test** — confirms the project not only *loads* but *runs*: boots a
   headless **host** into the actual game (`Main`, host player spawned) and fails on any
   logged runtime error. Catches `_ready` / spawn / boot errors the load-checks miss, plus
   host-driven systems that run without input (e.g. the enemy/wave director).
   ```
   bash tools/smoke-test.sh
   ```
   It enables the DEBUG autoload for the run (restored on exit), drives `debug.gd`'s `smoke`
   path, and prints `SMOKE: PASS` / `FAIL` (exit 0/1). **Host-driven only** — it does **not**
   exercise input (casting/movement); that stays with the two-window playtest.

Together these catch the "won't parse / won't load / won't boot" bugs a no-Godot session would
ship blind. They are the cheap gate **before** the two-window playtest — not a replacement.

---

## Conventions

### Naming
- Scripts: `snake_case.gd`
- Classes: `PascalCase` (`class_name WandComponent`)
- Signals: `snake_case` past tense (`spell_cast`, `wave_started`)
- Exported variables: `snake_case`, with units in the name where helpful (`cast_delay_sec`)
- Node names in scenes: `PascalCase`

### Script Structure (within a .gd file)
```
class_name / extends
signals
@export vars (public API for designers)
@onready vars
private vars
_ready
_input
_process / _physics_process
public methods
private methods
RPC methods (grouped at bottom, prefixed with intent)
```

### Component Pattern
A "component" is a `Node` (or `MultiplayerSynchronizer`) scene that encapsulates one
responsibility. It does not reach up to its parent — it exposes signals and methods, and the
parent or a coordinator wires them together in `_ready`.

### RPC Pattern
- Client → Host: `@rpc("any_peer", "call_remote", "reliable")` — host checks
  `multiplayer.get_remote_sender_id()`
- Host → All: `@rpc("authority", "call_local", "reliable")` on a node the host owns
- Player input is **never** sent via RPC — use `MultiplayerSynchronizer`

### Scene Instancing
Use `preload("uid://...")` for scenes and scripts referenced in code. Never use string
paths like `"res://entities/player/player.tscn"` — UIDs survive file moves.

### Physics (Jolt)
- **Enemies** are `CharacterBody3D` — drive with `move_and_slide()` after setting `velocity`;
  gravity via `get_gravity()`; `is_on_floor()` for grounded checks. Knockback = add to `velocity`.
- **Player** currently `RigidBody3D` (first-person, legacy). Knockback there is an impulse.
  Controller model is an open decision; don't assume one when writing player-agnostic code.
- **Physics-chaos is a feature** of the friend-slop tone — ragdolls, knockback, ice-slips.
  Keep gameplay-critical physics on a single owner; let purely-cosmetic chaos be loose.
- `RigidBody3D` is fine for physics props (throwables, debris) regardless.
- Jolt is the engine (`project.godot`); test with Jolt enabled — its collision response
  differs from default Godot physics.

### Camera Rig Pattern (First-Person)
The camera lives on the player body. Casting aims forward from the camera (a forward raycast
/ muzzle spawn). No ground-cursor in the slice. Cast *feel* on clients comes from immediate
local cosmetic feedback (muzzle flash), decoupled from host-authoritative resolution.

---

## Known Issues / Watch Out For

- **Player controller is `RigidBody3D` (first-person).** Climbing/parkour has been removed;
  it's now a clean run/jump/look/cast controller. The RigidBody3D-vs-CharacterBody3D
  decision is still open — don't assume one when writing player-agnostic code.
- **Cast feel is host-asymmetric.** Pure host-authority means the host feels instant casts
  and clients eat a round-trip. Use the local cosmetic muzzle flash, and read playtests
  knowing host feel ≠ client feel (rotate who hosts).
- **Spawn height vs capsule:** keep spawn markers at `y≈1.0`+ so the capsule doesn't clip
  the floor.
- **`input_multiplayer_authority` on clients:** `spawn_function` runs on the host only, so
  clients never call `set_multiplayer_authority` on their copy. Works for same-machine
  testing (all peers are peer 1); needs fixing for real multiplayer.
- `main_menu.gd` defaults to `127.0.0.1` and port `3000` (keep the port an `int` — ENet
  requires it).
- `multiplayer.connected_to_server` is only wired for the client path; the host transitions
  immediately — correct, don't add host-side handling.
- `class_name Player` must stay — `main.gd`'s `spawn_function` casts to `Player`.
