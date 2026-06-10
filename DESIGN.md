# DESIGN.md — the friendslop framework (working title)

DESIGN is **decision-led**: vision, the locked decisions, the build roadmap, and parked ideas.
`CLAUDE.md` is **structure-led** (how the code is organized + the dev workflow); the
**reference-led** docs (`docs/NETWORKING.md`, `docs/SPELLS.md`) trace system behavior
end-to-end. When a fact appears in more than one place, the *decision* lives here.

> **⚡ THE REFRAME (2026-06-10, supersedes "Build this game").** The product is the
> **framework**, not the spell game. Earlier versions of this doc framed the project as
> "build Magick With Friends and prove it's fun" with a reusable spine as a parked maybe.
> That's inverted now: the durable goal is a **reusable host-client co-op multiplayer
> framework for Godot** that makes standing up a 2–8-player friend-group game easy. The
> spell game was a starter idea, isn't a passion project, and is hereby **demoted to test
> fixture** (see the Fixture section below). Ignore any "build this game" framing in older
> history.

---

## Project Vision

A **Godot 4 framework for online co-op games played with close friends** — host-client,
2–8 players, drop-in lobbies, friendly-fire-tolerant "friend slop" tone in the games built on
it. **Not** public matchmaking, **not** dedicated servers, **not** competitive netcode
(no rollback or client prediction unless a real game demands it).

**The promise:** when a game idea worth being passionate about arrives, the multiplayer
plumbing — connection, authority, replication, spawning, session UX, voice — is already
solid, documented, and boring, so all the energy goes into the game.

**Flagship capabilities (built or planned):**

- Robust connect / host / disconnect flow with honest error UX *(built; real-online
  **verified** — see milestone 1)*
- Host-authoritative simulation with per-player input authority *(built — the decided
  authority model below)*
- Replicated spawning of players / entities with late-join replay *(built; late-join
  state sync is milestone 3)*
- Lobby / ready flow *(milestone 4)* · spawn points *(milestone 5)*
- **Proximity voice chat** *(milestone 6 — the headline feature)*
- NAT traversal / relay so friends don't fight port forwarding *(working answer: **playit.gg**
  — see milestone 1)*
- Dev ergonomics: two-window autostart, headless validation gate, dev console *(built)*

### Design decisions (framework-level)

**Decided (do not re-litigate or contradict):**

- **Frameworks are extracted, not designed.** The framework grows by extraction from running
  games, demand-driven — with one carve-out: the **universal set** (lobby/ready, late-join
  sync, spawn points, voice chat, NAT/relay, disconnect UX) is predictably needed by *any*
  friend co-op game and may be built game-free against the current fixture. Everything else
  (ability systems, inventory, AI patterns) waits for a game to demand it.

- **Import direction.** Spine code never references a game noun; game code imports the spine,
  never the reverse. (The enforceable rule lives in `CLAUDE.md` → Rules; the spine-vs-game
  inventory lives in `docs/NETWORKING.md` §10.)

- **Authority model.** **Per-player authority** over your own character (movement, position,
  input) for crisp self-feel — each peer simulates its own player and replicates position
  outward. **Host authority** over everything interactive: damage / health / death / respawn
  (reliable RPC *value*-sync from `Main`, never a `MultiplayerSynchronizer`), entities, waves,
  pickups, world reactions. Clients send intent; the host owns the simulation and replicates
  outward; client cast/action *feel* is local cosmetic feedback only. This matches Godot best
  practice for trusted friend co-op. Client-side prediction is **not** used; add only if real
  playtests show input lag.

- **Kinematic actors.** Players and enemies are `CharacterBody3D` (`move_and_slide`);
  physics-chaos is deliberate scripted effects, not emergent rigid-body jank. (Fixture-proven;
  lives at the module layer, not core — a future game may ship a different controller.)

- **Prototypes live in-repo; games graduate out.** New game ideas start as cheap levels /
  game folders inside this repo (the level is already a swappable child of `main.tscn`;
  spawning is level-agnostic). A game gets its own repo only when it becomes a real project.
  **Repo-split trigger for the framework itself:** a second *graduated* game consuming it, or
  wanting independently-versioned addon releases — not before.

**Still open (DECIDE LATER — do not invent these):**

