extends "res://scripts/world/playable_world_stage5_frozen_runtime.gd"

const STAGE6_DATA := preload("res://scripts/world/playable_world_stage6_generation_data.gd")
const STAGE6_CACHE := preload("res://scripts/world/playable_world_stage6_generation_cache_fast.gd")

# Frozen Stage 6 facade for historical acceptance tests. Later stages may
# intentionally change geography, so Stage 6 equivalence/performance must use
# the accepted Stage 6 data/cache pair rather than the moving public runtime.
func _init() -> void:
	data = STAGE6_DATA.new()


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return STAGE6_CACHE.build(coord, data)
