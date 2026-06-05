# CLAUDE.md — Magick With Friends

Architecture reference for AI-assisted development. Read this before touching any file.

**Game vision, design decisions, build roadmap, and status live in `DESIGN.md`.** DESIGN is
**decision-led** (what/why); this file is **structure-led** (how the code is organized + the
dev workflow): rules, file map, the non-obvious Godot gotchas. Expect some overlap — when a fact
is in both, the *decision* lives in `DESIGN.md` and the *implementation detail* lives here.

In one line: a **3D online co-op, first-person, horde** game; combat is the **BLEND spell
system** (Form × Element → one fused cast). It began as a generic multiplayer "friend slop"
framework; the networking spine carries over, movement/camera/combat are being (re)built.
Where this doc describes a system the code doesn't implement yet, it's marked roadmap.

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

---

## Rules (Non-Negotiable)

- **GDScript only.** No C#. Ever.
- **3D only.** No 2D. Jolt physics, `CharacterBody3D`/`RigidBody3D`/`StaticBody3D` nodes.
- **Jolt physics engine.** Set in `project.godot`. Do not switch to default Godot physics.
- **No C# toolchain.** No `.csproj`, no `dotnet`, no NuGet.
- **Do not modify UIDs** in `.tscn` or `.gd.uid` files manually (the editor generates them).
- **@export everything tunable.** Any value a non-coder might want to change must be `@export`.
- **Enemies are `CharacterBody3D`** (kinematic, `move_and_slide`-driven). **Physics-chaos —
  ragdolls, knockback, slips — is the embraced tone**, so `RigidBody3D` is fine for players and
  props. (The player's controller — `RigidBody3D` today — is a *current default, open to change*,
  not a fixed rule; see `DESIGN.md`.)
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
transport is in use. The rest of the codebase calls `host_game()` / `join_game(ip)` /
`disconnect_game()` and listens to its signals (`connection_succeeded`, `connection_failed`,
`server_disconnected`, `peer_connected(id)`, `peer_disconnected(id)`).

**To swap ENet for Steam/relay:** replace the two lines inside `host_game()` and `join_game()`
that create the peer. Nothing else changes — the `multiplayer.*` signal layer above the
transport is identical across backends. The file opens with a formal transport contract
comment; read it before adding any connection code.

### Multiplayer Model

ENet host/client. One player is the server (host, peer ID `1`); others are clients. This is the
**implementation home for the authority model decided in `DESIGN.md`** — other sections defer
here for the *how*.

- **Input authority:** Each player is `multiplayer_authority` over their own `Player` node and
  `PlayerInputSynchronizerComponent`. Input is gathered locally only on the authority peer,
  then synced to all.
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

- **Mode 1** (`REPLICATION_MODE_ALWAYS`) — syncs every physics frame. Used for `global_position`.
- **Mode 2** (`REPLICATION_MODE_ON_CHANGE`) — syncs only when value changes. Used for the
  synced input fields in `PlayerInputSynchronizerComponent`.

*If* you add velocity sync (a Beyond-the-slice item in `DESIGN.md`), use mode 1 alongside
`global_position` for smoother client interpolation.

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

`GameConfig` (`resources/game_config.gd`) is a `Resource` holding session-level settings
(`max_players`, `respawn_time`). It is not an autoload — plain data; expect run-level fields.

`GameManager` (`autoloads/game_manager.gd`) is an autoload `Node` owning a `GameConfig`
(`GameManager.config`) + the local `player_name`. The host sets config before starting the
server; all systems read from `GameManager.config`. Natural home for future run/wave state.

### First-Person Camera (current)

The player ships a **first-person** rig (camera on the player body). **Casting aims forward**
from the camera (a forward raycast / muzzle spawn point) — no ground-cursor in the slice. The
climbing/parkour camera path has been **removed**. Cast *feel* on clients is immediate local
cosmetic feedback (muzzle flash), decoupled from host-authoritative resolution.

### Spell System — BLEND (the combat core)

A spell fuses two swappable slots **on cast** → **one fused effect** (NOT a sequence/program;
see `DESIGN.md` for the blend rationale and the legibility north star):

- **Form** — delivery shape, where the mechanical distinctness lives (~7 ceiling: projectile,
  beam, cone, wall, bubble, AoE burst, trap orb). *Slice:* Projectile, AoE burst.
- **Element** — thin damage + reaction layer, via a small reaction table. *Slice:* Fire, Lightning.
- **Modifier** — optional; Split / Bounce / Homing **omitted in the slice** (they erode the
  per-cast legibility blend exists to protect).

Implemented as `@export`-driven Resources under `systems/spells/` (`Spell` / `SpellForm` /
`SpellElement` / `BlendSpell`), cast by a `WandComponent` on the player holding the
`(Form, Element)` pair and enforcing `cast_delay_sec`. `Spell` exposes a `cast_on_host()` seam so
an authored `CascadeSpell` (the roadmap A/B) slots in without reworking the wand.

