# CLAUDE.md — Magick With Friends

Architecture reference for AI-assisted development. Read this before touching any file.

This project began as a generic multiplayer "friend slop" framework and is now being
built into an actual game. The networking spine carries over; the movement, camera, and
combat identity are being rebuilt. **Where this document describes a system the code
does not yet implement, it is clearly marked as roadmap (see "What Is NOT Done").**

---

## Game Vision

**Magick With Friends** is a **3D, online co-op roguelike**.

- **Main influence — Risk of Rain 2.** A run is a series of stages. Difficulty scales
  with elapsed time. You fight escalating hordes, find and *stack* items, buy from
  interactables with gold, clear a per-stage objective (teleporter-style event), and
  loop into the next, harder stage. Up to 4 players co-op, host-authoritative.
- **Secondary influence — Noita.** Combat leans toward **wand-building / spell-
  construction** (assembling spells + modifiers that fire in sequence, with
  mana / cast-delay / recharge), and toward **emergent material/elemental interactions**
  (fire that spreads, liquids, explosions, chain reactions). How deep this goes is a
  **deliberately deferred decision** (see Combat, below).

The camera is **third-person** (RoR2-style orbit). The core loop is being *surrounded by
a scaling horde*, which third-person reads well — situational awareness on all sides,
verticality, visible item-stacking on the body, and seeing your co-op teammates.

### Open design decisions (DECIDE LATER — do not invent these)

- **Combat depth.** Either deep **Noita-style wand-building** (spell + modifier slots
  fired in sequence) **or** a simpler **fixed element-themed ability loadout**
  (RoR2-style primary / secondary / utility / special on cooldowns). The structural
  framework below (ability slots, projectile/effect spawning, status effects) supports
  either; the *content model* is **TBD**.
- **Aim style.** Center-screen reticle (aim where you look) vs a ground cursor
  (raycast a screen-space cursor onto the world for precise AoE placement). Tied to the
  combat decision. **TBD.**
- **Ability resource.** Whether the existing two-pool `StaminaComponent` is repurposed
  into a mana/energy resource or dropped for per-ability cooldowns. **TBD with combat.**

---

## Git Workflow (Non-Negotiable)

- **New branch per task.** Always create `claude/[short-description]` before making any
  changes. Never commit directly to main.
- **Always fetch main first.** Before creating any branch, run
  `git fetch origin main && git reset --hard origin/main` to guarantee the branch starts
  from the actual current state of main. Skipping this causes merge conflicts on every PR.
- **Open a PR when done.** Every task ends with a pull request against main.
- **End-of-task confirmation.** After pushing, always report: branch name, whether it's
  been pushed to remote, and a list of files changed.

---

## Rules (Non-Negotiable)

- **GDScript only.** No C#. Ever.
- **3D only.** No 2D. Jolt physics, `CharacterBody3D`/`RigidBody3D`/`StaticBody3D` nodes.
- **Jolt physics engine.** Set in `project.godot`. Do not switch to default Godot physics.
- **No C# toolchain.** No `.csproj`, no `dotnet`, no NuGet.
- **Do not modify UIDs** in `.tscn` or `.gd.uid` files manually.
- **@export everything tunable.** Any value a non-coder might want to change must be `@export`.
- **Players (and enemies) are `CharacterBody3D`.** Kinematic, `move_and_slide`-driven —
  not physics bodies. (The player script still needs to be migrated off `RigidBody3D` —
  see "What Is NOT Done" item 1.)
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
`join_game()` that create the peer. Nothing else changes.

```gdscript
# Today (ENet):
var peer := ENetMultiplayerPeer.new()
peer.create_server(port)

# Future (Steam):
var peer := SteamMultiplayerPeer.new()
peer.create_host(GameManager.config.max_players)
```

The `multiplayer.*` signal layer above the transport is identical across all backends —
NetworkManager's `_ready` wiring does not change. The file opens with a formal transport
contract comment; read it before adding any connection code.

