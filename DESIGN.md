# DESIGN.md — Magick With Friends

DESIGN is **decision-led**: vision, the locked design decisions, the build roadmap, and parked
ideas. `CLAUDE.md` is **structure-led** (how the code is organized + the dev workflow). Expect
some overlap — when a fact appears in both, the *decision* lives here and the *implementation
detail* lives in `CLAUDE.md`. The blow-by-blow rationale lives in the design transcript / plan;
the decisions here are settled unless told otherwise.

---

## Game Vision

**Magick With Friends** is a **3D, online co-op, first-person, horde-based** game built for
**close friend groups** (not public matchmaking). Tone is **"friend slop"** — chaotic fun,
friendly-fire laughs, happy accidents, jank-as-charm. It is explicitly **NOT** a
balance-tight, optimal-build competitive game.

> **Project frame (the bigger picture).** At its core this is a **reusable co-op multiplayer
> spine** — host/join, the swappable transport seam, the host-authoritative model, spawners +
> event bus — and *games are built on top of it*. The **spell game described here is the first and
> current focus**: the near-term job is to prove it's fun with friends before broadening. The
> longer-term direction — keep the spine constant and let the *level* be the game (the swappable
> mini-game sandbox in Future Considerations) — is real but **not active**: no second game starts
> until the slice proves out. Everything below describes the spell game unless it says otherwise.

> **⚠ Online status (vision vs reality):** the identity is *online* co-op, but on **this** codebase
> only **same-machine two-window** is verified. Per-peer authority **does** propagate correctly — the
> untested piece is **cross-machine transport** (NAT / relay / latency), not authority. Don't claim
> "online verified" until that test is done. Full detail + the plan: the *Re-verify real online MP*
> milestone in the roadmap below (canonical home for this story).

- **Core loop:** 2–4 players fight escalating hordes together in first-person.
  **Friendly fire is ON and is a design pillar** — it's the comedy engine, not a footnote.
- **Combat — the BLEND spell system (decided).** You wield a wand/staff that casts spells
  built by *blending* a **Form** (delivery shape) with an **Element** (damage + reaction
  layer). **One cast = one fused effect.** This captures the *feel* of Noita's wands
  (combinatorial, emergent, things-go-wrong) but is deliberately **shallow** — it is **NOT**
  Noita's sequence/program model (no triggers, timers, multicast, or nesting).
  - **Form ceiling (~7).** Forms carry the mechanical distinctness, so the set is intentionally
    capped at roughly seven candidates: projectile, beam, cone, wall, bubble, AoE burst, trap orb.
    Elements stay a thin damage+reaction layer on top. (The slice ships Projectile + AoE burst.)
- **Randomness is the keystone.** Forms/elements are dealt randomly (drops), so nobody can
  pre-build an optimal loadout. This keeps runs fresh, blocks an external "netdeck" meta,
  and flattens intra-group power gaps so one power-gamer friend can't pull ahead on builds.
- **Make-or-break constraint:** chaos must be **unpredictable going in, legible in
  hindsight.** "My fireball ricocheted into Dave" = good; "everyone took damage, nobody
  knows why" = bad. Readable telegraphs, distinct per-element VFX, and readable reactions
  are a **priority, not polish-later.**
  - **Acceptance bar (how we know it passes):** after any death, the victim can **name what
    killed them** — which element/form, and for friendly fire *whose* — within a couple
    seconds, **unprompted**. We ask this explicitly in the playtest. Per effect the bar is:
    a distinct color + a pre-impact telegraph + a readable reaction. (A playtest question,
    not telemetry — staying cheap.)

**Influences:** the co-op horde lineage (**Left 4 Dead / Vermintide / Helldivers 2**) for
the format and the friendly-fire chaos; **Noita** for the wand-building *feel* (the blend,
not the per-pixel simulation).

### Design decisions

**Decided (do not re-litigate or contradict):**

