extends RefCounted

const STAGE10_CACHE := preload("res://scripts/world/playable_world_stage10_generation_cache_fast.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := CHUNK_SIZE + PADDING * 2
const FIELD_STRIDE := 6

# Stage 8 ecology envelope and Stage 9 modifier constants, frozen from the
# accepted Stage 10 cache. Stage 13 changes river geography only.
const PLAINS_FOREST_MOISTURE_BOUNDARY := 0.18
const DENSE_FOREST_ENVELOPE_START := 0.348326996197719
const FOREST_ENVELOPE_END := 0.671395348837208
const HILL_START := -0.28
const PLATEAU_START := 0.22
const MOUNTAIN_START := 0.34
const MOUNTAIN_FULL := 0.68
const MOUNTAIN_RANGE_RECIPROCAL := 2.9411764705882353
const VALLEY_MIN := 0.22
const MODIFIER_NONE := 0
const MODIFIER_HILL := 1
const MODIFIER_PLATEAU := 2
const MODIFIER_MOUNTAIN := 3
const MODIFIER_VALLEY := 4


static func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func build(coord: Vector2i, sampler) -> Dictionary:
	# Reuse Stage 10's highly optimized noise/warp field production. Stage 13 then
	# rebuilds only the cheap scalar terrain/hydrology/ecology pass from those
	# cached fields, replacing periodic rivers with independent lane centerlines.
	var stage10: Dictionary = STAGE10_CACHE.build(coord, sampler)
	var fields: PackedFloat32Array = stage10.get("world_fields", PackedFloat32Array())
	if fields.is_empty():
		return stage10

	var count := WIDTH * WIDTH
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	var water_types := PackedByteArray()
	var modifiers := PackedByteArray()
	heights.resize(count)
	biomes.resize(count)
	water_types.resize(count)
	modifiers.resize(count)

	var min_x := coord.x * CHUNK_SIZE - PADDING
	var min_z := coord.y * CHUNK_SIZE - PADDING
	var max_x := min_x + WIDTH - 1
	var max_z := min_z + WIDTH - 1

	# Stage 2 constants.
	var continental_base: float = sampler.STAGE2_CONTINENTAL_BASE_HEIGHT
	var continental_scale: float = sampler.STAGE2_CONTINENTAL_HEIGHT_SCALE
	var shelf_start: float = sampler.STAGE2_OCEAN_SHELF_START
	var basin_full: float = sampler.STAGE2_OCEAN_BASIN_FULL
	var basin_depth: float = sampler.STAGE2_OCEAN_BASIN_DEPTH
	var rolling_start: float = sampler.STAGE2_ROLLING_START
	var plains_end: float = sampler.STAGE2_PLAINS_END
	var rolling_end: float = sampler.STAGE2_ROLLING_END
	var mountain_start: float = sampler.STAGE2_MOUNTAIN_START
	var mountain_full: float = sampler.STAGE2_MOUNTAIN_FULL
	var rolling_rise: float = sampler.STAGE2_ROLLING_RISE
	var upland_rise: float = sampler.STAGE2_UPLAND_RISE
	var mountain_base_rise: float = sampler.STAGE2_MOUNTAIN_BASE_RISE
	var mountain_ridge_rise: float = sampler.STAGE2_MOUNTAIN_RIDGE_RISE
	var valley_cut: float = sampler.STAGE2_VALLEY_CUT
	var safe_top: int = sampler.STAGE2_SAFE_TERRAIN_TOP
	var basin_reciprocal := 1.0 / (shelf_start - basin_full)
	var plains_blend_reciprocal := 1.0 / (plains_end - rolling_start)
	var upland_blend_reciprocal := 1.0 / (mountain_start - rolling_end)
	var mountain_blend_reciprocal := 1.0 / (mountain_full - mountain_start)

	# Stage 4 ocean constants.
	var ocean_start: float = sampler.STAGE4_OCEAN_WATER_START
	var ocean_full: float = sampler.STAGE4_OCEAN_BASIN_FULL
	var coast_end: float = sampler.STAGE4_COAST_INLAND_END
	var ocean_edge_floor: int = sampler.STAGE4_OCEAN_EDGE_FLOOR
	var ocean_core_floor: int = sampler.STAGE4_OCEAN_CORE_FLOOR
	var sea_level: int = sampler.SEA_LEVEL
	var ocean_reciprocal := 1.0 / (ocean_start - ocean_full)
	var coast_reciprocal := 1.0 / (coast_end - ocean_start)

	# Stage 13 river layout + accepted Stage 5 shaping constants.
	var river_spacing: float = sampler.STAGE5_RIVER_SPACING
	var river_diagonal_slope: float = sampler.STAGE5_RIVER_DIAGONAL_SLOPE
	var channel_inner: float = sampler.STAGE5_CHANNEL_INNER
	var channel_outer: float = sampler.STAGE5_CHANNEL_OUTER
	var channel_cutoff: float = sampler.STAGE5_CHANNEL_WATER_CUTOFF
	var valley_inner: float = sampler.STAGE5_VALLEY_INNER
	var valley_outer: float = sampler.STAGE5_VALLEY_OUTER
	var coast_width: float = sampler.STAGE5_COAST_WIDTH_SCALE
	var inland_width: float = sampler.STAGE5_INLAND_WIDTH_SCALE
	var width_range: float = sampler.STAGE5_WIDTH_CONTINENTAL_RANGE
	var max_carve: int = sampler.STAGE5_MAX_VALLEY_CARVE
	var channel_depth: int = sampler.STAGE5_CHANNEL_DEPTH
	var relief_fraction: float = sampler.STAGE5_VALLEY_RELIEF_FRACTION
	var river_early_out: float = valley_outer * coast_width

	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_dense: int = sampler.BIOME_DENSE_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_dry: int = sampler.BIOME_DRY_GRASSLAND
	var biome_cold: int = sampler.BIOME_COLD_FOREST
	var water_none: int = sampler.WATER_NONE
	var water_ocean: int = sampler.WATER_OCEAN
	var water_river: int = sampler.WATER_RIVER

	var chunk_mid_x := float(min_x) + float(WIDTH - 1) * 0.5
	for cz in range(WIDTH):
		var world_z := min_z + cz
		var zf := float(world_z)
		var lane_estimate := roundi(
			(chunk_mid_x + zf * river_diagonal_slope) / river_spacing
		)
		var best_center := 0.0
		var best_mid_distance := INF
		for lane_index in range(lane_estimate - 1, lane_estimate + 2):
			var center_x: float = sampler.stage13_river_center_x(lane_index, zf)
			var mid_distance := absf(chunk_mid_x - center_x)
			if mid_distance < best_mid_distance:
				best_mid_distance = mid_distance
				best_center = center_x
		var center_local := best_center - float(min_x)
		var river_active_min := maxi(0, ceili(center_local - river_early_out))
		var river_active_max := mini(WIDTH - 1, floori(center_local + river_early_out))
		var row := cz * WIDTH

		for cx in range(WIDTH):
			var column := row + cx
			var field := column * FIELD_STRIDE
			var continentalness := float(fields[field])
			var structure := float(fields[field + 1])
			var temperature := float(fields[field + 2])
			var moisture := float(fields[field + 3])

			# Exact Stage 2 scalar shaping from accepted Stage 10.
			var c := clampf(continentalness, -1.0, 1.0)
			var s := clampf(structure, -1.0, 1.0)
			var shaped_continent := c * 0.35 + c * c * c * 0.65
			var base_height := continental_base + shaped_continent * continental_scale
			if c < shelf_start:
				var basin_t := clampf((shelf_start - c) * basin_reciprocal, 0.0, 1.0)
				basin_t = _smooth(basin_t)
				base_height -= basin_t * basin_depth
			var rolling_target := base_height + 2.0 + absf(c) * rolling_rise
			var height: int
			if s <= rolling_start:
				height = clampi(roundi(base_height), 3, safe_top)
			elif s < plains_end:
				var terrain_t := _smooth((s - rolling_start) * plains_blend_reciprocal)
				height = clampi(roundi(lerpf(base_height, rolling_target, terrain_t)), 3, safe_top)
			elif s <= rolling_end:
				height = clampi(roundi(rolling_target), 3, safe_top)
			else:
				var upland_target := base_height + 6.0 + upland_rise
				if s < mountain_start:
					var terrain_t := _smooth((s - rolling_end) * upland_blend_reciprocal)
					height = clampi(roundi(lerpf(rolling_target, upland_target, terrain_t)), 3, safe_top)
				else:
					var ridge_base := 1.0 - absf(c)
					var ridge := ridge_base * ridge_base
					var mountain_target := (
						base_height + mountain_base_rise + ridge * mountain_ridge_rise
						- (1.0 - ridge) * valley_cut
					)
					if s < mountain_full:
						var terrain_t := _smooth((s - mountain_start) * mountain_blend_reciprocal)
						height = clampi(roundi(lerpf(upland_target, mountain_target, terrain_t)), 3, safe_top)
					else:
						height = clampi(roundi(mountain_target), 3, safe_top)

			# Stage 4 ocean/coast shaping.
			var water_type := water_none
			if continentalness <= ocean_start:
				var ocean_t := _smooth((ocean_start - continentalness) * ocean_reciprocal)
				var ocean_floor := roundi(
					float(ocean_edge_floor) + float(ocean_core_floor - ocean_edge_floor) * ocean_t
				)
				height = mini(height, ocean_floor)
				if height < sea_level:
					water_type = water_ocean
			elif continentalness < coast_end:
				var inland_t := _smooth((continentalness - ocean_start) * coast_reciprocal)
				height = roundi(float(sea_level) + float(height - sea_level) * inland_t)

			# Stage 13 lane-independent river layout, Stage 5 shaping contract.
			if continentalness > ocean_start and cx >= river_active_min and cx <= river_active_max:
				var river_value := absf(float(cx) - center_local)
				var width_t := _smooth((continentalness - ocean_start) / width_range)
				var width_scale := coast_width + (inland_width - coast_width) * width_t
				var scaled_distance := river_value / width_scale
				if scaled_distance < valley_outer:
					var valley_t := _smooth(
						(scaled_distance - valley_inner) / (valley_outer - valley_inner)
					)
					var valley_strength := 1.0 - valley_t
					var relief := maxi(0, height - sea_level)
					var valley_drop := mini(max_carve, maxi(2, roundi(float(relief) * relief_fraction)))
					var valley_floor := maxi(sea_level, height - valley_drop)
					height = roundi(float(height) + float(valley_floor - height) * valley_strength)
					if scaled_distance < channel_outer:
						var channel_t := _smooth(
							(scaled_distance - channel_inner) / (channel_outer - channel_inner)
						)
						var channel_strength := 1.0 - channel_t
						var channel_floor := maxi(sea_level - 1, height - channel_depth)
						height = roundi(float(height) + float(channel_floor - height) * channel_strength)
						if channel_strength >= channel_cutoff:
							water_type = water_river
				height = clampi(height, 3, safe_top)
			heights[column] = height
			water_types[column] = water_type

			# Exact Stage 8 ecology classification.
			if water_type != water_none:
				biomes[column] = biome_plains
				modifiers[column] = MODIFIER_NONE
				continue
			var biome: int
			if moisture <= PLAINS_FOREST_MOISTURE_BOUNDARY:
				if 1.04 * temperature < 0.72 * moisture - 0.3856:
					biome = biome_cold
				elif 0.80 * temperature <= 0.44 * moisture + 0.2172:
					biome = biome_plains
				elif 0.52 * temperature >= 0.72 * moisture + 0.578:
					biome = biome_desert
				else:
					biome = biome_dry
			elif moisture < DENSE_FOREST_ENVELOPE_START:
				if 1.04 * temperature < -0.08 * moisture - 0.2416:
					biome = biome_cold
				elif 0.80 * temperature > 1.24 * moisture + 0.0732:
					biome = biome_dry
				else:
					biome = biome_forest
			elif moisture <= FOREST_ENVELOPE_END:
				if 1.04 * temperature < -0.08 * moisture - 0.2416:
					biome = biome_cold
				elif 0.24 * temperature <= 0.3884 - 0.68 * moisture:
					biome = biome_forest
				elif 0.56 * temperature > 1.92 * moisture - 0.3152:
					biome = biome_dry
				else:
					biome = biome_dense
			else:
				if 1.28 * temperature + 0.76 * moisture - 0.1468 < 0.0:
					biome = biome_cold
				elif 0.56 * temperature > 1.92 * moisture - 0.3152:
					biome = biome_dry
				else:
					biome = biome_dense
			biomes[column] = biome

			var modifier := MODIFIER_NONE
			if structure >= MOUNTAIN_START:
				var mountain_strength := 1.0
				if structure < MOUNTAIN_FULL:
					var mountain_t := _smooth((structure - MOUNTAIN_START) * MOUNTAIN_RANGE_RECIPROCAL)
					mountain_strength = mountain_t
				var ridge_base := 1.0 - absf(continentalness)
				var ridge := ridge_base * ridge_base
				var modifier_valley_strength := mountain_strength * (1.0 - ridge)
				modifier = MODIFIER_VALLEY if modifier_valley_strength >= VALLEY_MIN else MODIFIER_MOUNTAIN
			elif structure >= PLATEAU_START:
				modifier = MODIFIER_PLATEAU
			elif structure >= HILL_START:
				modifier = MODIFIER_HILL
			modifiers[column] = modifier

	# Re-run Stage 6 sparse feature discovery against the corrected Stage 13 river
	# terrain, then apply exactly the accepted lake/pond basin/rim shaping.
	var features: Array[Dictionary] = sampler.stage6_collect_features_for_cached_bounds(
		min_x, min_z, max_x, max_z, WIDTH, fields, heights
	)
	for feature in features:
		var center_x: int = int(feature["center_x"])
		var center_z: int = int(feature["center_z"])
		var radius_x: float = float(feature["radius_x"])
		var radius_z: float = float(feature["radius_z"])
		var reciprocal_radius_x := 1.0 / radius_x
		var reciprocal_radius_z := 1.0 / radius_z
		var water_radius: float = float(feature["water_radius"])
		var water_radius_squared := water_radius * water_radius
		var hard_rim_radius: float = float(feature["hard_rim_radius"])
		var hard_rim_squared := hard_rim_radius * hard_rim_radius
		var inverse_outer_rim_range := 1.0 / (1.0 - hard_rim_squared)
		var water_level: int = int(feature["water_level"])
		var water_level_plus_one := water_level + 1
		var depth: int = int(feature["depth"])
		var feature_type: int = int(feature["type"])
		var feature_min_x := maxi(min_x, floori(float(center_x) - radius_x))
		var feature_max_x := mini(max_x, ceili(float(center_x) + radius_x))
		var feature_min_z := maxi(min_z, floori(float(center_z) - radius_z))
		var feature_max_z := mini(max_z, ceili(float(center_z) + radius_z))
		for world_z in range(feature_min_z, feature_max_z + 1):
			var normalized_z := float(world_z - center_z) * reciprocal_radius_z
			var normalized_z_squared := normalized_z * normalized_z
			var row := (world_z - min_z) * WIDTH
			for world_x in range(feature_min_x, feature_max_x + 1):
				var normalized_x := float(world_x - center_x) * reciprocal_radius_x
				var distance_squared := normalized_x * normalized_x + normalized_z_squared
				if distance_squared >= 1.0:
					continue
				var index := row + world_x - min_x
				var stage5_height := int(heights[index])
				if distance_squared <= water_radius_squared:
					var core_t := _smooth(distance_squared / water_radius_squared)
					var floor_height := water_level - 1 - roundi(float(depth) * (1.0 - core_t))
					heights[index] = clampi(mini(stage5_height, floor_height), 3, safe_top)
					water_types[index] = feature_type
					biomes[index] = biome_plains
					modifiers[index] = MODIFIER_NONE
					continue
				if distance_squared <= hard_rim_squared:
					heights[index] = clampi(maxi(stage5_height, water_level_plus_one), 3, safe_top)
					continue
				if stage5_height >= water_level_plus_one:
					continue
				var rim_t := _smooth(
					(distance_squared - hard_rim_squared) * inverse_outer_rim_range
				)
				var blended_rim := roundi(lerpf(
					float(water_level_plus_one), float(stage5_height), rim_t
				))
				heights[index] = clampi(maxi(stage5_height, blended_rim), 3, safe_top)

	return {
		"world_fields": fields,
		"heights": heights,
		"biomes": biomes,
		"stage7_water_types": water_types,
		"stage6_features": features,
		"stage8_active_biome_count": sampler.STAGE8_ACTIVE_BIOME_COUNT,
		"stage9_terrain_modifiers": modifiers,
		"stage9_terrain_modifier_count": sampler.STAGE9_TERRAIN_MODIFIER_COUNT,
	}