### Multiplayer Model

ENet host/client. One player is the server (host, peer ID `1`). Others are clients.

- **Input authority:** Each player is `multiplayer_authority` over their own `Player`
  node and `PlayerInputSynchronizerComponent`. Input is gathered locally only on the
  authority peer, then synced to all.
- **Physics authority:** Host runs simulation. Position (and eventually velocity) is
  synced from host to clients via `MultiplayerSynchronizer`.
- **Spawn authority:** Host's `MultiplayerSpawner` in `main.tscn` handles all spawning.
  Clients fire `peer_ready.rpc_id(1)` → host spawns their player via `spawn_function`.
- **RPCs:** Use `@rpc("any_peer", "call_remote", "reliable")` for client→host calls. Use
  `@rpc("authority", "call_local", "reliable")` for host→all broadcasts.

**This same host-authoritative model governs everything net-new** — enemies, the spawn
director, projectiles/spell effects, item pickups, and run/stage state all run on the
host and replicate outward. Clients send intent (input, interact requests) via the
authority/RPC patterns above; the host owns the simulation.

### Node Ownership Pattern

```
Main (Node) — no authority set, runs on all peers
└── Player_{peer_id} (CharacterBody3D) — authority = peer_id
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

When adding replicated properties to the player, add `velocity` (mode 1) to the player's
`MultiplayerSynchronizer` alongside `global_position` for smooth client interpolation.

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
settings (currently `max_players`, `round_timer`, `respawn_time`). It is not an autoload —
it's plain data. Expect it to grow run-level fields (difficulty curve, stage count, etc.).

`GameManager` (`autoloads/game_manager.gd`) is an autoload `Node` that owns a `GameConfig`
instance (`GameManager.config`) and the local `player_name`. The host sets
`GameManager.config` values before starting the server. All game systems read from
`GameManager.config`. `GameManager` is the natural home for the **run/stage state
machine** (see roadmap).

### Third-Person Camera (Target Design)

**ROADMAP — not yet implemented.** The player currently still ships a *first-person*
rig; it is being replaced with a third-person orbit camera.

Target design:

- A `SpringArm3D` anchored to (or following) the player, with the `Camera3D` on its tip,
  so the camera pulls in automatically when geometry occludes it.
- Orbit (yaw/pitch) driven by mouse / right-stick; pitch clamped to a sane overhead range.
- **Movement is camera-relative:** WASD maps onto the camera's flattened forward/right
  basis, so "forward" means "away from camera".
- **Aim** (reticle vs ground cursor) is **TBD** and decided with combat. Keep the camera
  controller's aim output behind a small seam so either can slot in later.

Until migrated, see "What Is NOT Done" item 1. The legacy first-person notes are
intentionally removed from this document.

---

## File Map

```
autoloads/
  game_events.gd              — Global signal bus. Add signals here, not in random scripts.
                                Currently only has a leftover `enemy_died` — see roadmap item 2.
  game_manager.gd             — Autoload Node. Owns GameConfig + local player_name. Set by host
                                before server start. Future home of the run/stage state machine.
  network_manager.gd          — Transport abstraction. ONLY file that touches ENet/Steam/relay.
                                Exposes host_game(), join_game(ip), disconnect_game(), and
                                connection/peer signals. See NetworkManager section above.

components/
  health_component.gd/.tscn   — max_health (export), current_health, damage(int), died signal.
                                Default max_health is currently 1 — bump to 100 (roadmap item 3).
                                Reused by both players and enemies.
  stamina_component.gd/.tscn  — Two-pool resource (primary + bonus buffer) with regen and a
                                `depleted` signal. Built for parkour; PARKOUR IS BEING CUT, so this
                                is repurpose-or-remove pending the combat decision (mana/energy?).
  player_input_synchronizer_component.gd/.tscn
                              — Extends MultiplayerSynchronizer. Reads input on the authority peer
                                and replicates it (mode 2). The synced fields are being re-pointed
                                from climbing/parkour inputs to action/ability slots (roadmap).