- **Authority model.** **Per-player authority** over your own character (movement, position,
  input) for crisp self-feel — each peer simulates its own player and replicates position
  outward. **Host authority** over damage / health / death / respawn (reliable RPC *value*-sync
  from `Main`, not a `MultiplayerSynchronizer`) and, net-new, enemies / waves / pickups / world
  reactions — the interaction layer needs one resolver to stay consistent and *legible*. This
  matches Godot best practice for trusted friend co-op (peer-owns-input + host-authoritative
  health via RPC). Client-side movement prediction is **not** used; add only if real-connection
  playtests show input lag. The split is *decided*; fully *formalizing* it in code (enemies / waves /
  pickups / reactions) is a post-slice task, done as those systems land.

- **Player movement controller → `CharacterBody3D`.** Was open (keep `RigidBody3D` for the
  physics-chaos tone vs. migrate); now **decided: migrate to `CharacterBody3D`** — crisper,
  more standard FP feel, and it fixes the airborne wall-stick the RigidBody force-model causes.
  Physics-chaos (knockback, ragdoll, getting shoved) becomes **deliberate scripted** effects rather
  than emergent jank. **Implementation deferred to its own PR** — the player is `RigidBody3D` in code
  until then. **Enemies** are already `CharacterBody3D`.

**Still open (DECIDE LATER — do not invent these):**

- **Run / meta structure** beyond bare wave-survival (stages? mission arc? between-run
  progression?) — **open.** The slice is wave-survival only.
- **Ability resource.** Per-cast **cooldown** for now; a mana pool (repurpose
  `StaminaComponent`) is deferred.

> **Superseded:** earlier drafts committed to *third-person*, a *RoR2 roguelite* frame, and
> *deferred combat*. All three are now decided differently (first-person; co-op horde; blend
> combat). Ignore any third-person / RoR2-primary framing in older history.

---

## Roadmap — What Is NOT Done (the Vertical Slice, then beyond)

The immediate work is a **cheap vertical slice** — the smallest thing that lets 2–4 friends
play and answers "is the core fun?" Built on the existing co-op framework, **one feature per
PR**, legibility baked into each PR (not deferred). Everything is host-authoritative and
reuses the `MultiplayerSpawner` / RPC / `GameEvents` patterns.

1. **Player FP controller cleanup.** ✅ DONE — climbing/parkour removed, LMB → cast,
   first-person run/jump kept. (RigidBody3D-vs-CharacterBody3D still open.)
2. **Blend spell core + friendly fire + respawn.** ✅ DONE — `Spell`/`SpellForm`/
   `SpellElement`/`BlendSpell` + `WandComponent` (Form+Element slots, `cast_delay_sec`),
   Projectile + Fire, host-authoritative projectile spawn, FF damage on `HealthComponent`
   (default 100), local cosmetic cast feedback, current-spell HUD, cheap respawn with a
   death fade. Validated two-window.
