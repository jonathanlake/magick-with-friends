# DEV.md — Dev Workflow, Validation & Gotchas

**Charter:** this doc is **workflow-led** — the day-to-day mechanics of working on this repo:
the two-window DEBUG setup, the pre-PR headless validation gate, and the hard-won Known Issues
list. It was split out of `CLAUDE.md` so sessions load it on demand rather than every time.
**Open it before** running the project locally, validating a PR, or touching player movement,
replication/smoothing, damage flow, collision layers, or `@export` node wiring (the gotchas
name those systems for a reason).

- **Rules, architecture, file map** → `CLAUDE.md` (always read first).
- **Decisions / roadmap** → `DESIGN.md`.
- **System traces** → `docs/NETWORKING.md` (multiplayer) / `games/magick/SPELLS.md` (blend system).

---

## DEBUG Autoload — Two-Window Dev Workflow

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
parse/scene errors**. `.godot/` is gitignored, so runs don't dirty the tree.

**One command runs the whole gate** (Git Bash; also exposed as the `/validate` skill):

```
bash tools/validate.sh
```

It prints `VALIDATE: PASS` / `FAIL` (exit 0/1). Under the hood it runs **three** checks —
no single one is complete (verified empirically):

1. **Parse-check each changed `.gd`** — catches syntax errors in **any** script, incl. brand-new
   files (which check 2 misses):
   ```
   "<godot>" --headless --path "<project>" --check-only --script "res://path/to/changed.gd"
   ```
   **Fail only on `Parse Error` lines.** `--check-only` doesn't load autoloads, so it *falsely*
   reports `Identifier not found: GameManager / NetworkManager / …` for any script using an
   autoload — **ignore those** (`validate.sh` already filters them out).
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

## Known Issues / Watch Out For

- **Player controller is `CharacterBody3D` (first-person).** Switched from RigidBody3D — crisper feel,
  and the airborne wall-stick is gone (move_and_slide slides along walls). Movement is velocity-model
  in `player.gd._physics_process` (gravity + jump on Y, `move_toward` accel/decel on the horizontal).
  Emergent rigid-body shoving is gone by design — knockback/ragdoll are now scripted (a follow-up).
- **Remote bodies snap; their *Visual* is what's smoothed.** A remote player's `global_position`
  replicates with no interpolation (Godot snaps mode-1 values), so the **body** teleports between
  packets *by design* — collision and host hit-resolution must use that true position. The visible
  stutter is hidden by easing the decoupled `Visual` toward it (see `CLAUDE.md` → Replication
  Modes). **Don't "fix" the body snap by lerping the body** — that would desync collision/hits.
  Smooth the Visual, not the body. (Players done; remote enemies are a deferred follow-up.)
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
