extends "res://scripts/world/playable_world_stage2_generation_runtime.gd"

const STAGE2_FAST_CACHE := preload("res://scripts/world/playable_world_stage2_cache_fast.gd")

# Frozen Stage 2 performance oracle. The historical Stage 2 runtime remains in
# place as the architectural reference; this wrapper swaps only the direct
# generation/cache path used by the Stage 2 gate for an output-equivalent fast
# cache that omits terrain-climate noise samples Stage 2 no longer consumes.

func _build_column_caches(coord: Vector2i) -> Dictionary:
	return STAGE2_FAST_CACHE.build(coord, data)