3. **Enemies + wave spawner.** ✅ BUILT — headless-validated; two-window playtest pending.
   `EnemyBase` (CharacterBody3D + `HealthComponent`, host AI: gravity + steer to nearest alive
   player + cooldown'd melee routed through `apply_player_damage`), replicated host→clients via
   a `MultiplayerSynchronizer`; `systems/director/wave_director.gd` is a host-only escalating
   ring spawner feeding a 3rd `MultiplayerSpawner`. Spells already kill enemies via the existing
   projectile→`HealthComponent` path. Arena flattened to a walled horde box (climbing geometry
   removed). Collision layers now named + explicit (world / players / enemies / projectiles) — see
   `CLAUDE.md`. The wave director now **boots paused** — the host begins the round via the dev
   console `start` (so you can set up before the horde comes).
4. **Blend matrix + reactions + world volumes.** ✅ MOSTLY BUILT — the **2×2 Form×Element matrix**
   + **entity reactions** (`systems/reactions/reactions.gd`: lightning chain incl. allies, fire
   burn/DoT) landed (#33), index-stable via the `SpellCatalog` autoload. **Still pending:** the
   1–2 `Area3D` world reactive volumes (oil, water) and the distinct per-element VFX done-criterion.
5. **Wild-cascade A/B (hardcoded) — a *flavor* probe, NOT an engine bake-off.** Blend is the
   **decided engine** (Form × Element, one fused cast) and this A/B cannot move that. Its only
   question: do players want chaos sourced more from the **world** (reactions/physics — blend's
   default) or from the **spell** (internal cascades)? — which informs *modifier/content*
   direction later, not the engine. 2–3 authored `CascadeSpell`s (split → chain → explode) via
   the `Spell.cast_on_host()` seam + a `GameConfig.spell_mode = BLEND | CASCADE` toggle, no generative
   engine. (The 3 hand-authored cascades aren't a fair proxy for cascade-*as-a-system* — fine,
   because we're sensing flavor preference, not picking an engine.)
6. **Random keep-or-swap acquisition.** Enemy-dropped Form/Element pickups; `interact`
   action; interact-to-swap that drops the old spell as a re-grabbable pickup.
7. **Legibility tightening pass**, then the 30-minute friend playtest (run as the A/B).

**Presentation (cross-cutting, in progress).** Placeholder capsules retired for **KayKit** models
(Mage / Skeleton). Players animate idle↔run; skeletons idle↔run + an attack swing, facing their
target — all driven by one reusable `LocomotionAnimator`, with animation **derived locally from a
replicated speed/facing driver** (never replicated animation state). See `CLAUDE.md` → Animation.
Still ahead: spell VFX, wand/hands viewmodel, enemy death animation.

Beyond the slice (only if it proves fun):
- **GameEvents vocabulary** — replace `enemy_died` with `player_died`, `enemy_died(pos)`,
  `wave_started`, `run_ended`, `spell_picked_up`, etc.; let callers emit directly.
- **Run / meta structure** beyond wave-survival.
- **Production HUD** (health/shield, current spell, wave/timer).
- **Spawn point system** (4–8 points, by player index).
- **Re-verify real online MP (named milestone).** Per-peer authority already propagates correctly
  — the custom `spawn_function` runs on **all peers** (Godot docs), so each client re-runs it and
  sets `set_multiplayer_authority(data.peer_id)` on its copies. Verifiable now via the two-window
  `[AUTH]` diagnostic in `player.gd`. What's still untested is **cross-machine transport** (NAT /
  port-forwarding / relay) + latency feel — real online worked on the predecessor (external relay);
  confirm it here on two actual machines before claiming "online." (Not an authority bug — earlier
  notes that framed it as one were a misdiagnosis.)
- **Velocity sync** for smoother client interpolation.
- **More Forms/Elements**, modifiers (constrained), downed/revive.

---

## Future Considerations (Do Not Implement Yet)

- **Noita-style material simulation.** The blend reaction layer uses cheap `Area3D` volumes,
  NOT a per-pixel falling-sand sim. Full simulation (fire spreading per-pixel, liquids,
  electrified water at sim fidelity) is expensive and hard to net-replicate in 3D — stay with
  tagged volumes / area triggers until there's a reason not to.
- **Mana resource** — repurpose `StaminaComponent` if cooldowns prove too shallow.
- **Steam networking** — replace the ENet peer with `SteamMultiplayerPeer`; keep all
  spawn/RPC logic identical (the point of `NetworkManager`).
- **Cloudflare Workers / WebSocket relay** — online play without port forwarding.
- **Lobby / ready system**, **spectator camera** for dead players, **gamepad** bindings +
  right-stick look.
- **Multiplayer sandbox / swappable mini-game levels.** The longer-term broadening introduced in
  the *Project frame* (top of this doc): keep the netcode spine **constant** and let the *level* be
  the game — the horde spell-caster becomes one level; other levels could be entirely different
  mini-games sharing the same netcode, with the **host picking which level/game** to run and
  broadcasting that choice. **Not active until the spell-game slice proves out.** The architecture
  is already most of the way there:
  - the level is a **swappable child node** in `main.tscn` (`TestLevel` instance), not hard-wired
    into the game logic;
  - player spawning is **level-agnostic** — `main.gd` finds `PlayerSpawnPosition` via
    `find_child(...)`, so any level with that marker just works;
  - `GameManager`/`GameConfig` + the existing host→client RPC pattern already carry pre-game
    config, so a `selected_level` field + a broadcast RPC slot in cleanly.
