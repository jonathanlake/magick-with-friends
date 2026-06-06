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

**Build this game.** A reusable-spine / swappable-mini-game-sandbox future is parked in `DESIGN.md`,
but it earns **no architectural weight until a second game needs it** — "keeps the spine reusable" is
not a tiebreaker yet. (The `NetworkManager` transport seam, the component pattern, and the `GameEvents`
event bus are good practice on their own merit, not because of the sandbox — keep them regardless.)

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

- **Mode 1** (`REPLICATION_MODE_ALWAYS`) — syncs every physics frame. Used for `global_position`
  and the **animation drivers**: player `aim_yaw` + `anim_speed`, enemy `face_yaw` + `anim_speed`
  (the owning peer authors them; every peer animates/faces from the replicated value — see Animation).
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

### Animation (LocomotionAnimator + AnimationTree)

Players and enemies use KayKit models (gitignored `/assets/`) animated through one reusable
`components/locomotion_animator.gd` on each **visual scene root** (`player_visual.tscn` /
`enemy_visual.tscn`):

- **Tree shape.** The animator reads an `AnimationTree`. Player: a bare **BlendSpace1D** (Idle↔Run by
  speed). Enemy: a **BlendTree** = the same BlendSpace1D "Loco" feeding an **AnimationNodeOneShot**
  whose shot is the attack clip — `blend_param` / `oneshot_request_param` exports point at the right
  nested params (`parameters/Loco/blend_position`, `parameters/OneShot/request`).
- **Replicate the DRIVER, never the animation.** The idiomatic Godot multiplayer rule (and the cause
  of a real jitter bug we fixed): **don't differentiate a replicated `global_position`** to get speed
  — a remote body's position arrives in held network snapshots, so differentiating it sawtooths the
  blend (run↔idle, worst at a weapon tip on a long lever). Instead the **owning peer authors its real
  speed** and the animator blends from that. The owner writes `anim_speed` (planar velocity) — and a
  facing yaw (`aim_yaw` player / `face_yaw` enemy) — these **replicate (mode 1)**, and every peer
  `feed_speed()`s the animator + rotates the visual from the steady value. Sample on the **physics
  clock** (not `_process`), the same clock the body moves on.
- **One-shots** (enemy attack) fan out cosmetically: the host calls `play_attack_anim.rpc()`
  (`authority, call_local` — the host owns the enemy) → every peer `fire_oneshot()`s.
- **Looping** on Idle/Run is set in the glb **import dock** (author action, not code); the attack clip
  stays **non-looping** so the OneShot ends and returns to locomotion.

### Spell System — BLEND (the combat core)

A spell fuses two swappable slots **on cast** → **one fused effect** (NOT a sequence/program;
see `DESIGN.md` for the blend rationale and the legibility north star):

- **Form** — delivery shape, where the mechanical distinctness lives (the ~7-Form ceiling + the
  candidate list is a *decision* — see `DESIGN.md`). *Slice:* Projectile, AoE burst.
- **Element** — thin damage + reaction layer, via a small reaction table. *Slice:* Fire, Lightning.
- **Modifier** — optional; Split / Bounce / Homing **omitted in the slice** (they erode the
  per-cast legibility blend exists to protect).

Implemented as `@export`-driven Resources under `systems/spells/` (`Spell` / `SpellForm` /
`SpellElement` / `BlendSpell`), cast by a `WandComponent` on the player holding the
`(Form, Element)` pair and enforcing `cast_delay_sec`. `Spell` exposes a `cast_on_host()` seam so
an authored `CascadeSpell` (a deferred cascade experiment — cut from the slice, see `DESIGN.md`)
could slot in without reworking the wand.

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
                                Has `enemy_died`, `enemy_count_changed(count)` + `alive_enemy_count`
                                (register_enemy/unregister_enemy), and `local_player_damaged` (FP
                                hit cue, via `emit_local_player_damaged()`). Fuller vocabulary is a
                                DESIGN.md roadmap item.
  game_manager.gd             — Autoload Node. Owns GameConfig + local player_name.
  spell_catalog.gd            — Autoload. Index-stable Form/Element arrays + `make_blend(f,e)` so
                                every peer builds the SAME spell from replicated indices. BUILT.
  network_manager.gd          — Transport abstraction. ONLY file that touches ENet/Steam/relay.

components/
  health_component.gd/.tscn   — max_health (export, default 100), current_health, damage(int),
                                died + damaged signals. Reused by players and enemies.
  hit_flash_component.gd/.tscn — Reusable damage flash. @export target_mesh_path / flash_color /
                                flash_duration_sec / health_component_path. Auto-wires to a
                                HealthComponent's `damaged`; host fans the cosmetic flash to all
                                peers via an `any_peer` RPC (deliberate — see RPC Pattern exception:
                                player nodes are client-owned). Used by players + enemies.
  stamina_component.gd/.tscn   — Two-pool resource + `depleted` signal. OFF the player; files
                                kept, unused — reserved for a future mana pool.
  player_input_synchronizer_component.gd/.tscn
                              — Extends MultiplayerSynchronizer. Gathers input on the authority
                                peer, replicates it (mode 2). Syncs `movement_vector` (WASD) +
                                `is_jump_pressed`. Cast is RPC-driven; interact is roadmap.
  locomotion_animator.gd      — Reusable script on a visual scene root. Drives a locomotion
                                BlendSpace1D (idle↔run) from a fed speed, and fires a OneShot
                                (`fire_oneshot`) for a layered action. See Animation below. BUILT.

