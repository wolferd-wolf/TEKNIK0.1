extends RefCounted

const STAGE6_CACHE := preload("res://scripts/world/playable_world_stage6_generation_cache_fast.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := CHUNK_SIZE + PADDING * 2
const FIELD_STRIDE := 6


static func _smooth01(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _distance_sq(
	temperature: float,
	moisture: float,
	target: Vector2
) -> float:
	var dx: float = temperature - target.x
	var dy: float = moisture - target.y
	return dx * dx + dy * dy


static func _feature_water_type_at(
	world_x: int,
	world_z: int,
	features: Array
) -> int:
	for raw_feature in features:
		var feature: Dictionary = raw_feature
		var radius_x: float = float(feature["radius_x"])
		var radius_z: float = float(feature["radius_z"])
		var dx: float = float(world_x - int(feature["center_x"])) / radius_x
		var dz: float = float(world_z - int(feature["center_z"])) / radius_z
		var water_radius: float = float(feature["water_radius"])
		if dx * dx + dz * dz <= water_radius * water_radius:
			return int(feature["type"])
	return 0


static func build(coord: Vector2i, sampler) -> Dictionary:
	var result: Dictionary = STAGE6_CACHE.build(coord, sampler)
	var heights: PackedInt32Array = result.get("heights", PackedInt32Array())
	var fields: PackedFloat32Array = result.get("world_fields", PackedFloat32Array())
	if heights.size() != WIDTH * WIDTH or fields.size() != WIDTH * WIDTH * FIELD_STRIDE:
		return result

	var biomes := PackedByteArray()
	var water_types := PackedByteArray()
	var slopes := PackedFloat32Array()
	var mountain_strengths := PackedFloat32Array()
	var coast_proximity := PackedFloat32Array()
	biomes.resize(WIDTH * WIDTH)
	water_types.resize(WIDTH * WIDTH)
	slopes.resize(WIDTH * WIDTH)
	mountain_strengths.resize(WIDTH * WIDTH)
	coast_proximity.resize(WIDTH * WIDTH)

	var features: Array = result.get("stage6_features", [])
	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING

	# River row values reuse the accepted Stage 5 graph formula. One meander is
	# evaluated per Z row; individual columns only pay a periodic-distance check.
	var river_spacing: float = sampler.STAGE5_RIVER_SPACING
	var river_half_spacing: float = sampler.STAGE5_RIVER_HALF_SPACING
	var river_diagonal_slope: float = sampler.STAGE5_RIVER_DIAGONAL_SLOPE
	var river_meander_amplitude: float = sampler.STAGE5_RIVER_MEANDER_AMPLITUDE
	var river_width_range: float = sampler.STAGE5_WIDTH_CONTINENTAL_RANGE
	var river_coast_width: float = sampler.STAGE5_COAST_WIDTH_SCALE
	var river_inland_width: float = sampler.STAGE5_INLAND_WIDTH_SCALE
	var channel_inner: float = sampler.STAGE5_CHANNEL_INNER
	var channel_outer: float = sampler.STAGE5_CHANNEL_OUTER
	var channel_cutoff: float = sampler.STAGE5_CHANNEL_WATER_CUTOFF
	var ocean_start: float = sampler.STAGE4_OCEAN_WATER_START
	var coast_end: float = sampler.STAGE4_COAST_INLAND_END
	var sea_level: int = sampler.SEA_LEVEL

	var mountain_start: float = sampler.STAGE2_MOUNTAIN_START
	var mountain_range_reciprocal: float = 1.0 / (
		sampler.STAGE2_MOUNTAIN_FULL - sampler.STAGE2_MOUNTAIN_START
	)

	var plains_target: Vector2 = sampler.STAGE7_PLAINS_TARGET
	var forest_target: Vector2 = sampler.STAGE7_FOREST_TARGET
	var desert_target: Vector2 = sampler.STAGE7_DESERT_TARGET
	var rocky_target: Vector2 = sampler.STAGE7_ROCKY_TARGET
	var rocky_strength_min: float = sampler.STAGE7_ROCKY_MOUNTAIN_STRENGTH_MIN
	var rocky_elevation_min: int = sampler.STAGE7_ROCKY_ELEVATION_MIN
	var rocky_coast_max: float = sampler.STAGE7_ROCKY_COAST_PROXIMITY_MAX
	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_rocky: int = sampler.BIOME_ROCKY

	for cz in range(WIDTH):
		var world_z: int = min_z + cz
		var zf: float = float(world_z)
		var river_meander: float = sampler.stage5_meander_at(zf)
		var river_row_phase: float = (
			zf * river_diagonal_slope + river_meander * river_meander_amplitude
		)
		for cx in range(WIDTH):
			var world_x: int = min_x + cx
			var index: int = cz * WIDTH + cx
			var field_index: int = index * FIELD_STRIDE
			var continentalness: float = fields[field_index]
			var structure: float = fields[field_index + 1]
			var temperature: float = fields[field_index + 2]
			var moisture: float = fields[field_index + 3]
			var height: int = heights[index]

			var mountain_strength: float = _smooth01(
				(structure - mountain_start) * mountain_range_reciprocal
			)
			mountain_strengths[index] = mountain_strength

			var coast: float = 0.0
			if continentalness <= ocean_start:
				coast = 1.0
			elif continentalness < coast_end:
				coast = 1.0 - _smooth01(
					(continentalness - ocean_start) / (coast_end - ocean_start)
				)
			coast_proximity[index] = coast

			# Local cardinal slope from the padded cache. It is exported as Stage 7
			# context for later terrain modifiers but does not alter the transitional
			# four-biome ecology selection, so outer-halo one-sided sampling cannot
			# create biome seams.
			var local_slope: int = 0
			if cx > 0:
				local_slope = maxi(local_slope, absi(heights[index - 1] - height))
			if cx + 1 < WIDTH:
				local_slope = maxi(local_slope, absi(heights[index + 1] - height))
			if cz > 0:
				local_slope = maxi(local_slope, absi(heights[index - WIDTH] - height))
			if cz + 1 < WIDTH:
				local_slope = maxi(local_slope, absi(heights[index + WIDTH] - height))
			slopes[index] = float(local_slope)

			var water_type: int = sampler.WATER_NONE
			if continentalness <= ocean_start and height < sea_level:
				water_type = sampler.WATER_OCEAN
			else:
				var river_position: float = float(world_x) + river_row_phase
				var river_distance: float = absf(
					fposmod(river_position + river_half_spacing, river_spacing)
					- river_half_spacing
				)
				var width_t: float = _smooth01(
					(continentalness - ocean_start) / river_width_range
				)
				var width_scale: float = lerpf(river_coast_width, river_inland_width, width_t)
				var scaled_distance: float = river_distance / width_scale
				if scaled_distance < channel_outer:
					var channel_t: float = clampf(
						(scaled_distance - channel_inner) / (channel_outer - channel_inner),
						0.0,
						1.0
					)
					channel_t = channel_t * channel_t * (3.0 - 2.0 * channel_t)
					if 1.0 - channel_t >= channel_cutoff:
						water_type = sampler.WATER_RIVER
				if water_type == sampler.WATER_NONE and not features.is_empty():
					water_type = _feature_water_type_at(world_x, world_z, features)
			water_types[index] = water_type

			if water_type != sampler.WATER_NONE:
				biomes[index] = biome_plains
				continue

			var best_biome: int = biome_plains
			var best_distance: float = _distance_sq(temperature, moisture, plains_target)
			var forest_distance: float = _distance_sq(temperature, moisture, forest_target)
			if forest_distance < best_distance:
				best_biome = biome_forest
				best_distance = forest_distance
			var desert_distance: float = _distance_sq(temperature, moisture, desert_target)
			if desert_distance < best_distance:
				best_biome = biome_desert
				best_distance = desert_distance
			if (
				coast <= rocky_coast_max
				and (mountain_strength >= rocky_strength_min or height >= rocky_elevation_min)
			):
				var rocky_distance: float = _distance_sq(temperature, moisture, rocky_target)
				if rocky_distance < best_distance:
					best_biome = biome_rocky
			biomes[index] = best_biome

	result["biomes"] = biomes
	result["stage7_water_types"] = water_types
	result["stage7_slopes"] = slopes
	result["stage7_mountain_strengths"] = mountain_strengths
	result["stage7_coast_proximity"] = coast_proximity
	return result