**Host-authoritative** (see Multiplayer Model): casts originate on the authority peer; the host
spawns + resolves them (damage incl. friendly fire, reactions) and replicates out. **Reactions**
are two cheap layers (NOT a pixel sim): entity status (lightning chains to nearby units incl.
allies; fire burns + spreads) and a few hand-placed `Area3D` world volumes (oil, water).
**Acquisition** is random keep-or-swap (interact-to-swap; drops your old spell as a re-grabbable
pickup). Design rationale for all of this lives in `DESIGN.md`.

---

## File Map

```
autoloads/
  game_events.gd              — Global signal bus. Add signals here, not in random scripts.
                                Currently only a leftover `enemy_died` — see DESIGN.md roadmap.
  game_manager.gd             — Autoload Node. Owns GameConfig + local player_name.
  network_manager.gd          — Transport abstraction. ONLY file that touches ENet/Steam/relay.

components/
  health_component.gd/.tscn   — max_health (export, default 100), current_health, damage(int),
                                died signal. Reused by players and enemies.
  stamina_component.gd/.tscn   — Two-pool resource + `depleted` signal. OFF the player; files
                                kept, unused — reserved for a future mana pool.
  player_input_synchronizer_component.gd/.tscn
                              — Extends MultiplayerSynchronizer. Gathers input on the authority
                                peer, replicates it (mode 2). Syncs `movement_vector` (WASD) +
                                `is_jump_pressed`. Cast is RPC-driven; interact is roadmap.

entities/
  player/
    player.gd                 — First-person RigidBody3D controller: run / jump / look /
                                cast / death-state. Climbing/parkour removed.
    player.tscn               — FP body, InputSync, MultiplayerSynchronizer, HealthComponent,
                                mesh + capsule collider, NameLabel, GroundCheck, camera.
                                (WandComponent is added in code, not in the scene.)
  projectiles/                — projectile.gd/.tscn: host-spawned + host-resolved spell
                                projectile (Area3D). BUILT.
  enemies/                    — (roadmap) EnemyBase (CharacterBody3D + Health + AI).
  pickups/                    — (roadmap) Form/Element spell pickups (interact-to-swap).

systems/
  spells/                     — Spell/SpellForm/SpellElement/BlendSpell resources +
                                WandComponent. BUILT.
  reactions/                  — (roadmap) reaction table + Area3D reactive volumes.
  director/                   — (roadmap) host-side wave spawner (timer + waves).

resources/
  game_config.gd              — Resource. max_players, respawn_time. Not an autoload.

ui/
  main_menu/                  — Host/join flow. Validates name, parses IP:port (default 127.0.0.1:3000).
  hud/                        — DEV debug HUD (CanvasLayer): current-spell + HP readout,
                                crosshair, death fade overlay. (Proximity swap prompt is roadmap.)

debug/
  debug.gd                    — Dev-only helper. DEBUG autoload, DISABLED by default. Two-window
                                autostart (`-- host/join debug_autostart`) + `-- smoke` driver.

tools/
  smoke-test.sh               — Headless gameplay smoke test (see Headless Validation).

main.gd                       — MultiplayerSpawner setup, peer_ready RPC, spawn_function, damage/
                                death/respawn RPCs, projectile spawner.
main.tscn                     — World root: player + projectile MultiplayerSpawners + a level.
test_level.tscn               — Dev sandbox arena (CSG). Movement/combat sandbox.
project.godot                 — Autoloads, input map (move_*, cast, jump), Jolt, 1920×1080,
                                D3D12. config_name = "Magick With Friends".
```

(For built-vs-roadmap status, the `BUILT` / `(roadmap)` tags above + the `DESIGN.md` roadmap
are the source of truth.)

---

## What Carries Over From the Framework

The reusable spine that is real and working today:

- [x] Project scaffolding — Jolt, Forward Plus, 1920×1080, D3D12 on Windows
- [x] **`NetworkManager` autoload** — swappable transport layer; ENet today, Steam/relay ready
- [x] **Multiplayer connection flow** — host spawns self; clients send `peer_ready` RPC;
      max_players gate; despawn on disconnect; `MultiplayerSpawner` `spawn_function`
- [x] `PlayerInputSynchronizerComponent` (mode 2 input) + player `MultiplayerSynchronizer`
      (`global_position`, mode 1, spawn=true)
- [x] `HealthComponent` / `GameConfig` / `GameManager` / `GameEvents` (stub) autoloads + components
- [x] **IP input field** + name validation in the main menu (falls back to `127.0.0.1:3000`)
- [x] Floating name labels over players; placeholder capsule meshes
- [x] **DEBUG autoload** — disabled-by-default two-window autostart (see below)
- [x] Two-player local multiplayer verified — host + client see each other move (first-person)
- [x] **Blend casting + friendly fire + death/respawn** — built and validated two-window

> **Online status:** the *vision* is online co-op, and real cross-machine play worked on the
> **predecessor** framework (external relay / port-forwarding). On **this** codebase only
> **same-machine two-window** is verified — real online needs the client-authority-propagation
> fix (see Known Issues) + a cross-machine re-test (see the `DESIGN.md` roadmap milestone).

