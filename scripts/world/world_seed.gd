extends Node

# Single source of truth for the active world's seed.
#
# Previously every terrain/mesh sampler had its own hardcoded
# `const WORLD_SEED := 734921`, so every launch generated the exact same
# world. This autoload generates one random seed per game launch and every
# sampler/mesher now reads it from here instead of hardcoding a literal.
#
# To support a fixed/shareable seed later (e.g. a "enter seed" field on a
# new-game screen), call set_seed(value) before any world data/mesher
# objects are constructed -- it must happen before ChunkManager._ready()
# instantiates the generation runtime.
#
# playable_world_mesher.gd and playable_world_stage6_mesher.gd read WORLD_SEED
# from static functions, so their WORLD_SEED is a `static var`, not an
# instance var -- it has to be pushed in explicitly rather than picked up
# via a normal instance initializer.

const BASE_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const TREE_MESHER := preload("res://scripts/world/playable_world_stage6_mesher.gd")

var current_seed: int = 0

func _ready() -> void:
	var saved_seed: Variant = SaveManager.get_saved_seed()
	if saved_seed != null:
		current_seed = int(saved_seed)
	else:
		randomize()
		current_seed = randi()
	_apply_to_static_meshers()

# Call before world generation starts to use a specific seed instead of a
# random one (e.g. loading a save, or a player-entered seed string).
func set_seed(value: int) -> void:
	current_seed = value
	_apply_to_static_meshers()

func _apply_to_static_meshers() -> void:
	BASE_MESHER.WORLD_SEED = current_seed
	TREE_MESHER.WORLD_SEED = current_seed
