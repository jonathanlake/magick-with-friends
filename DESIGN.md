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

> **Project frame.** Build **this game** and prove it's fun with friends. (A reusable
> multiplayer-spine / swappable-mini-game-sandbox future is possible — parked in Future
> Considerations — but it earns no architectural weight until a second game needs it.)

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
    seconds, **unprompted**. Per effect the bar is: a distinct color + a pre-impact telegraph +
    a readable reaction. (A playtest question, not telemetry — staying cheap.)
  - **Measure it IN-WORLD, with no answer-printing HUD.** The bar tests whether the chaos was
    legible from what the victim *saw* (color / telegraph / reaction), so the playtest must run with
    **no kill-feed / "killed by X" banner** — a HUD line that prints the answer makes everyone
    "pass" by reading it and contaminates the diagnostic. **Caster identity ("whose")** is the hard
    part — per-element color tells you *lightning*, not *Dave* — and the slice ships per-element VFX
    only, so expect the test to reveal whether "whose" needs **per-caster identity** (tint / trail /
    directional hit cue). That attribution is a **deferred option**, built only if the test shows
    it's needed — and if built, **suppressed/delayed** during any legibility test.

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

- **Player movement controller → `CharacterBody3D`. ✅ DONE.** Migrated from `RigidBody3D` (was open;
  decided; now implemented) — crisper, more standard FP feel, and the airborne wall-stick is gone
  (`move_and_slide` slides along walls). Physics-chaos (knockback, ragdoll, getting shoved) becomes
  **deliberate scripted** effects rather than emergent jank — a follow-up, none implemented yet.
  **Enemies** are also `CharacterBody3D`.

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
   first-person run/jump kept; migrated to `CharacterBody3D` (see the decided item above).
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
5. **Wild-cascade A/B — CUT from the slice (deferred).** Blend is the **decided engine**, so this
   *flavor* probe (world-sourced vs. spell-sourced chaos) can't move it, and 3 hand-authored cascades
   vs. emergent reactions is a noisy signal for a non-pressing question. Parked — revisit only if a
   modifier/content question makes the preference pressing. (Mechanism if ever needed: authored
   `CascadeSpell`s via the `Spell.cast_on_host()` seam + a `spell_mode` toggle.)
6. **Random keep-or-swap acquisition — slice stand-in.** A host-only dev-console **`give [all]`**
   rolls a random `(Form, Element)` onto a player (reuses `SpellCatalog` + `WandComponent`'s
   host-broadcast equip-sync) — enough to playtest the random-loadout / keep-or-swap *loop*. The full
   enemy-dropped pickups + `interact`-to-swap (drop old as a re-grabbable pickup) is **deferred to
   post-slice**.
7. **The fun test — now includes the real-online check.** A light legibility tightening pass, then
   the actual answer to "is it fun?": a **real-connection, 2-machine, 30-minute** session — **NOT**
   two-window/LAN (zero latency hides the #1 risk). This *is* the real-online-MP re-verify, **pulled
   up from "beyond the slice"** — latency killing cast feel is a reason it won't be fun, so it can't
   be gated behind the slice succeeding (that's circular). Per-peer authority already propagates
   correctly (the `spawn_function` runs on all peers; the two-window `[AUTH]` line confirms); the
   untested piece is **cross-machine transport** (NAT / port-forwarding / relay) + **latency feel**.
   Watch for: **cast feel under real latency** (the #1 risk — host-authoritative casting, no
   prediction, masked only by a local muzzle flash), **friendly-fire legibility *from the world***
   (see the acceptance bar), and the **keep/swap loop**.

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
