extends RefCounted

const STAGE10_CACHE := preload("res://scripts/world/playable_world_stage10_generation_cache_fast.gd")

# Stage 13 river selection is integrated directly into the accepted Stage 10
# hot cache. Older samplers do not expose stage13_river_center_x(), so the same
# cache remains an exact frozen oracle for Stages 10-12 while the Stage 13
# sampler gets independent river lanes without a second generation pass.
static func build(coord: Vector2i, sampler) -> Dictionary:
	return STAGE10_CACHE.build(coord, sampler)
