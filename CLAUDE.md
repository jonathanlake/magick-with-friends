# CLAUDE.md — Magick With Friends

Architecture reference for AI-assisted development. Read this before touching any file.

This project began as a generic multiplayer "friend slop" framework and is now an actual
game. The networking spine carries over almost untouched; the movement, camera, and combat
identity are being (re)built. **Where this document describes a system the code does not
yet implement, it is clearly marked as roadmap (see "What Is NOT Done").**

A long design pass converged the direction (the rationale lives in the design transcript /
plan). The locked decisions are recorded below — treat them as settled unless told otherwise.

---

## Game Vision

**Magick With Friends** is a **3D, online co-op, first-person, horde-based** game built for
**close friend groups** (not public matchmaking). Tone is **"friend slop"** — chaotic fun,
friendly-fire laughs, happy accidents, jank-as-charm. It is explicitly **NOT** a
balance-tight, optimal-build competitive game.

- **Core loop:** 2–4 players fight escalating hordes together in first-person.
  **Friendly fire is ON and is a design pillar** — it's the comedy engine, not a footnote.
- **Combat — the BLEND spell system (decided).** You wield a wand/staff that casts spells
  built by *blending* a **Form** (delivery shape) with an **Element** (damage + reaction
  layer). **One cast = one fused effect.** This captures the *feel* of Noita's wands
  (combinatorial, emergent, things-go-wrong) but is deliberately **shallow** — it is **NOT**
  Noita's sequence/program model (no triggers, timers, multicast, or nesting).
- **Randomness is the keystone.** Forms/elements are dealt randomly (drops), so nobody can
  pre-build an optimal loadout. This keeps runs fresh, blocks an external "netdeck" meta,
  and flattens intra-group power gaps so one power-gamer friend can't pull ahead on builds.
- **Make-or-break constraint:** chaos must be **unpredictable going in, legible in
  hindsight.** "My fireball ricocheted into Dave" = good; "everyone took damage, nobody
  knows why" = bad. Readable telegraphs, distinct per-element VFX, and readable reactions
  are a **priority, not polish-later.**

**Influences:** the co-op horde lineage (**Left 4 Dead / Vermintide / Helldivers 2**) for
the format and the friendly-fire chaos; **Noita** for the wand-building *feel* (the blend,
not the per-pixel simulation).

### Open design decisions (DECIDE LATER — do not invent these)

- **Player movement controller.** The player currently ships a **first-person
  `RigidBody3D`** controller (legacy, with a climbing/parkour system that is being cut).
  Whether to keep `RigidBody3D` (physics-chaos — ragdolls, knockback, slips — actually
  *suits* the friend-slop tone) or migrate to `CharacterBody3D` (snappier, more standard)
  is **open**. The vertical slice keeps the existing controller. **Enemies** are
  `CharacterBody3D`.
- **Authority model.** The slice rides the existing model (per-player *input* authority,
  *host* simulation/spawn authority). Post-slice target to decide deliberately: **per-player
  authority over movement / character / own-HP** (crisp self-feel), but keep **host
  authority over enemies, waves, pickups, and spell hit-resolution + world reactions**
  (the interaction layer needs one resolver to stay consistent and *legible*).
- **Run / meta structure** beyond bare wave-survival (stages? mission arc? between-run
  progression?) — **open.** The slice is wave-survival only.
- **Ability resource.** Per-cast **cooldown** for now; a mana pool (repurpose
  `StaminaComponent`) is deferred.

> **Superseded:** earlier drafts of this doc committed to *third-person*, a *RoR2 roguelite*
> frame, and *deferred combat*. All three are now decided differently (first-person; co-op
> horde; blend combat). Ignore any third-person / RoR2-primary framing in older history.

---

## Git Workflow (Non-Negotiable)

- **New branch per task.** Always create `claude/[short-description]` before making any
  changes. Never commit directly to main.
- **Always fetch main first.** Before creating any branch, run
  `git fetch origin main && git reset --hard origin/main` to guarantee the branch starts
  from the actual current state of main. Skipping this causes merge conflicts on every PR.
- **Open a PR when done.** Every task ends with a pull request against main.
- **One feature per PR.** Keep PRs narrowly scoped and independently reviewable/playable.
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
  decision** (see above). **Physics-chaos — ragdolls, knockback, slips — is a *feature* of
  the friend-slop tone**, so `RigidBody3D` for the player is no longer ruled out.
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
- **Physics / simulation authority:** Host runs the simulation. Position (and eventually
  velocity) is synced from host to clients via `MultiplayerSynchronizer`.
- **Spawn authority:** Host's `MultiplayerSpawner` in `main.tscn` handles all spawning.
  Clients fire `peer_ready.rpc_id(1)` → host spawns their player via `spawn_function`.
- **RPCs:** Use `@rpc("any_peer", "call_remote", "reliable")` for client→host calls. Use
  `@rpc("authority", "call_local", "reliable")` for host→all broadcasts.

