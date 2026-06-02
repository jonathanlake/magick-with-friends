# CLAUDE.md — Friend Slop Framework

Architecture reference for AI-assisted development. Read this before touching any file.

---

## Git Workflow (Non-Negotiable)

- **New branch per task.** Always create `claude/[short-description]` before making any changes. Never commit directly to main.
- **Always fetch main first.** Before creating any branch, run `git fetch origin main && git reset --hard origin/main` to guarantee the branch starts from the actual current state of main. Skipping this causes merge conflicts on every PR.
- **Open a PR when done.** Every task ends with a pull request against main.
- **End-of-task confirmation.** After pushing, always report: branch name, whether it's been pushed to remote, and a list of files changed.

---

## Rules (Non-Negotiable)

- **GDScript only.** No C#. Ever.
- **3D only.** No 2D. Jolt physics, `CharacterBody3D`/`RigidBody3D`/`StaticBody3D` nodes.
- **Jolt physics engine.** Set in `project.godot`. Do not switch to default Godot physics.
- **No C# toolchain.** No `.csproj`, no `dotnet`, no NuGet.
- **Do not modify UIDs** in `.tscn` or `.gd.uid` files manually.
- **@export everything tunable.** Any value a non-coder might want to change must be `@export`.
- **Component pattern.** Behavior goes in component nodes, not monolithic scripts.
- **Event bus pattern.** Cross-system communication goes through `GameEvents` signals. No direct node references across unrelated systems.
- **Swappable transport.** All network peer creation lives in `NetworkManager.host_game()` and `NetworkManager.join_game()` only. No other file may import or reference `ENetMultiplayerPeer` (or any future transport class) directly.

---

## Architecture Overview

### NetworkManager — Swappable Transport Layer

`NetworkManager` (`autoloads/network_manager.gd`) is the **only** file that knows which transport is in use. The rest of the codebase calls:

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

**To swap ENet for Steam/relay:** replace the two lines inside `host_game()` and `join_game()` that create the peer. Nothing else changes.

```gdscript
# Today (ENet):
var peer := ENetMultiplayerPeer.new()
peer.create_server(port)

# Future (Steam):
var peer := SteamMultiplayerPeer.new()
peer.create_host(GameManager.config.max_players)
```

The `multiplayer.*` signal layer above the transport is identical across all backends — NetworkManager's `_ready` wiring does not change.

### Multiplayer Model

ENet host/client. One player is the server (host, peer ID `1`). Others are clients.

- **Input authority:** Each player is `multiplayer_authority` over their own `Player` node and `PlayerInputSynchronizerComponent`. Input is gathered locally only on the authority peer, then synced to all.
- **Physics authority:** Host runs simulation. Position (and eventually velocity) is synced from host to clients via `MultiplayerSynchronizer`.
- **Spawn authority:** Host's `MultiplayerSpawner` in `main.tscn` handles all spawning. Clients fire `peer_ready.rpc_id(1)` → host spawns their player via `spawn_function`.
- **RPCs:** Use `@rpc("any_peer", "call_remote", "reliable")` for client→host calls. Use `@rpc("authority", "call_local", "reliable")` for host→all broadcasts.

### Node Ownership Pattern

```
Main (Node) — no authority set, runs on all peers
└── Player_{peer_id} (RigidBody3D) — authority = peer_id
    ├── PlayerInputSynchronizerComponent — authority = peer_id (gathers input locally, syncs out)
    └── MultiplayerSynchronizer — authority = peer_id (syncs position from host outward)
```

The `Player` node is named by peer ID (`str(peer_id)`). This is how Godot's high-level multiplayer finds and routes to the right node.

### Replication Modes

Godot 4 `MultiplayerSynchronizer` replication modes used in this project:

- **Mode 1** (`REPLICATION_MODE_ALWAYS`) — syncs every physics frame. Used for `global_position`.
- **Mode 2** (`REPLICATION_MODE_ON_CHANGE`) — syncs only when value changes. Used for `movement_vector` and `is_attacked_pressed` in `PlayerInputSynchronizerComponent`.

