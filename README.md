# Friend Slop Framework

A reusable Godot 4.6 foundation for making co-op "friendslop" games — physics-driven, low barrier to entry, designed for groups of 2–4 friends to jump into online or on a LAN.

Inspired by games like PEAK: the default hook is a shared objective (climbing, surviving, reaching a goal together) with emergent chaos from physics interactions. Sumo, last-one-standing, and race modes are all easy to layer on top.

---

## Design Philosophy

- **Physics-first.** Characters are `RigidBody3D` nodes driven by Jolt physics. The chaos is a feature.
- **Component-based.** Behavior lives in small, reusable component nodes attached to entities. Mix and match.
- **Designer-friendly.** Every tunable value is an `@export` variable. Non-coders can tweak the game without reading code.
- **Multiplayer from day one.** The framework assumes up to 4 players (expandable to 8) connected via ENet, direct IP. Input is gathered locally and synced; physics authority lives on the host.
- **GDScript only.** No C#. Keeps the codebase accessible and the toolchain simple.
- **3D locked in.** Jolt physics in 3D is where friendslop shines.

---

## Folder Structure

```
friend-slop-framework/
├── autoloads/
│   └── game_events.gd          # Global event bus (signals: player_died, round_started, round_ended, ...)
├── components/
│   ├── health_component.gd/.tscn       # Tracks HP, emits died signal
│   └── player_input_synchronizer_component.gd/.tscn  # Gathers & syncs local input to all peers
├── entities/
│   └── player/
│       ├── player.gd           # RigidBody3D — movement, look, physics response
│       └── player.tscn         # Player scene: input sync, position sync, health, mesh, collision
├── ui/
│   └── main_menu/
│       ├── main_menu.gd        # Host/Join logic, IP input field, ENet peer setup
│       └── main_menu.tscn      # Simple Host / Join UI
├── main.gd                     # Root scene: MultiplayerSpawner, spawn logic, peer_ready RPC
├── main.tscn                   # World: sky, light, ground plane, spawner, spawn marker
└── project.godot               # Autoloads, input map, Jolt physics, 1920×1080
```

---

## Key Systems

### Multiplayer (ENet, Direct IP)

The framework uses `ENetMultiplayerPeer` for peer-to-peer style networking where one player acts as host/server. Clients connect via a typed IP address on port `3000`.

**Flow:**
1. `MainMenu` — player either hosts (creates server peer) or joins (enters IP, creates client peer).
2. On connection, `main.tscn` loads and `peer_ready` RPC fires from each client to the host.
3. The host's `MultiplayerSpawner` calls its `spawn_function`, which instantiates a `Player` scene, names it by peer ID, assigns multiplayer authority, and positions it at the spawn marker.

**Player count:** Default max is 4. To raise it, adjust your lobby logic and add spawn points — the spawner has no hard limit.

### Player Entity (`entities/player/`)

`Player` extends `RigidBody3D` (Jolt physics). It owns:

- A **first-person Camera3D** at head height, driven by mouse/right-stick look.
- WASD / left-stick movement applied as physics forces/impulses.
- A `MultiplayerSynchronizer` that replicates `global_position` (and eventually `linear_velocity`, `angular_velocity`) to all peers.
- A `PlayerInputSynchronizerComponent` that gathers input locally (authority peer only) and syncs it to everyone else.
- A `HealthComponent` for HP tracking.

The player script is the right place to implement jump, and to read `is_attacked_pressed` for game-specific actions.

### Input Synchronization (`components/player_input_synchronizer_component`)

`PlayerInputSynchronizerComponent` extends `MultiplayerSynchronizer`. Each frame, the peer who owns the player gathers:
- `movement_vector: Vector2` — from `move_left/right/up/down` actions
- `is_attacked_pressed: bool` — from the `attack` action

These are replicated (mode 2, always) to all peers so any node can read them without extra RPCs. The player script reads these variables and applies physics on the authoritative peer.

### Health Component (`components/health_component`)

A plain `Node` component that tracks `current_health` against `@export var max_health`. Call `damage(amount)` to reduce HP; listen to the `died` signal to respond (respawn, eliminate, etc.).

Default `max_health` is `100`. Change per-entity by setting the export in the scene.

### Game Events (`autoloads/game_events.gd`)

A global event bus autoloaded as `GameEvents`. Emit and listen to game-wide signals from anywhere without direct node references.

Current signals:
- `player_died` — emit when a player's HealthComponent fires `died`
- `round_started` — emit when a new round begins
- `round_ended` — emit when win/lose condition is met

Add more signals here as your game needs them. Keep them generic — they're hooks for game-mode logic to attach to.

### Input Map

| Action | Keyboard | Gamepad |
|---|---|---|
| `move_left` | A / Left Arrow | Left stick left |
| `move_right` | D / Right Arrow | Left stick right |
| `move_up` | W / Up Arrow | Left stick up |
| `move_down` | S / Down Arrow | Left stick down |
| `attack` | Left Mouse Button | (to be mapped) |

Deadzone: `0.2` on all actions.

---

## Starting a New Game from This Framework

1. **Duplicate the project** (or use it as a Git submodule / template).
2. **Define your objective** — connect it to `GameEvents.round_started` / `round_ended`.
3. **Build your world** — replace or extend `main.tscn`. Add terrain, obstacles, hazards.
4. **Tune player feel** — adjust `@export` variables on the `Player` node (speed, jump height, mass) and `HealthComponent` (max_health, respawn_time).
5. **Add game-mode logic** — create a new autoload or scene script that listens to `GameEvents` and enforces your rules (scoring, elimination, timers).
6. **Layer on components** — add component scenes to the player or world for your mechanic (throwable objects, grapple hooks, stamina, etc.).

### Key Exported Variables (tune without touching code)

**Player node** — per-character feel:

| Variable | Default | Effect |
|---|---|---|
| `move_force` | 40.0 | Force applied toward input direction each physics tick |
| `max_speed` | 8.0 | Horizontal speed cap (m/s) |
| `ground_friction` | 8.0 | Horizontal deceleration rate when no input |
| `camera_height` | 0.7 | Camera Y offset above body centre |
| `camera_smoothing` | 15.0 | Camera position lerp speed (higher = snappier) |
| `mouse_sensitivity` | 0.003 | Mouse look sensitivity |

**GameConfig** (set on `GameManager.config` before the host starts) — session settings:

| Variable | Default | Effect |
|---|---|---|
| `max_players` | 4 | Lobby cap |
| `round_timer` | 180.0 | Round length in seconds |
| `respawn_time` | 3.0 | Seconds before a dead player respawns |

**HealthComponent** — per-entity health:

| Variable | Default | Effect |
|---|---|---|
| `max_health` | 100 | HP pool |

---

## Technical Notes

- **Physics engine:** Jolt Physics (set in `project.godot`). Do not switch to the default Godot physics — Jolt behavior is assumed throughout.
- **Renderer:** Forward Plus, 1920×1080 viewport.
- **Networking port:** `3000` (hardcoded in `main_menu.gd`). Change it in one place.
- **Multiplayer authority:** The host is always peer ID `1`. Players own their own `Player` node and `PlayerInputSynchronizerComponent`. The host runs physics simulation.
- **Scene UIDs:** Godot 4.6 uses `uid://` references everywhere. Do not manually edit UIDs.