- **Transport for real online — working answer found, final answer open.** **playit.gg**
  (a UDP tunnel the host runs; zero code changes) got a real remote friend into a session —
  good enough for now. Whether to ever replace it (`netfox.noray`, Steam, a hosted relay) is
  decided only if playit.gg proves unreliable/laggy in regular sessions or the third-party
  dependency starts to chafe. The swappable-transport seam keeps all options open.
- **Voice chat implementation** — milestone 6 opens with a research spike (see roadmap).
- **Host migration** — probably never (friend groups can re-host); revisit only if drop-outs
  prove painful in real sessions.

---

## Roadmap — Framework Milestones

Ordered by risk-burndown: verify the core promise before building on top of it. One feature
per PR, validated per `CLAUDE.md`.

1. **Real-online verification. ✅ SUBSTANTIALLY DONE (2026-06-10).** A real remote friend
   joined a session over the internet via **playit.gg** (a UDP tunnel the host runs — no port
   forwarding, zero code changes). The core promise is proven; per-peer authority propagates
   (the two-window `[AUTH]` repro in `CLAUDE.md` plus the live session). **Still open, gather
   during normal play:** latency *feel* over a real link (host-authoritative casting with no
   prediction is the #1 risk — rotate who hosts), remote-player smoothing under real jitter,
   and mid-session disconnect behavior. The transport *decision* (keep playit.gg vs noray/
   Steam/relay) stays open — see Still-open decisions above.
2. **Spine/game restructure. ✅ DONE (2026-06-10).** Fixture code lives under `games/magick/`,
   the spine under `framework/` — the import-direction rule is visible in the directory tree.
   Two named follow-ups remain, forced properly by the next prototype: **(a)** split the
   fixture `enemy_*` signals off `framework/autoloads/game_events.gd`; **(b)** split the mixed
   `main.gd`/`main.tscn` composition root per-game (this is also when `selected_level` +
   host-broadcast land in `GameConfig`).
3. **Late-join state push.** Close the known gap: on `peer_connected`, the host pushes
   current health / dead flags / equip state to the new peer (reuses `_sync_health` /
   `_set_dead` / the wand equip-sync). Required for drop-in friend sessions.
4. **Lobby / ready flow + session UX.** Pre-game gathering: who's here, ready-up, host
   starts; in-game join/leave notices; kicked/full/failed states surfaced with honest
   messages (the spine already kicks and errors correctly — milestone is the UX).
5. **Spawn-point system.** 4–8 points, assignment by player index; closes the
   everyone-spawns-in-one-spot gap.
6. **Proximity voice chat.** Opens with a **research spike** — Godot 4 has no built-in VoIP.
   Candidates: an existing godot-voip-style addon · `AudioEffectCapture` + an Opus
   GDExtension · a raw-PCM LAN-quality MVP to prove the pipe first. Proximity itself is the
   easy half: route each speaker's stream through an `AudioStreamPlayer3D` on their player
   node (the cast-SFX positional pattern already does exactly this). Decide build-vs-adopt
   from the spike, then ship.
7. **8-player validation.** `GameConfig.max_players` already scales; nothing has run above 2.
   Verify spawner, replication bandwidth (mode-1 sync × 8), and the HUD/console at 8.

**Cadence guard (process, not a milestone).** Every month or two, build a cheap throwaway
prototype level on the spine (a weekend's work, no polish). This is the extraction discipline:
prototypes pull real demands out of the framework and stop it drifting into speculative,
fits-nothing generality. It's also the antidote to the known solo-dev failure mode where
tool-building becomes a way to defer the scary creative work. **The intake is
`docs/IDEAS.md`** — the idea backlog (capture > debate; the clip / the loop / framework
demands; promote one SEED to a gray-box monthly-ish).

**Backlog (unscheduled, demand-driven):** richer `GameEvents` vocabulary
(`player_died`, `wave_started`, …) · remote-**enemy** visual smoothing (reuse
`RemoteVisualSmoother`) · scripted knockback/ragdoll · production HUD patterns · gamepad
bindings · spectator camera for dead players · Steam transport (`SteamMultiplayerPeer` behind
the existing seam).

---

## Fixture Game: Magick With Friends (demoted — no new investment as a game)

The spell-casting horde game is the framework's **test fixture**: the runnable consumer that
exercises connection, authority, replication, spawning, combat-shaped RPCs, and the validation
harness (`tools/smoke-test.sh` boots it; the two-window workflow plays it). It is kept because
a framework without a consumer can't be validated — and replaced organically whenever a
prototype exercises the spine better.

**The rule:** fixture work happens only when it *blocks a framework milestone* (e.g. its
equip-sync is the late-join test case). No new Forms, no pickups loop, no legibility passes,
no fun-tuning. **Superseded by the reframe:** the keep-or-swap acquisition loop (old item 6),
the legibility tightening pass, and the "is it fun?" playtest question (the 2-machine session
survives as framework milestone 1, stripped of its fun-test framing).

### Recorded design decisions (kept because they explain the code)

These shaped the code that exists; they are *frozen*, not deleted:

- **Vision (as a game):** 3D, online co-op, first-person horde for close friend groups;
  "friend slop" tone — chaotic fun, friendly-fire laughs (FF is ON and was a design pillar);
  influences: L4D/Vermintide/Helldivers for format, Noita for the wand *feel*.
- **Combat — the BLEND spell system.** A wand casts a **Form × Element** fusion; **one cast =
  one fused effect**, deliberately shallow — NOT Noita's sequence/program model (no triggers,
  timers, multicast, nesting). **Form ceiling ~7** (projectile, beam, cone, wall, bubble, AoE
  burst, trap orb — slice shipped Projectile + Burst); Elements stay a thin damage+reaction
  layer (slice: Fire, Lightning). Modifiers (Split/Bounce/Homing) were cut — they erode
  per-cast legibility. Full mechanics: `docs/SPELLS.md`.
- **Randomness as keystone:** forms/elements dealt randomly so nobody pre-builds an optimal
  loadout (blocks netdecking, flattens intra-group power gaps).
- **The legibility north star:** chaos must be *unpredictable going in, legible in hindsight* —
  after any death the victim can name what killed them (element/form, and whose) within
  seconds, unprompted, **from what they saw in-world** (no kill-feed during tests). Per-element
  color + telegraph + readable reaction is the bar. Per-caster attribution was a deferred
  option. (Frozen with the fun test; recorded because the per-element VFX/color plumbing in
  the code exists to serve it.)
- **Reactions are two cheap layers, not a pixel sim:** entity status (lightning chains incl.
  allies, fire burn/DoT — built) + hand-placed `Area3D` world volumes (oil, water — never
  built; frozen).
- **What was built and verified** (two-window): blend casting, friendly fire, death/respawn,
  enemies + escalating wave director, reactions, KayKit presentation with replicated-driver
  animation, remote-player visual smoothing. The wild-cascade A/B experiment was cut
  (mechanism preserved: the `Spell.cast_on_host()` seam + an authored `CascadeSpell` slot in
  cleanly if ever wanted).

---

## Future Considerations (Do Not Implement Yet)

- **Steam networking** — replace the ENet peer with `SteamMultiplayerPeer`; keep all spawn/RPC
  logic identical (the point of `NetworkManager`). Backlog; the milestone-1 transport decision
  may pull it forward.
- **netfox (or equivalent) as a networking foundation.** Evaluated during the remote-smoothing
  work (PR #55) and deliberately deferred: its rollback/prediction core is overkill for
  host-authoritative co-op. Revisit as **one** decision if/when we want lag compensation,
  client-side prediction, or **`netfox.noray`** for NAT punch-through — the noray piece is
  exactly milestone 1's question. Adopt a foundation on its own merits, not to patch a symptom.
- **Cloudflare Workers / WebSocket relay** — an alternative milestone-1 answer if noray
  disappoints.
- **Noita-style material simulation** — frozen with the fixture; cheap tagged volumes were
  always the ceiling here. Expensive and hard to net-replicate in 3D.
- **Mana resource** — `StaminaComponent` is kept (unused) as the future pool, if a game wants
  ability costs beyond cooldowns.
- **Multi-game sandbox / host-picks-the-level.** No longer parked — this *is* the project
  vision, absorbed into the roadmap. The implementation notes stand: the level is a swappable
  child of `main.tscn`; spawning is level-agnostic (`find_child("PlayerSpawnPosition")`);
  `GameManager`/`GameConfig` + the host→client RPC pattern carry pre-game config, so
  `selected_level` + a broadcast slot in cleanly (milestone 2).
