# IDEAS.md — The Game-Idea Backlog

**Charter: capture > debate.** Every idea gets three lines and a status — never an argument.
Ideas are cheap to write down and expensive to litigate in the abstract; a **weekend gray-box
answers "is it fun?" better than two weeks of doubt**. Monthly-ish, promote whichever SEED you
can't stop thinking about. This file is the intake for the cadence guard in `DESIGN.md`
(periodic throwaway prototypes keep the framework honest).

**The three lines per idea:**
- **The clip** — the 20-second moment someone posts in the group chat the next morning.
  (Design backwards from this. If you can't picture the clip, the idea isn't ready.)
- **The loop** — one sentence.
- **Framework demands** — what it pulls out of the spine (this is half the point).

**Statuses:** `SEED` → `GRAY-BOXED` (a `games/<name>/` prototype exists) → `PROMOTED` (real
project) or `SHELVED` (one line why — shelved ideas stay; enthusiasm is allowed to come back).

---

## On "a similar game already exists"

It almost always does, and it almost never matters. Lethal Company is Phasmophobia plus scrap
quotas. Among Us is the parlor game Werewolf and sat dead for two years. Vampire Survivors is
a Castlevania asset pack with the aiming removed. **Similar games existing is validation that
the loop is fun** — the novelty bar only matters if you're competing for strangers' wallets.
The bar here is: *would my group laugh for an hour on Friday?* And in this framework's tone,
network jank is a comedy asset — a timing game made harder by 80 ms of latency isn't broken,
it's funnier.

## Idea-generation prompts

- **Design backwards from the clip** (see charter).
- **Playground games** — three-legged race, tug-of-war, sardines, red-light-green-light,
  capture the flag… physical games digitize into jank comedy almost automatically, and
  they're creatively free.
- **Mundane jobs under pressure** (the Overcooked formula) — movers, window washers,
  trawler crew, baggage handlers, surgeons.
- **Voice as mechanic, not channel** — asymmetric info (one player reads/sees, others act),
  proximity hide-and-seek with open mics, mic volume as a game input.
- **Shared body / shared resource** — one limb each, one steers one pedals, crew stations.
- **The framework lens** — naturally cheap: host-simulated entities, FP movement, replicated
  spawning, voice (planned). Currently expensive: precise synced physics piles, huge
  streaming worlds, competitive precision. Spend weekends, not quarters.

---

## Backlog

### "FIELD DAY" — school-field-day party collection (umbrella) · SEED
- **The clip:** the medal ceremony after an event where everyone failed.
- **The loop:** 2–8 friends play short, dumb, school-field-day events (one swappable level
  each); score across an evening; variety IS the product.
- **Framework demands:** lobby/ready, `selected_level` + host broadcast, the `main.gd`
  per-game split, score/round state — i.e. exactly the queued framework milestones. Each
  event is a weekend gray-box, which satisfies the cadence guard by construction.
- **Why this umbrella matters:** no single idea has to be The Idea; "similar games exist"
  dissolves (party collections compete on character, this one stars your friends); shelved
  bigger ideas can donate their best 5 minutes as an event.
- **Why the school theme earns its place** (renamed from "Friendlympics"): field day isn't
  just a name — it's a free roster (everything from gym class: sack race, tug-of-war,
  dodgeball, kickball, capture the flag, egg-and-spoon, water-balloon toss, the rainbow
  parachute) and a free art direction (cones, whistles, ribbons, juice boxes). The nostalgia
  does comedic lifting on its own.

### Three-legged race · SEED (candidate first event)
- **The clip:** two grown adults faceplanting at the starting line, in sync, twice.
- **The loop:** two players' legs are tied; alternate keypresses in rhythm to advance —
  mistime and you both eat dirt; first pair to the line wins.
- **Framework demands:** a **shared-body host-simulated entity with two input authorities**
  — finally consumes the input-sync seam (`player_input_synchronizer_component` replicates
  input that nothing remote reads today). Latency desync between the two players IS the
  comedy. Scripted ragdoll on fail (the physics-chaos tone, kinematic-safe).
- Cousins for later events: potato sack (solo rhythm), wheelbarrow (one steers one pumps),
  tug-of-war (team rhythm), egg-and-spoon (move slowly while friends jostle), relay (baton
  handoff under latency), red-light-green-light (ragdoll pile at the line), water-balloon
  toss (pairs toss-catch over latency, step back each round).

### Red Rover · SEED (FIELD DAY event — shares the player-link module)
- **The clip:** "RED ROVER RED ROVER, send DAVE on over" yelled into voice chat — then Dave
  either bounces off the line flat on his back, or blasts through two ragdolling friends.
- **The loop:** two lines of linked players; the calling team names a runner (out loud — the
  chant is the ritual); the runner charges a chosen link; the two linked defenders time/mash a
  grip input on impact — hold and the runner joins your line, break and they take someone home.
- **Framework demands:** the **player-link constraint** (scripted distance clamp + break
  threshold between two CharacterBody3Ds — the SAME primitive as the three-legged leg-tie:
  build the link module once, get both events), charge movement, scripted ragdoll, team/round
  state. **Voice is baked into the rules** — the call-out is the targeting ritual, the first
  event where the mic is part of the design rather than the channel.

### Shipwreck diving — ship crew + divers + walkie-talkies · SHELVED (enthusiasm cooled)
- **The clip:** a diver's panicked radio call while the deck crew argues about the winch.
- **The loop:** 1–2 players run the ship (tasks, map, winch, air); the rest dive wrecks for
  salvage under oxygen pressure; walkie-talkies carry everything.
- **Framework demands:** the strongest **voice-channel demand-driver** (radio = push-to-talk
  channels, the *easy* version of voice); asymmetric roles → lobby; swim controller →
  validates controller-as-module; oxygen → `StaminaComponent` finally used.
- **Why shelved:** proven format (Lethal Company / Barotrauma territory) took the wind out of
  the sails. Kept because the *shape* is excellent — and "salvage dash" could return as a
  single party event.

### Quick seeds · SEED
- **Co-op couch movers** — *clip:* the couch wedged in the stairwell, both players screaming
  directions. Two-player carry + interactables + fragile-cargo physics (scripted, not
  emergent).
- **Walkie-talkie manhunt** — *clip:* a hider's breathing giving them away on an open mic.
  Dark map, proximity voice, seekers hear hiders; muting yourself also deafens you.
- **Echolocation horror** — *clip:* someone sneezes, lights up the whole map, the monster
  turns. Mic input volume emits visible pulses that reveal AND attract. Voice-as-light.
- **Belayer + climber** — *clip:* "TAKE! TAKE!! …were you alt-tabbed?" Trust game; one
  player's attention is the other's safety. Asymmetric roles + voice.
- **Tandem kayak / rowing crew** — *clip:* the boat doing donuts while both insist they're
  paddling right. Three-legged race on water; one host-simulated hull, N oar inputs.
- **Fishing trawler** — *clip:* the catch of the day sliding off the deck in a storm while
  the helmsman takes the wave sideways. Jobs-under-pressure; boat = shared station entity.