entities/player/
  player.gd                   — LEGACY: still a first-person RigidBody3D with climbing/mantle.
                                Slated for a full rewrite to a third-person CharacterBody3D
                                (run/jump/sprint + dash). See "What Is NOT Done" item 1.
  player.tscn                 — Node tree to be reworked alongside the script: CharacterBody3D root,
                                InputSync, position/velocity MultiplayerSynchronizer, HealthComponent,
                                MeshInstance3D + CollisionShape3D (capsule), NameLabel, GroundCheck,
                                third-person camera rig (SpringArm3D + Camera3D).

resources/
  game_config.gd              — Resource. max_players, round_timer, respawn_time. Not an autoload.

ui/main_menu/
  main_menu.gd                — Host/join flow. Validates name, parses IP:port (default
                                127.0.0.1:3000), writes GameManager.player_name, transitions scene.
  main_menu.tscn              — Name field, IP field, Host button, Join button.

debug/
  debug.gd                    — Dev-only autostart helper. Registered as DEBUG autoload but DISABLED
                                by default (no * prefix in project.godot). Reads
                                OS.get_cmdline_user_args(): `-- host debug_autostart` → host;
                                `-- join debug_autostart` → join. Never enable for shipping builds.

ui/hud/
  hud.gd/.tscn                — DEV debug HUD (CanvasLayer). Input glyphs + state readout + the two
                                stamina ProgressBars. A production HUD is still to be built (item 5).

main.gd                       — MultiplayerSpawner setup, peer_ready RPC, spawn_function lambda
                                (names player by peer ID, sets authority, applies player_name).
                                Instantiates the dev HUD on _ready.
main.tscn                     — World root: MultiplayerSpawner + a level instance.
test_level.tscn               — Dev sandbox: CSG geometry (platforms, ramps, walls, a pillar).
                                Originally tuned for climbing tests; now just a movement/combat
                                sandbox. Open directly in editor to test.
project.godot                 — Autoloads (GameEvents, GameManager, NetworkManager, DEBUG-disabled),
                                input map, Jolt, 1920×1080, D3D12. NOTE: application/config_name is
                                still "Friend Slop Framework" — rename to "Magick With Friends".
```

---

## What Carries Over From the Framework

The reusable spine that is real and working today:

- [x] Project scaffolding — Jolt, Forward Plus, 1920×1080, D3D12 on Windows
- [x] **`NetworkManager` autoload** — swappable transport layer; ENet today, Steam/relay ready
- [x] ENet host/join — host creates server peer, client creates client peer, both transition
      to the main scene on connect
- [x] **Multiplayer connection flow** — host spawns self directly; clients send `peer_ready`
      RPC (call_remote, timing-safe); max_players gate; despawn on disconnect via
      `NetworkManager.peer_disconnected`
- [x] `MultiplayerSpawner` in `main.tscn` with a `spawn_function` that names the player by
      peer ID, sets authority, and applies the display name
- [x] `PlayerInputSynchronizerComponent` — gathers input on the authority peer and syncs it (mode 2)
- [x] Player `MultiplayerSynchronizer` — replicates `global_position` (mode 1, spawn=true)
- [x] `HealthComponent` — `max_health`, `damage()`, `died` signal (component pattern)
- [x] `StaminaComponent` — two-pool resource + `depleted` signal (pending repurpose)
- [x] `GameEvents` autoload — event bus registered in `project.godot`
- [x] **`GameConfig` resource** + **`GameManager` autoload** — session settings + player name
- [x] **IP input field** + name validation in the main menu (falls back to `127.0.0.1:3000`)
- [x] Floating name labels over players; placeholder capsule meshes
- [x] **DEBUG autoload** — disabled-by-default two-window autostart (see below)
- [x] Two-player local multiplayer verified — host and client see each other move

> Movement currently works via the legacy first-person `RigidBody3D` controller (with a
> climbing/mantle/parkour-stamina system). That controller is **being replaced**, not kept
> — it is listed here only to describe the current running state, not the target design.

---

## DEBUG Autoload — Dev Workflow

`debug/debug.gd` is registered as the `DEBUG` autoload in `project.godot` **without** the
`*` prefix, which means it is **disabled by default**. It never runs in normal play or in
exported builds.

### Enabling for local two-window testing

1. **Enable the autoload** — Project Settings → Autoload → check `DEBUG` (or manually add
   `*` before `res://debug/debug.gd` in `project.godot`).