---

## DEBUG Autoload — Dev Workflow

`debug/debug.gd` is registered as the `DEBUG` autoload in `project.godot` **without** the `*`
prefix, so it is **disabled by default**. It never runs in normal play or exported builds.

### Enabling for local two-window testing

1. **Enable the autoload** — Project Settings → Autoload → check `DEBUG` (or add `*` before
   `res://debug/debug.gd` in `project.godot`).
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
| `project.godot` DEBUG line | `DEBUG="*res://debug/debug.gd"` | `DEBUG="res://debug/debug.gd"` |
| Run Instances Launch Arguments | `-- host/join debug_autostart` | **cleared** |

**Important:** Godot passes Launch Arguments even when "Override Main Run Args" is unchecked.
**Clear the Launch Arguments**, not just the autoload. Both steps are required.

**Rule:** Never commit `project.godot` with `DEBUG="*res://debug/debug.gd"`. The `*` is dev-local only.

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
- Player input is **never** sent via RPC — use `MultiplayerSynchronizer`.

### Scene Instancing
Use `preload("uid://...")` for scenes/scripts referenced in code. Never use string paths like
`"res://entities/player/player.tscn"` — UIDs survive file moves. (New hand-authored scenes may
reference by path until the editor assigns a uid on save.)

### Physics (Jolt)
- **Enemies** are `CharacterBody3D` — `move_and_slide()` after setting `velocity`; gravity via
  `get_gravity()`; `is_on_floor()` for grounded. Knockback = add to `velocity`.
- **Player** is `RigidBody3D` (first-person); knockback there is an impulse.
- **Physics-chaos is a feature** of the friend-slop tone — keep gameplay-critical physics on a
  single owner; let purely-cosmetic chaos be loose. `RigidBody3D` is fine for physics props.
- Jolt is the engine (`project.godot`); test with Jolt enabled — its collision response differs.

### Camera Rig Pattern (First-Person)
The camera lives on the player body; casting aims forward from it (forward raycast / muzzle
spawn). No ground-cursor in the slice. Cast *feel* on clients is immediate local cosmetic
feedback (muzzle flash), decoupled from host-authoritative resolution.

### Engine Behavior — Check Current Docs First
For engine/library/API behavior, check the **version-current Godot docs** (or community consensus)
**before** inventing a workaround. Godot's behavior shifts across minor versions, so stale intuition
is a real trap. **Treat a failed "this should be trivial" fix as the trigger to research — not to
add more complexity.** (Concrete example: the dev-console input "losing focus" after Enter wasn't a
focus bug at all — Godot 4.4 added `LineEdit.keep_editing_on_text_submit` defaulting to `false`;
two hand-rolled `grab_focus` workarounds failed before a doc check found the one-property fix.)

---

## Known Issues / Watch Out For

- **Player controller is `RigidBody3D` (first-person).** Don't assume RigidBody3D vs
  CharacterBody3D when writing player-agnostic code — the choice is an open decision (`DESIGN.md`).
- **Cast feel is host-asymmetric.** The host feels instant casts; clients eat a round-trip. The
  local cosmetic muzzle flash masks it; read playtests knowing host feel ≠ client feel (rotate hosts).
- **Spawn height vs capsule:** keep spawn markers at `y≈1.0`+ so the capsule doesn't clip the floor.
- **Collision layers are all on layer 1 (tech debt — TODO).** Players, enemies, projectiles, and
  world geometry share the default layer 1 / mask 1. The projectile→body hit detection relies on
  this shared layer, and it's the lowest-risk default for the slice. Side effect: enemies
  physically shove each other and players. **Cleanup item:** define named layers
  (world / players / enemies / projectiles) in `project.godot` and set each body's layer/mask
  explicitly (remember to widen the projectile Area3D mask to include the enemy layer).
- **`input_multiplayer_authority` propagation (verified OK — not a bug):** the custom
  `MultiplayerSpawner` `spawn_function` runs on **all peers** (Godot docs: *"called on all peers"*),
  so each client re-runs it with the replicated `data` and sets
  `set_multiplayer_authority(data.peer_id)` on its copies via `_enter_tree`. Observable: enable the
  DEBUG autoload + run two-window — the `[AUTH]` line in `player.gd` prints each copy's authority
  from every peer's view (a client sees the host's player as `authority=1 is_mine=false`, its own as
  `is_mine=true`). Earlier notes calling this "host-only / broken cross-machine" were a misdiagnosis.
  The genuinely untested piece is **cross-machine transport** (NAT / port-forward / relay) + latency,
  not authority — see the `DESIGN.md` roadmap milestone.
- `main_menu.gd` defaults to `127.0.0.1` and port `3000` (keep the port an `int` — ENet requires it).
- `multiplayer.connected_to_server` is only wired for the client path; the host transitions
  immediately — correct, don't add host-side handling.
- `class_name Player` must stay — `main.gd`'s `spawn_function` casts to `Player`.
