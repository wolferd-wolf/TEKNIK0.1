extends "res://scripts/world/playable_world_stage3_generation_runtime.gd"

const FROZEN_STAGE3_DATA := preload("res://scripts/world/playable_world_stage3_generation_data.gd")
const FROZEN_STAGE3_CACHE := preload("res://scripts/world/playable_world_stage3_frozen_cache_fast.gd")

# Test-only frozen Stage 3 runtime. Streaming behavior remains inherited from
# the accepted Stage 3 runtime; direct cache construction uses the optimized,
# semantics-equivalent Stage 3 cache so later hydrology does not contaminate
# Stage 3's performance oracle.

func _init() -> void:
	data = FROZEN_STAGE3_DATA.new()


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return FROZEN_STAGE3_CACHE.build(coord, data)