2. **Configure Run Instances** — Debug → Customize Run Instances, two instances:

   | Instance | Arguments |
   |----------|-----------|
   | 1 (Host) | `-- host debug_autostart` |
   | 2 (Client) | `-- join debug_autostart` |

   The `--` separator is required — everything after it is a user arg, read via
   `OS.get_cmdline_user_args()`. Optionally offset window 2 (e.g. x=960) so they don't overlap.
3. **Hit Play (F5).** Both windows launch. Host titles itself `HOST`, client `CLIENT`.

### Disabling before shipping / returning to normal play

Both must be true for debug autostart to be fully off:

| Step | Enabled | Disabled |
|------|---------|----------|
| `project.godot` DEBUG line | `DEBUG="*res://debug/debug.gd"` | `DEBUG="res://debug/debug.gd"` |
| Run Instances Launch Arguments | `-- host/join debug_autostart` | **cleared** |

**Important:** Godot passes Launch Arguments even when "Override Main Run Args" is
unchecked. You must **clear the Launch Arguments**, not just uncheck the autoload. Both
steps are required.

### Rule
Never commit `project.godot` with `DEBUG="*res://debug/debug.gd"`. The `*` is dev-local only.

---

## What Is NOT Done (Priority Order)

This is the roadmap from the current framework state to the game. Everything below is
host-authoritative and reuses the existing `MultiplayerSpawner` / RPC / `GameEvents`
patterns.

### 1. Rewrite the Player: first-person RigidBody3D → third-person CharacterBody3D
The single biggest change. Replace the legacy controller with a kinematic
`CharacterBody3D` driven by `move_and_slide`:
- Camera-relative WASD run, jump, sprint, and a RoR2-style **dash/dodge** utility.
- **Remove** all climbing, 8-ray wall detection, mantle, and lunge logic.
- Build the **third-person orbit camera** (SpringArm3D + Camera3D) described above.
- Rework `player.tscn` accordingly; keep `class_name Player` (main.gd's `spawn_function`
  casts to it) and the `_enter_tree` authority timing.
- Re-point `PlayerInputSynchronizerComponent`'s synced fields from parkour inputs to
  action slots (move, jump, sprint, dash, interact, ability primary/secondary/utility/special).

### 2. GameEvents Signals
`game_events.gd` has a leftover `enemy_died` signal and `emit_enemy_died()` helper.
Replace with the game's vocabulary and let callers emit directly:
```gdscript
signal player_died(peer_id: int)
signal enemy_died(enemy_id: int, position: Vector3)
signal run_started
signal stage_started(stage_index: int)
signal stage_cleared(stage_index: int)
signal run_ended(victory: bool)
signal item_picked_up(peer_id: int, item_id: StringName)
```

### 3. HealthComponent for a real game
Change `max_health` default from `1` to `100`. Add the RoR2-style extensions: passive
regen, a shield/barrier pool, brief invincibility frames after a hit, and knockback
(applied as a `CharacterBody3D` velocity, not an impulse). Used by players and enemies.

### 4. Input Map: ability + interact actions, and gamepad
`project.godot` currently has `move_*`, `grab` (LMB), `attack` (RMB), `sprint`, `jump` —
several of those names are parkour leftovers. Define the action slots the new controller
needs (cast primary/secondary, utility, special, interact) and add gamepad bindings:
- `move_*` → left stick; look → right stick (handled in the camera script, not the map)
- jump → South face button; dash/abilities/interact → TBD buttons/triggers