entities/
  player/
    player.gd                 — First-person CharacterBody3D controller: run / jump / look / cast /
                                death-state (velocity + move_and_slide + is_on_floor). Authors
                                replicated `aim_yaw` + `anim_speed` and feeds the Visual's animator
                                each frame. Climbing/parkour removed.
    player.tscn               — FP body, InputSync, MultiplayerSynchronizer, HealthComponent,
                                HitFlashComponent, a `Visual` instance of player_visual.tscn,
                                capsule collider, NameLabel, camera. (WandComponent is added in code.)
    player_visual.tscn        — The visible rig: KayKit Mage (.glb) + an AnimationTree (idle↔run
                                BlendSpace1D) + LocomotionAnimator. Editable art/anim scene. BUILT.
  projectiles/                — projectile.gd/.tscn: host-spawned + host-resolved spell
                                projectile (Area3D). BUILT.
  enemies/                    — enemy_base.gd/.tscn: EnemyBase (CharacterBody3D + HealthComponent +
                                HitFlashComponent; host AI: gravity / steer / cooldown'd melee;
                                authors replicated `anim_speed` + `face_yaw`; attack-swing RPC).
                                enemy_visual.tscn: KayKit Skeleton (.glb) + AnimationTree
                                (BlendTree: idle↔run + a OneShot attack) + LocomotionAnimator. BUILT.
  pickups/                    — (roadmap) Form/Element spell pickups (interact-to-swap).

systems/
  spells/                     — Spell/SpellForm/SpellElement/BlendSpell resources +
                                WandComponent. BUILT.
  reactions/                  — reactions.gd: host-central resolver (Node under Main). Direct
                                damage + entity reactions (lightning chain incl. allies, fire
                                burn/DoT); cosmetic broadcasts. BUILT (entity reactions; Area3D
                                world volumes still roadmap).
  director/                   — wave_director.gd: host-side escalating ring spawner (timer + waves,
                                alive cap). Boots PAUSED (`auto_start = false`) — the host begins
                                the round via the console `start` (set_spawning). BUILT.

resources/
  game_config.gd              — Resource. max_players, respawn_time. Not an autoload.

ui/
  main_menu/                  — Host/join flow. Validates name, parses IP:port (default 127.0.0.1:3000).
  hud/                        — DEV debug HUD (CanvasLayer): spell + HP + enemy/player counts + FPS
                                readout, crosshair, death fade, host-left + self-damage overlays.
                                (Proximity swap prompt is roadmap.)
  console/                    — dev_console.gd: dev console (backtick). Mounted on EVERY peer in
                                main.gd, gated by role: HOST gets the full set (help / start /
                                give [all] / players / wave / enemies [off|on|clear] / clear); a
                                CLIENT gets only help / clear (host-only cmds print "host only"),
                                with a seam (`_HOST_ONLY`) for future client-side commands. BUILT.

debug/
  debug.gd                    — Dev-only helper. DEBUG autoload, DISABLED by default. Two-window
                                autostart (`-- host/join debug_autostart`) + `-- smoke` driver.

tools/
  smoke-test.sh               — Headless gameplay smoke test (see Headless Validation).

main.gd                       — Spawner setup (player/projectile/enemy), peer_ready RPC,
                                spawn_functions, host damage/death/respawn RPCs + self-damage cue,
                                HUD + host-only console mount, host-disconnect handling.
main.tscn                     — World root: player/projectile/enemy MultiplayerSpawners,
                                Projectiles/Enemies containers, WaveDirector, + a level.
test_level.tscn               — Walled horde arena (CSG floor + 4 perimeter walls). Combat sandbox.
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
- [x] `HealthComponent` / `GameConfig` / `GameManager` / `GameEvents` autoloads + components
- [x] **IP input field** + name validation in the main menu (falls back to `127.0.0.1:3000`)
- [x] Floating name labels over players; KayKit Mage/Skeleton models with idle/run + attack animation
      (placeholder capsules retired)
- [x] **DEBUG autoload** — disabled-by-default two-window autostart (see below)
- [x] Two-player local multiplayer verified — host + client see each other move (first-person)
- [x] **Blend casting + friendly fire + death/respawn** — built and validated two-window

> **Online status:** only **same-machine two-window** is verified on this codebase. Per-peer
> authority *does* propagate correctly (repro in Known Issues); the open gap is **cross-machine
> transport** (NAT / relay / latency), not an authority fix. Full story + the re-test plan: the
> **slice playtest** (`DESIGN.md` roadmap item 7 — the real-online re-verify now lives there, canonical).

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
    Player/HealthComponent hits + lifetime, so walls don't stop it (add `world` to the mask + handle
    it if wall-despawn is ever wanted).
- **`input_multiplayer_authority` propagation (verified OK — not a bug).** Earlier notes calling
  this "host-only / broken cross-machine" were a misdiagnosis; it propagates correctly. **Repro:**
  enable the DEBUG autoload + run two-window — the `[AUTH]` line in `player.gd` prints each copy's
  authority from every peer's view (a client sees the host's player as `authority=1 is_mine=false`,
  its own as `is_mine=true`). *Why it works* and the still-untested cross-machine transport piece:
  the slice playtest (`DESIGN.md` roadmap item 7, canonical — don't restate it here).
- `main_menu.gd` defaults to `127.0.0.1` and port `3000` (keep the port an `int` — ENet requires it).
- `multiplayer.connected_to_server` is only wired for the client path; the host transitions
  immediately — correct, don't add host-side handling.
- `class_name Player` must stay — `main.gd`'s `spawn_function` casts to `Player`.
