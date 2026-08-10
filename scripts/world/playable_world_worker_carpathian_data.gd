extends "res://scripts/world/playable_world_carpathian_data.gd"

# Generation-only shipping sampler for background chunk workers.
#
# The authoritative world data object loads user:// save data once on the main
# thread. Chunk workers receive an immutable, chunk-local override snapshot
# separately, so loading/parsing the whole save again in every worker sampler is
# both redundant and a source of Android streaming I/O/allocation pressure.

func load_save() -> void:
	# Intentionally no-op. Procedural sampler state is initialized normally by
	# the inherited _init(); only persistent player-edit loading is suppressed.
	pass