### 5. Production In-Game HUD
A dev debug HUD exists (`ui/hud/`). Build a production HUD: health + shield bar, ability
icons with cooldown sweeps, item inventory (stacks), gold/credits, and a run timer +
difficulty meter. Reads the local player's components; listens to `GameEvents`.

### 6. Run / Stage State Machine
The structural heart of the RoR2 loop, owned at the `GameManager` level: `run_started` →
`stage_started` → a per-stage objective/teleporter event → `stage_cleared` → next (harder)
stage → … → `run_ended`. Drives difficulty scaling and emits the `GameEvents` above.

### 7. Spawn Director / Enemy Spawning
Host-side director (`autoloads/director.gd` or under `systems/`) with a **credit budget**
that grows with elapsed time and stage index. It picks enemies from a spawn table and
replicates them via a `MultiplayerSpawner`. This is what makes the horde scale.

### 8. Enemy Entities
`EnemyBase` (`CharacterBody3D`) reusing `HealthComponent`, with simple host-run AI
(navigate toward the nearest player, attack in range). Death emits `enemy_died` and rolls
drops (gold, items). Lives under `entities/enemies/`.

### 9. Items / Pickups / Currency
Stacking-item inventory component, item-effect hooks fired off `GameEvents`, gold/credits,
and interactables (chests, shops) with a purchase cost. Items drop from enemies/chests.
Visual item-stacking on the body is a later nicety.

### 10. Abilities / Spell System (combat — DECIDE LATER)
Build the *framework* (ability/spell slots, cooldowns or mana, projectile/effect spawning
& sync, elemental **status effects** like burn/chill/shock as a status-component pattern)
**without committing the content model**. The fork — deep **Noita wand-building** vs a
**fixed element-themed loadout** — is an explicit open decision. Do not pick one
unprompted.

### 11. Spawn Point System
`main.tscn` has a single spawn marker. Add several (4–8) spread around the arena, selected
by player index so players don't spawn on top of each other.

### 12. Client-Side Authority Propagation
`input_multiplayer_authority` is set by `main.gd`'s `spawn_function`, which runs on the
**host**. Clients receive the spawned node via replication but `spawn_function` does not
run on clients, so `set_multiplayer_authority()` is never called on their copy. Works for
same-machine testing (all peers are peer 1); needs fixing for real multiplayer. Options:
include the peer ID in the spawn state, RPC the host→client `set_multiplayer_authority`,
or parse it from the node name on the client's `MultiplayerSpawner.spawned` signal.

### 13. Velocity Sync for Smooth Interpolation
The player `MultiplayerSynchronizer` only syncs `global_position`. Add `velocity` (mode 1)
for smoother client-side interpolation once movement feel is stable. Godot 4.6's
`MultiplayerSynchronizer` interpolation can be enabled then too.

### 14. Main Menu / Project Cleanup
Wire the main menu to set `GameManager.config` (max_players, etc.) before hosting. Rename
`application/config_name` from "Friend Slop Framework" to "Magick With Friends".

---

## Conventions

### Naming
- Scripts: `snake_case.gd`
- Classes: `PascalCase` (`class_name PlayerInputSynchronizerComponent`)
- Signals: `snake_case` past tense (`player_died`, `stage_cleared`)
- Exported variables: `snake_case`, with units in the name where helpful (`dash_force`,
  `respawn_time_sec`) — or just use comments
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
responsibility. It does not reach up to its parent — it exposes signals and methods, and
the parent or a coordinator wires them together in `_ready`.

### RPC Pattern
- Client → Host: `@rpc("any_peer", "call_remote", "reliable")` — host checks
  `multiplayer.get_remote_sender_id()`
- Host → All: `@rpc("authority", "call_local", "reliable")` on a node the host owns
- Player input is **never** sent via RPC — use `MultiplayerSynchronizer` (lower overhead,
  automatic)

