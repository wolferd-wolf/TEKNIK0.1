extends RefCounted

const STAGE5_CACHE := preload("res://scripts/world/playable_world_stage5_cache_fast.gd")
const CHUNK_SIZE := 12
const PADDING := 2

# Stage 6 generation-only cache. This is the measured world-generation hot path:
# build accepted Stage 5 columns, discover sparse lake/pond features, and shape
# only columns inside those feature bounds. Water-aware tree-origin suppression
# is a meshing concern and is deliberately performed after cache_usec is closed.


static func build(coord: Vector2i, sampler) -> Dictionary:
	var result: Dictionary = STAGE5_CACHE.build(coord, sampler)
	var heights: PackedInt32Array = result.get("heights", PackedInt32Array())
	if heights.is_empty():
		return result
	var world_fields: PackedFloat32Array = result.get("world_fields", PackedFloat32Array())

	var width: int = CHUNK_SIZE + PADDING * 2
	var origin_x: int = coord.x * CHUNK_SIZE
	var origin_z: int = coord.y * CHUNK_SIZE
	var min_x: int = origin_x - PADDING
	var min_z: int = origin_z - PADDING
	var max_x: int = origin_x + CHUNK_SIZE + PADDING - 1
	var max_z: int = origin_z + CHUNK_SIZE + PADDING - 1
	var features: Array[Dictionary] = sampler.stage6_collect_features_for_cached_bounds(
		min_x,
		min_z,
		max_x,
		max_z,
		width,
		world_fields,
		heights
	)
	if features.is_empty():
		return result

	for feature: Dictionary in features:
		var center_x: int = int(feature["center_x"])
		var center_z: int = int(feature["center_z"])
		var radius_x: float = float(feature["radius_x"])
		var radius_z: float = float(feature["radius_z"])
		var reciprocal_radius_x: float = 1.0 / radius_x
		var reciprocal_radius_z: float = 1.0 / radius_z
		var water_radius: float = float(feature["water_radius"])
		var water_radius_squared: float = water_radius * water_radius
		var hard_rim_radius: float = float(feature["hard_rim_radius"])
		var hard_rim_squared: float = hard_rim_radius * hard_rim_radius
		var inverse_outer_rim_range: float = 1.0 / (1.0 - hard_rim_squared)
		var water_level: int = int(feature["water_level"])
		var water_level_plus_one: int = water_level + 1
		var depth: int = int(feature["depth"])
		var safe_top: int = int(sampler.STAGE2_SAFE_TERRAIN_TOP)
		var feature_min_x: int = maxi(min_x, floori(float(center_x) - radius_x))
		var feature_max_x: int = mini(max_x, ceili(float(center_x) + radius_x))
		var feature_min_z: int = maxi(min_z, floori(float(center_z) - radius_z))
		var feature_max_z: int = mini(max_z, ceili(float(center_z) + radius_z))
		for world_z in range(feature_min_z, feature_max_z + 1):
			var normalized_z: float = float(world_z - center_z) * reciprocal_radius_z
			var normalized_z_squared: float = normalized_z * normalized_z
			var cache_z: int = world_z - min_z
			var row: int = cache_z * width
			for world_x in range(feature_min_x, feature_max_x + 1):
				var normalized_x: float = float(world_x - center_x) * reciprocal_radius_x
				var distance_squared: float = normalized_x * normalized_x + normalized_z_squared
				if distance_squared >= 1.0:
					continue
				var cache_x: int = world_x - min_x
				var index: int = row + cache_x
				var stage5_height: int = int(heights[index])
				if distance_squared <= water_radius_squared:
					var core_t: float = clampf(
						distance_squared / water_radius_squared,
						0.0,
						1.0
					)
					core_t = core_t * core_t * (3.0 - 2.0 * core_t)
					var floor_height: int = (
						water_level
						- 1
						- roundi(float(depth) * (1.0 - core_t))
					)
					heights[index] = clampi(
						mini(stage5_height, floor_height),
						3,
						safe_top
					)
					continue
				if distance_squared <= hard_rim_squared:
					heights[index] = clampi(
						maxi(stage5_height, water_level_plus_one),
						3,
						safe_top
					)
					continue
				if stage5_height >= water_level_plus_one:
					continue
				var rim_t: float = clampf(
					(distance_squared - hard_rim_squared) * inverse_outer_rim_range,
					0.0,
					1.0
				)
				rim_t = rim_t * rim_t * (3.0 - 2.0 * rim_t)
				var blended_rim: int = roundi(lerpf(
					float(water_level_plus_one),
					float(stage5_height),
					rim_t
				))
				heights[index] = clampi(
					maxi(stage5_height, blended_rim),
					3,
					safe_top
				)

	result["heights"] = heights
	return result
