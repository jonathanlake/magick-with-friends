# DESIGN.md — Magick With Friends (the fixture game)

**Charter:** decision-led, game-scoped — the frozen design decisions of the Magick With
Friends fixture, kept because they explain the code under `games/magick/`. The framework's
vision, decisions, and roadmap live in the root `DESIGN.md` (which owns the fixture *rule*:
work on this game only when it blocks a framework milestone). Mechanics reference:
`SPELLS.md` (same directory). Game docs live with the game — if this game ever graduates to
its own repo, this file goes with it.

---

## Status: test fixture (demoted — no new investment as a game)

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

## Recorded design decisions (kept because they explain the code)

These shaped the code that exists; they are *frozen*, not deleted:

- **Vision (as a game):** 3D, online co-op, first-person horde for close friend groups;
  "friend slop" tone — chaotic fun, friendly-fire laughs (FF is ON and was a design pillar);
  influences: L4D/Vermintide/Helldivers for format, Noita for the wand *feel*.
- **Combat — the BLEND spell system.** A wand casts a **Form × Element** fusion; **one cast =
  one fused effect**, deliberately shallow — NOT Noita's sequence/program model (no triggers,
  timers, multicast, nesting). **Form ceiling ~7** (projectile, beam, cone, wall, bubble, AoE
  burst, trap orb — slice shipped Projectile + Burst); Elements stay a thin damage+reaction
  layer (slice: Fire, Lightning). Modifiers (Split/Bounce/Homing) were cut — they erode
  per-cast legibility. Full mechanics: `SPELLS.md`.
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

## Frozen future ideas (do not implement)

- **Noita-style material simulation** — frozen with the fixture; cheap tagged volumes were
  always the ceiling here. Expensive and hard to net-replicate in 3D.