### Scene Instancing
Use `preload("uid://...")` for scenes and scripts referenced in code. Never use string
paths like `"res://entities/player/player.tscn"` — UIDs survive file moves.

### Physics (Jolt + CharacterBody3D)
- Players and enemies are **`CharacterBody3D`**. Drive them with `move_and_slide()` after
  setting `velocity`.
- Gravity: accumulate `velocity += get_gravity() * delta` each `_physics_process` while
  not on floor; check `is_on_floor()` for grounded state and jump eligibility.
- Horizontal movement: lerp/accelerate `velocity.x`/`velocity.z` toward the camera-relative
  input direction × speed; apply friction only to the horizontal plane so jumps/gravity
  on Y are unaffected.
- **Knockback / impulses** are applied by adding to `velocity` directly — there is no
  `apply_central_impulse` on a `CharacterBody3D`.
- Jolt is still the engine (set in `project.godot`); test interactions with Jolt enabled,
  as its collision response differs from Godot default physics.
- `RigidBody3D` is still allowed for *physics props* (throwables, debris) — just not for
  the player/enemy controllers.

### Camera Rig Pattern (Third-Person — target)
A `SpringArm3D` parented to (or following) the player carries the `Camera3D` on its tip so
the camera auto-pulls-in on occlusion. Orbit yaw/pitch come from mouse/right-stick (pitch
clamped to a sensible overhead range). Movement input is transformed into the camera's
flattened forward/right basis so "up" on the stick means "away from camera". Keep the
aim-target output (reticle vs ground-cursor raycast) behind a small seam — it's **TBD**.

---

## Known Issues / Watch Out For

- **Player controller is mid-migration.** The shipped `player.gd` is still the legacy
  first-person `RigidBody3D` parkour controller. Treat its movement/camera code as
  scheduled for replacement (roadmap item 1), not as the pattern to extend.
- **Spawn height vs capsule:** the spawn marker sits near `y=0`; with a 0.9 m capsule
  half-height, spawning at `y=0` clips the body into the ground. Keep spawn markers at
  least `y≈1.0`. Re-verify once the controller is `CharacterBody3D`.
- **`input_multiplayer_authority` on clients:** see roadmap item 12. Local same-machine
  testing works because `is_multiplayer_authority()` defaults to peer 1; real authority
  propagation is deferred.
- `main_menu.gd` defaults to `127.0.0.1` and port `3000` (keep the port an `int` — ENet
  requires it). Same-machine / LAN testing until a real address is entered.
- `multiplayer.connected_to_server` is only wired for the client path. The host transitions
  immediately — this is correct; do not add `connected_to_server` handling for the host.
- `class_name Player` must stay — `main.gd`'s `spawn_function` casts to `Player`.
- `project.godot` still names the app "Friend Slop Framework" (roadmap item 14).

---

## Future Considerations (Do Not Implement Yet)

- **Noita-style material simulation.** Emergent material/elemental interactions (fire
  spreading across surfaces/liquids, explosions, electrified water, chain reactions). Full
  per-voxel/per-particle simulation is expensive and hard to net-replicate in 3D —
  approximate it (status-tagged volumes, area triggers, simple propagation) before
  attempting anything simulation-grade. Out of scope until core combat lands.
- **Steam networking** — replace the ENet peer with `SteamMultiplayerPeer` from GodotSteam.
  Keep all spawn/RPC logic identical (that's the whole point of `NetworkManager`).
- **Cloudflare Workers / WebSocket relay** — for online play without port forwarding.
- **Game mode system** — a `GameMode` resource/autoload listening to `GameEvents` that
  enforces variant rules (scoring, modifiers, objectives). Design as optional.
- **Spectator camera** — free-fly cam for dead players, constrained to world bounds, until
  the next stage / revive.
- **Lobby / ready system** — pre-run lobby with character select and a ready check before
  the host starts the run.
- **Right-stick look (gamepad)** — `Input.get_axis(...)` in the camera script; needs the
  look actions added to `project.godot`.