**This same host-authoritative model governs everything net-new** — enemies, the wave
spawner, projectiles/spell effects, world reactions, item/spell pickups, and run state all
run on the host and replicate outward. Clients send intent (input, interact/cast requests)
via the authority/RPC patterns above; the host owns the simulation. Cast *feel* on clients
is provided by **local cosmetic feedback only** (muzzle flash) — never client-authoritative
damage or reactions. (See the authority-model open decision for the post-slice target.)

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
settings (currently `max_players`, `round_timer`, `respawn_time`). It is not an autoload —
it's plain data. Expect it to grow run-level fields.

`GameManager` (`autoloads/game_manager.gd`) is an autoload `Node` that owns a `GameConfig`
instance (`GameManager.config`) and the local `player_name`. The host sets
`GameManager.config` values before starting the server. All game systems read from
`GameManager.config`. `GameManager` is the natural home for any future run/wave state.

### First-Person Camera (current)

The player ships a **first-person** rig (camera on the player body). Movement is
first-person and **casting aims forward** from the camera (where you look) — keep the aim
output simple (a forward raycast / muzzle spawn point), no ground-cursor in the slice.

The legacy controller also carries a climbing/parkour camera path that is **being cut**
(roadmap item 1). The player movement-controller decision (`RigidBody3D` vs
`CharacterBody3D`) is open but does not change the first-person camera.

### Spell System — BLEND (decided, the combat core)

A spell is a **fusion of two parts**, held in two swappable slots and fused **on cast**:

- **Form** — the delivery shape, and where the mechanical distinctness lives. Ceiling ~7
  (projectile, beam, cone, wall, bubble, AoE burst, trap orb). *Slice:* Projectile, AoE burst.
- **Element** — a thin **damage + reaction** layer on top, driven by a small **reaction
  table**. Sparse — not every element needs every form. *Slice:* Fire, Lightning.
- **Modifier** — *optional.* Event-multiplying / trajectory-scrambling modifiers (Split,
  Bounce, Homing) erode the per-cast legibility that is the whole reason we picked blend →
  **omitted in the slice**, constrained later.

