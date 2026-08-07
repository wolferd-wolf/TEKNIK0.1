extends RefCounted

const STAGE5_CACHE := preload("res://scripts/world/playable_world_stage5_cache_fast.gd")
const CHUNK_SIZE := 12
const PADDING := 2


static func build(coord: Vector2i, sampler) -> Dictionary:
	# Stage 5 remains the dense hot path. Stage 6 is intentionally sparse: first
	# build the accepted Stage 5 cache, then touch only columns inside accepted
	# lake/pond feature bounds. Chunks without a basin do no per-column Stage 6
	# work at all.
	var result: Dictionary = STAGE5_CACHE.build(coord, sampler)
	var heights: PackedInt32Array = result.get("heights", PackedInt32Array())
	if heights.is_empty():
		return result

	var width := CHUNK_SIZE + PADDING * 2
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	var min_x := origin_x - PADDING
	var min_z := origin_z - PADDING
	var max_x := origin_x + CHUNK_SIZE + PADDING - 1
	var max_z := origin_z + CHUNK_SIZE + PADDING - 1
	var features: Array[Dictionary] = sampler.stage6_collect_features_for_bounds(
		min_x,
		min_z,
		max_x,
		max_z
	)
	if features.is_empty():
		return result

	for feature: Dictionary in features:
		var center_x := int(feature["center_x"])
		var center_z := int(feature["center_z"])
		var radius_x := float(feature["radius_x"])
		var radius_z := float(feature["radius_z"])
		var feature_min_x := maxi(min_x, floori(float(center_x) - radius_x))
		var feature_max_x := mini(max_x, ceili(float(center_x) + radius_x))
		var feature_min_z := maxi(min_z, floori(float(center_z) - radius_z))
		var feature_max_z := mini(max_z, ceili(float(center_z) + radius_z))
		for world_z in range(feature_min_z, feature_max_z + 1):
			var cache_z := world_z - min_z
			var row := cache_z * width
			for world_x in range(feature_min_x, feature_max_x + 1):
				if sampler.stage6_feature_distance_squared(world_x, world_z, feature) >= 1.0:
					continue
				var cache_x := world_x - min_x
				var index := row + cache_x
				heights[index] = sampler.stage6_shape_height_for_feature(
					heights[index],
					world_x,
					world_z,
					feature
				)

	result["heights"] = heights
	return result
