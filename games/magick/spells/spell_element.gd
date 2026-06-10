class_name SpellElement
extends Resource

## The damage + reaction layer painted on a Form. The reaction is what makes an Element feel
## distinct beyond raw damage: Fire lingers (burning DoT), Lightning arcs (chain to nearby units,
## including allies — friendly-fire comedy). NONE = a plain damage element (the future "Arcane"
## baseline). World-volume reactions (oil/water) come in a later PR.

enum Reaction { NONE, FIRE, LIGHTNING }

@export var display_name: String = "Fire"
@export var damage: int = 25
@export var color: Color = Color(1.0, 0.45, 0.1)

## Cosmetic cast SFX, played when a spell with this element is fired (per-element: Fire hisses,
## Lightning crackles — the Form doesn't matter, so the Burst variants inherit it). Played locally
## on every peer, never networked (the cast event replicates, each peer plays its own sound).
@export var cast_sound: AudioStream

@export var reaction: Reaction = Reaction.NONE

## Lightning chain tuning (reaction == LIGHTNING).
@export var chain_count: int = 0          # max extra units the arc jumps to
@export var chain_range: float = 6.0      # max jump distance between units
@export var chain_falloff: float = 0.6    # damage multiplier applied per jump

## Fire burn tuning (reaction == FIRE).
@export var burn_dps: int = 0             # damage per second while burning
@export var burn_duration_sec: float = 0.0