**One cast = one fused effect.** This is NOT a sequence/program (no triggers/timers/
multicast/nesting — that's the Noita engine, deliberately rejected). Depth is **deliberately
shallow**; no deep stat-tuning knobs. Implemented as `@export`-driven Resources under
`systems/spells/` (`Spell` / `SpellForm` / `SpellElement`), cast by a `WandComponent` on the
player that holds the `(Form, Element)` pair and enforces a per-cast `cast_delay`.

**Reactions are the emergent chaos**, in two cheap layers (NOT a per-pixel sim):

- **Entity reactions** (status): e.g. Lightning **chains** to nearby units *including
  allies*; Fire applies a **burning DoT** that spreads to adjacent units.
- **World reactions:** a few hand-placed `Area3D` **reactive volumes** with a material tag
  (oil, water). Lightning in water electrifies everyone inside; fire ignites oil and spreads.
  This is the *signature* environmental chaos — done with trigger volumes, **not** a
  falling-sand simulation (that stays out of scope; see Future Considerations).

**Acquisition is random and keep-or-swap.** Forms/elements drop from enemies. Picking one up
is a **deliberate interact-to-swap** (proximity prompt → press interact) that **drops your
previous spell as a re-grabbable pickup** — a real "keep my Fire or take this Lightning?"
decision with a tradeoff, never a silent walk-over overwrite. Randomness keystone intact;
composition genuinely exercised.

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
  stamina_component.gd/.tscn   — Two-pool resource + `depleted` signal. PARKOUR IS CUT;
                                repurpose-or-remove — candidate mana pool (deferred).
  player_input_synchronizer_component.gd/.tscn
                              — Extends MultiplayerSynchronizer. Gathers input on the
                                authority peer, replicates it (mode 2). Synced fields being
                                re-pointed to action slots (move, jump, cast, interact).

entities/
  player/
    player.gd                 — LEGACY first-person RigidBody3D with climbing/parkour.
                                Slice: climbing disabled, LMB → cast. Controller model
                                (RigidBody3D vs CharacterBody3D) is an open decision.
    player.tscn               — FP body, InputSync, MultiplayerSynchronizer, HealthComponent,
                                mesh + capsule collider, NameLabel, camera, WandComponent.
  projectiles/                — (new) spell projectile/effect scenes, host-spawned.
  enemies/                    — (new) EnemyBase (CharacterBody3D + HealthComponent + host AI).
  pickups/                    — (new) Form/Element spell pickups (interact-to-swap).

systems/
  spells/                     — (new) Spell/SpellForm/SpellElement resources + WandComponent.
  reactions/                  — (new) reaction table + Area3D reactive world volumes.
  director/                   — (new) host-side wave spawner (timer + escalating count).

resources/
  game_config.gd              — Resource. max_players, round_timer, respawn_time. Not an autoload.

ui/
  main_menu/                  — Host/join flow. Validates name, parses IP:port (default 127.0.0.1:3000).
  hud/                        — DEV debug HUD (CanvasLayer). Slice adds a current-spell
                                (Form+Element) readout + a proximity swap prompt.

debug/
  debug.gd                    — Dev-only autostart helper. DEBUG autoload, DISABLED by default.

main.gd                       — MultiplayerSpawner setup, peer_ready RPC, spawn_function.
main.tscn                     — World root: MultiplayerSpawner + a level instance.
test_level.tscn               — Dev sandbox arena (CSG). Now a movement/combat sandbox.
project.godot                 — Autoloads, input map, Jolt, 1920×1080, D3D12. NOTE: config_name
                                still "Friend Slop Framework" — rename to "Magick With Friends".
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
- [x] `StaminaComponent` — two-pool resource + `depleted` signal (pending repurpose)
- [x] `GameEvents` autoload — event bus registered in `project.godot`
- [x] **`GameConfig` resource** + **`GameManager` autoload** — session settings + player name
- [x] **IP input field** + name validation in the main menu (falls back to `127.0.0.1:3000`)
- [x] Floating name labels over players; placeholder capsule meshes
- [x] **DEBUG autoload** — disabled-by-default two-window autostart (see below)
- [x] Two-player local multiplayer verified — host and client see each other move (first-person)

> The first-person movement currently runs through the **legacy `RigidBody3D` controller**
> (with a climbing/parkour system). That climbing/parkour is **being cut**; the first-person
> movement itself is **kept** for the slice (the slice tests spells, not locomotion).

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

## What Is NOT Done (the Vertical Slice, then beyond)

The immediate work is a **cheap vertical slice** — the smallest thing that lets 2–4 friends
play and answers "is the core fun?" Built on the existing co-op framework, **one feature per
PR**, legibility baked into each PR (not deferred). Everything is host-authoritative and
reuses the `MultiplayerSpawner` / RPC / `GameEvents` patterns.

1. **Player FP controller cleanup.** Disable climbing/parkour; repurpose `grab` (LMB) →
   `cast`. Keep the first-person movement. (RigidBody3D-vs-CharacterBody3D decided later.)
2. **Blend spell core + friendly fire + respawn.** `Spell`/`SpellForm`/`SpellElement`
   resources, `WandComponent` (Form+Element slots, `cast_delay`), Projectile + Fire,
   host-authoritative projectile spawn, FF damage on `HealthComponent` (default → 100),
   immediate local cosmetic cast feedback, current-spell HUD, cheap respawn.
3. **Enemies + wave spawner.** `EnemyBase` (CharacterBody3D, host AI: steer to nearest
   player + melee); `systems/director/` timer spawner with escalating waves.
4. **Blend matrix + reactions + world volumes.** AoE burst + Lightning; reaction table
   (lightning chain incl. allies, fire burn-spread); 1–2 `Area3D` reactive volumes (oil,
   water). Distinct per-element VFX as a done-criterion.
5. **Random keep-or-swap acquisition.** Enemy-dropped Form/Element pickups; `interact`
   action; interact-to-swap that drops the old spell as a re-grabbable pickup.
6. **Legibility tightening pass**, then the 30-minute friend playtest.

Beyond the slice (only if it proves fun):
- **GameEvents vocabulary** — replace `enemy_died` with `player_died`, `enemy_died(pos)`,
  `wave_started`, `run_ended`, `spell_picked_up`, etc.; let callers emit directly.
- **Authority-model decision** (per-player self / host shared) before building past the slice.
- **Run / meta structure** beyond wave-survival.
- **Production HUD** (health/shield, current spell, wave/timer).
- **Spawn point system** (4–8 points, by player index).
- **Client-side authority propagation** (`spawn_function` runs on host only — clients never
  call `set_multiplayer_authority`; fine for same-machine, needs fixing for real MP).
- **Velocity sync** for smoother client interpolation.
- **More Forms/Elements**, modifiers (constrained), mana resource, downed/revive.
- **Project cleanup:** rename `application/config_name` to "Magick With Friends".

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

- **Player controller is legacy.** `player.gd` is still the first-person `RigidBody3D`
  parkour controller. The slice disables climbing and repoints LMB → cast; treat the
  movement/climbing code as scheduled for cleanup, not a pattern to extend.
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
- `project.godot` still names the app "Friend Slop Framework" (rename pending).

---

## Future Considerations (Do Not Implement Yet)

- **Noita-style material simulation.** The blend reaction layer uses cheap `Area3D` volumes,
  NOT a per-pixel falling-sand sim. Full simulation (fire spreading per-pixel, liquids,
  electrified water at sim fidelity) is expensive and hard to net-replicate in 3D — stay with
  tagged volumes / area triggers until there's a reason not to.
- **Authority model** — formalize per-player-self / host-shared split (see open decisions).
- **Mana resource** — repurpose `StaminaComponent` if cooldowns prove too shallow.
- **Run / meta structure** — stages, between-run progression, objectives.
- **Steam networking** — replace the ENet peer with `SteamMultiplayerPeer`; keep all
  spawn/RPC logic identical (the point of `NetworkManager`).
- **Cloudflare Workers / WebSocket relay** — online play without port forwarding.
- **Lobby / ready system**, **spectator camera** for dead players, **gamepad** bindings +
  right-stick look.
```