When adding replicated properties to `RigidBody3D`, add `linear_velocity` and `angular_velocity` to the player's `MultiplayerSynchronizer` alongside `global_position`.

### SceneReplicationConfig NodePath Syntax

Property paths in `SceneReplicationConfig` use the format `"<node_path>:<property>"`:

- `".:global_position"` — the `.` refers to the root node (resolved via the synchronizer's `root_path`). Use this to sync a property on the root itself.
- `".:movement_vector"` — same pattern used by `PlayerInputSynchronizerComponent` (where `root_path = "."` so root = the synchronizer itself).
- `"Player:global_position"` — **wrong**. This looks for a *child node named "Player"* under the root. After spawning, the player node is renamed to the peer ID, so this path never resolves.

**Rule:** always use `".:property"` for properties on the root node. Never use the scene-editor node name in a replication path — it breaks after spawning renames the node.

### MultiplayerSynchronizer Authority Timing

Call `set_multiplayer_authority()` in `_enter_tree()`, **not** `_ready()`. The `MultiplayerSynchronizer` children need to register with the correct authority when they first enter the scene tree. If authority is set in `_ready()`, the synchronizers have already registered under the wrong peer and Godot logs "has no network ID" errors.

```gdscript
func _enter_tree() -> void:
    set_multiplayer_authority(input_multiplayer_authority)  # set before children register
```

`set_multiplayer_authority(id)` defaults to `recursive = true`, so all child synchronizers inherit the authority automatically.

### GameConfig / GameManager

`GameConfig` (`resources/game_config.gd`) is a `Resource` subclass holding session-level settings (`max_players`, `round_timer`, `respawn_time`). It is not an autoload — it's plain data.

`GameManager` (`autoloads/game_manager.gd`) is an autoload `Node` that owns a `GameConfig` instance (`GameManager.config`). The host sets `GameManager.config` values before starting the server. All game systems read from `GameManager.config`.

---

## File Map

```
autoloads/
  game_events.gd              — Global signal bus. Add signals here, not in random scripts.
  game_manager.gd             — Autoload Node. Owns GameConfig. Set by host before server start.
  network_manager.gd          — Transport abstraction. ONLY file that touches ENet/Steam/relay.
                                Exposes host_game(), join_game(ip), disconnect_game(), and
                                connection/peer signals. See NetworkManager section above.

components/
  health_component.gd/.tscn   — max_health (export), current_health, damage(int), died signal
  stamina_component.gd/.tscn  — Two-tier stamina: primary (regens on ground) drains first, then
                                bonus buffer. depleted signal fires when both reach 0.
                                Exports: max_primary, max_bonus, primary_regen_rate.
  player_input_synchronizer_component.gd/.tscn
                              — Extends MultiplayerSynchronizer. Reads input on authority peer,
                                replicates movement_vector (Vector2), is_attacked_pressed,
                                is_jump_pressed, is_grab_pressed, is_sprint_pressed (all mode 2).

entities/player/
  player.gd                   — Extends RigidBody3D. First-person camera rig, WASD forces,
                                mouse look, climbing, mantle. All movement in _integrate_forces.
                                Climbing: 8 horizontal rays detect walls (PhysicsDirectSpaceState3D),
                                grab=LMB holds player on surface, W/S uses wall-up axis, sprint
                                while climbing lunges off wall. Mantle fires when wall runs out
                                while climbing upward: position step-up + forward impulse.
  player.tscn                 — Node tree: Player (RigidBody3D) > [InputSync, PositionSync,
                                HealthComponent, StaminaComponent, MeshInstance3D,
                                CollisionShape3D, NameLabel, GroundCheck, CameraRig]
                                CameraRig is top_level=true so it doesn't inherit body transform.

resources/
  game_config.gd              — Resource. max_players, round_timer, respawn_time. Not an autoload.

ui/main_menu/
  main_menu.gd                — ENet host/join, hardcoded IP (127.0.0.1), scene transition.
  main_menu.tscn              — Host button, Join button (IP field not yet added).

debug/
  debug.gd                    — Dev-only autostart helper. Registered as DEBUG autoload but DISABLED
                                by default (no * prefix in project.godot). Reads OS.get_cmdline_user_args():
                                `-- host debug_autostart` → host game; `-- join debug_autostart` → join.
                                Never enable for shipping builds.

ui/hud/
  hud.gd/.tscn                — Dev debug HUD (CanvasLayer, top-right). Shows pressed inputs with
                                ■/□ glyphs, wall detection / climbing / grounded state, surface
                                normal, and two ProgressBars (green=primary stamina,
                                yellow=bonus). Instantiated by main.gd on _ready.

main.gd                       — MultiplayerSpawner setup, peer_ready RPC, spawn_function lambda.
                                Instantiates HUD on _ready.
main.tscn                     — World root: sky, light, ground, MultiplayerSpawner, spawn marker.
test_level.tscn               — Dev test scene. CSG geometry: main platform, 3 ramps (20°/35°/45°),
                                2 raised platforms, step, wall, drop-off edges, tall cliff face,
                                overhang, chimney gap, pillar for climbing tests. Uses main.gd.
                                Open directly in editor to test movement and physics.
project.godot                 — Autoloads (GameEvents, GameManager), input map, Jolt, 1920×1080.
```

---

## What Is Done

- [x] Project scaffolding — Jolt, Forward Plus, 1920×1080
- [x] Input map — WASD + arrow keys for movement, left mouse for attack, deadzone 0.2
- [x] ENet host/join — host creates server peer, client creates client peer, both transition to main scene on connect
- [x] `MultiplayerSpawner` in `main.tscn` with `spawn_function` that names player by peer ID and sets authority
- [x] `peer_ready` RPC pattern — client notifies host, host spawns
- [x] `PlayerInputSynchronizerComponent` — gathers `movement_vector` and `is_attacked_pressed`, syncs both (mode 2)
- [x] Player `MultiplayerSynchronizer` — replicates `global_position` (mode 1, spawn=true)
- [x] `HealthComponent` — `max_health`, `damage()`, `died` signal
- [x] `GameEvents` autoload — event bus registered in `project.godot`
- [x] Basic world — procedural sky, directional light with shadows, 20×20 ground plane with collision
- [x] **Player converted to `RigidBody3D`** — all angular axes locked, Jolt-native physics
- [x] **Player movement** — `_integrate_forces`, horizontal-only friction, camera-relative forces, `max_speed` cap
- [x] **First-person camera rig** — `top_level = true` Node3D child, position lerps to body, mouse look (yaw + pitch clamped ±89°)
- [x] **`ConvexPolygonShape3D` replaced** with `CapsuleShape3D` (radius 0.4, height 1.8) — much cheaper
- [x] **`GameConfig` resource** — `max_players`, `round_timer`, `respawn_time` as `@export` vars
- [x] **`GameManager` autoload** — owns a `GameConfig` instance, registered in `project.godot`
- [x] **`NetworkManager` autoload** — swappable transport layer; ENet today, Steam/relay ready
- [x] **Multiplayer connection flow** — host spawns self directly; clients send `peer_ready` RPC (call_remote, timing-safe); max_players gate; despawn on disconnect via `NetworkManager.peer_disconnected`
- [x] **IP input field** — `LineEdit` in main menu; falls back to `127.0.0.1` if blank
- [x] **Camera height** — default `0.75` (eye level near top of 1.8m capsule)
- [x] **Two-player local multiplayer verified** — host and client see each other move; `set_multiplayer_authority` in `_enter_tree`, `SceneReplicationConfig` path `".:global_position"`
- [x] **DEBUG autoload** — `debug/debug.gd` registered disabled; reads `-- host debug_autostart` / `-- join debug_autostart` user args
- [x] **Jump action** — Space key in `project.godot`; `is_jump_pressed` synced via `PlayerInputSynchronizerComponent`; `RayCast3D` (`GroundCheck`, target -1.1 m) in `player.tscn`; rising-edge detection in `_process`, impulse applied in `_integrate_forces`; `@export var jump_force: float = 7.0`
- [x] **Test level** — `test_level.tscn`: CSG-based, main 24×24 platform, three ramps (20°/35°/45°), two raised platforms, a step, a wall, drop-off edges, tall cliff face, overhang, chimney gap, pillar; procedural sky + directional light; uses `main.gd` for multiplayer spawner
- [x] **Input map updated** — `grab` action on LMB; `sprint` on Left Shift; `attack` moved to RMB; `jump` on Space. All synced via `PlayerInputSynchronizerComponent` (mode 2).
- [x] **StaminaComponent** — `components/stamina_component.gd/.tscn`; two-tier: primary drains first (regens on ground), then bonus buffer; `depleted` signal fires when both reach 0
- [x] **Climbing system** — grab (LMB) + wall proximity activates climbing; 8 horizontal `PhysicsDirectSpaceState3D` rays detect any nearby wall; W/S uses `Vector3.UP` projected onto surface normal so movement is vertical on walls; A/D uses camera-right projected onto surface for lateral sliding; gravity cancelled and stick force applied while climbing; stamina drains at `climb_drain_rate` per second
- [x] **Lunge** — Sprint (Shift) while climbing applies an impulse away from wall + upward; costs `lunge_stamina_cost` stamina
- [x] **Mantle** — when climbing stops because wall runs out (player centre clears ledge top) while grab is held and upward velocity ≥ `mantle_velocity_threshold`, a position step-up (`mantle_step_height = 0.9`) clears the capsule corner then a forward impulse carries the player onto the ledge
- [x] **Debug HUD** — `ui/hud/hud.gd/.tscn`; CanvasLayer top-right; shows input glyphs, wall detection / climbing / grounded state, surface normal, primary (green) and bonus (yellow) stamina bars; instantiated by `main.gd`

---

## DEBUG Autoload — Dev Workflow

`debug/debug.gd` is registered as the `DEBUG` autoload in `project.godot` **without** the `*` prefix, which means it is **disabled by default**. It never runs in normal play or in exported builds.

### Enabling for local two-window testing

1. **Enable the autoload** — open Project Settings → Autoload, find `DEBUG`, check the Enabled box (or manually add `*` before `res://debug/debug.gd` in `project.godot`).
2. **Configure Run Instances** — open Debug → Customize Run Instances and set up two instances:

   | Instance | Arguments |
   |----------|-----------|
   | 1 (Host) | `-- host debug_autostart` |
   | 2 (Client) | `-- join debug_autostart` |

   The `--` separator is required — it tells Godot everything after it is a user arg, accessible via `OS.get_cmdline_user_args()`. Optionally set window offsets so the two windows don't overlap (e.g. instance 2 at x=960, y=0).

3. **Hit Play (F5).** Both windows launch automatically. The host window titles itself `HOST`, the client `CLIENT`.

### Disabling before shipping / returning to normal play

Both of the following must be true for debug autostart to be fully off:

| Step | Enabled state | Disabled state |
|------|--------------|----------------|
| `project.godot` DEBUG line | `DEBUG="*res://debug/debug.gd"` | `DEBUG="res://debug/debug.gd"` |
| Run Instances Launch Arguments | `-- host debug_autostart` / `-- join debug_autostart` | **cleared** |

**Important:** Godot passes Launch Arguments to each instance even when "Override Main Run Args" is unchecked. If the args are still present, `debug_autostart` reaches the script. You must **clear the Launch Arguments** in Debug → Customize Run Instances, not just uncheck the autoload. Both steps are required.

- Do **not** enable it in export presets or CI builds. Since the autoload is off by default, an accidental ship is safe — the script does nothing unless the flag is enabled and the user args are passed at launch.

### Rule
Never commit `project.godot` with `DEBUG="*res://debug/debug.gd"`. The `*` is a dev-local change only.

---

## What Is NOT Done (Priority Order)

### 1. Gamepad Input Bindings
`project.godot` only has keyboard/mouse bindings. Add gamepad events to each action:
- `move_left/right/up/down` → left joystick axis
- `attack` → right trigger or face button (TBD)
- `jump` → South face button (Cross/A) — keyboard Space already wired
- Look → right joystick (handled in `player.gd`, not input map — use `Input.get_axis`)

### 2. GameEvents Signals
`game_events.gd` has a leftover `enemy_died` signal. Replace with:
```gdscript
signal player_died(peer_id: int)
signal round_started
signal round_ended(winner_peer_id: int)  # -1 for draw/timeout
```
Remove `emit_enemy_died()` helper — callers should emit directly (`GameEvents.player_died.emit(peer_id)`).

### 3. HealthComponent Default
Change `max_health` default from `1` to `100` in `health_component.gd`.

### 4. Respawn System
Nothing handles player death → respawn. After `HealthComponent.died` fires:
- Emit `GameEvents.player_died`
- Disable player collision/visibility briefly
- After `respawn_time` seconds (from `GameManager.config`), teleport to spawn point and reset health
- `main.tscn` currently has one `Marker3D`. Add 4 and assign by index.

### 5. Production In-Game HUD
A dev debug HUD exists (`ui/hud/`) showing stamina bars and state. A production HUD still needs:
- Health bar (reads local player's `HealthComponent`)
- Player count / connected peers display
- Round timer

### 6. Player Position Sync for RigidBody3D
The existing `MultiplayerSynchronizer` on the player only syncs `global_position`. For smooth client-side interpolation, add:
- `linear_velocity` (mode 1)
- `angular_velocity` (mode 1)

### 7. Multiplayer Authority on Clients
`input_multiplayer_authority` is set by `main.gd`'s `spawn_function`, which runs on the host. Clients receive the spawned node via replication but `spawn_function` does NOT run on clients — so `set_multiplayer_authority()` is never called on the client's copy.

**Current workaround:** None. Works fine for same-machine testing (all peers are peer 1). Needs fixing before real multiplayer. Options:
- Include peer ID in the `MultiplayerSpawner` spawn state (replicated automatically)
- Send an RPC from host to each client after spawning to call `set_multiplayer_authority` locally
- Use `MultiplayerSpawner`'s `spawned` signal on clients to set authority by parsing the node name (which is the peer ID)

### 8. Main Menu: Wire GameConfig
`main_menu.gd` doesn't yet read from or write to `GameManager.config`. Before the host starts the server, it should set `GameManager.config.max_players` (and any other session settings exposed in the UI) so game systems can read them at runtime.

### 9. Spawn Point System
`main.tscn` has a single `Marker3D` for spawn positions. Needs 4 (up to 8) spread around the arena, selected by player index to avoid spawning on top of each other.

### 10. Lag Compensation / Interpolation
Not urgent. Godot 4.6 has `MultiplayerSynchronizer` interpolation support. Enable after physics feel is stable.

---

## Conventions

### Naming
- Scripts: `snake_case.gd`
- Classes: `PascalCase` (`class_name PlayerInputSynchronizerComponent`)
- Signals: `snake_case` past tense (`player_died`, `round_ended`)
- Exported variables: `snake_case` with units in name where helpful (`jump_strength_n`, `respawn_time_sec`) — or just use comments
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
_process / _physics_process / _integrate_forces
public methods
private methods
RPC methods (grouped at bottom, prefixed with intent)
```

### Component Pattern
A "component" is a `Node` (or `MultiplayerSynchronizer`) scene that encapsulates one responsibility. It does not reach up to its parent — it exposes signals and methods, and the parent or a coordinator wires them together in `_ready`.

### RPC Pattern
- Client → Host: `@rpc("any_peer", "call_remote", "reliable")` — host checks `multiplayer.get_remote_sender_id()`
- Host → All: `@rpc("authority", "call_local", "reliable")` on a node the host owns
- Input is **never** sent via RPC — use `MultiplayerSynchronizer` instead (lower overhead, automatic)

### Scene Instancing
Use `preload("uid://...")` for scenes and scripts referenced in code. Never use string paths like `"res://entities/player/player.tscn"` — UIDs survive file moves.

### Physics (Jolt-specific)
- Prefer `apply_central_impulse()` for discrete actions (jump, hit knockback)
- Prefer `apply_central_force()` in `_integrate_forces` for continuous movement
- Do not call `move_and_slide()` on `RigidBody3D` — that's `CharacterBody3D` only
- All three angular axes are locked on the Player body — do not unlock them; the camera handles yaw, and pitch is irrelevant for a capsule body
- `linear_damp` is NOT set on the Player body. Horizontal friction is applied manually in `_integrate_forces` using `ground_friction * state.step` so that the Y axis (gravity, jumps) is unaffected
- `state.step` in `PhysicsDirectBodyState3D` gives the physics timestep in seconds — use it for friction calculations inside `_integrate_forces`
- Jolt handles collision response differently from Godot default physics — test interactions with Jolt enabled

### Camera Rig Pattern
The `CameraRig` node uses `top_level = true`, which means its global transform is independent of its parent's transform. This prevents the RigidBody3D's orientation from affecting the camera. In `_process`:
- Position is lerped toward `player.global_position + Vector3(0, camera_height, 0)` using `camera_smoothing * delta`
- `camera_rig.global_rotation.y` is set directly from `_camera_yaw`
- `camera.rotation.x` is set directly from `_camera_pitch` (clamped ±89°)

---

## Known Issues / Watch Out For

- **Spawn height:** The `PlayerSpawnPosition` Marker3D in `main.tscn` is at world origin (y=0). With the capsule's half-height of 0.9m, spawning at y=0 places the body half inside the ground. Raise the marker to at least y=1.0 in the editor to spawn above the ground plane.
- **Camera initial position:** Set to the spawn position in `_ready`. If the physics body teleports after `_ready` (e.g., due to spawn sequencing), there will be a one-frame camera snap. The `camera_smoothing` lerp will recover in ~1 frame at high values.
- **`input_multiplayer_authority` on clients:** See "What Is NOT Done" item 9. For local testing (host + clients on same machine), everything works because `is_multiplayer_authority()` defaults to peer 1. Real multiplayer authority propagation is deferred.
- `main_menu.gd` hardcodes `127.0.0.1`. Same-machine testing only until the IP field is added.
- `multiplayer.connected_to_server` is only connected for the client path. The host transitions immediately. This is correct — do not add `connected_to_server` handling for the host.
- Port `3000` is a constant in `main_menu.gd`. Keep it as `int` (ENet requires `int`, not `String`).
- The `class_name Player` must stay — `main.gd`'s `spawn_function` casts to `Player`.
- **Climbing wall detection** casts 8 horizontal rays from `global_position` (body centre). On very thin walls or at extreme angles the rays may miss. Ray length is 0.7 m; capsule radius is 0.4 m, leaving 0.3 m of detection margin beyond the surface.
- **Mantle step height** (`mantle_step_height = 0.9`) teleports the player upward in a single physics step. On very low-ceiling areas this could push the player into overhead geometry. Tune the export if level design changes.

---

## Future Considerations (Do Not Implement Yet)

- **Steam networking** — replace ENet peer with SteamMultiplayerPeer from GodotSteam. Keep all spawn/RPC logic identical.
- **Cloudflare Workers relay** — for online play without port forwarding. Would sit in front of ENet or require a WebSocket transport.
- **Game mode system** — a `GameMode` resource or autoload that listens to `GameEvents` and enforces rules (scoring, elimination, objectives). Design as optional — the framework works without one.
- **Throwable objects / projectiles** — will need their own `MultiplayerSpawner` or RPC-based instantiation. Plan for this when implementing the attack system.
- **Spectator camera** — for eliminated players. Post-death free-fly cam, constrained to world bounds.
- **Lobby / ready system** — pre-game lobby where players signal ready before the host starts the round.
- **Right-stick look (gamepad)** — `Input.get_axis("look_left", "look_right")` etc. in `_process`. Needs new input actions added to `project.godot`.
