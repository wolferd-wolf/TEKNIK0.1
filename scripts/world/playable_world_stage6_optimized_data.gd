extends "res://scripts/world/playable_world_stage6_generation_data.gd"

# Shipping-only Stage 6 lookup optimization. The accepted Stage 6 topology stays
# in playable_world_stage6_generation_data.gd; this subclass preserves that
# exact behavior while rejecting impossible feature cells before terrain/noise
# sampling, reusing candidate-center terrain samples, avoiding full lake
# evaluation for geometrically distant ponds, and skipping feature cells whose
# maximum possible footprint cannot reach the current padded chunk.

func stage6_lake_candidate(cell_x: int, cell_z: int) -> Dictionary:
	# Moisture can raise the accepted probability only as high as base+bonus.
	# If the deterministic roll is already above that ceiling, the reference
	# implementation must reject this cell for every possible moisture value.
	var accept_roll := _stage3_hash01(cell_x, cell_z, STAGE6_LAKE_SALT_ACCEPT)
	if accept_roll >= STAGE6_LAKE_BASE_CHANCE + STAGE6_LAKE_MOISTURE_BONUS:
		return {}
	return super.stage6_lake_candidate(cell_x, cell_z)


func stage6_pond_candidate(cell_x: int, cell_z: int) -> Dictionary:
	var accept_roll := _stage3_hash01(cell_x, cell_z, STAGE6_POND_SALT_ACCEPT)
	if accept_roll >= STAGE6_POND_BASE_CHANCE + STAGE6_POND_MOISTURE_BONUS:
		return {}
	return super.stage6_pond_candidate(cell_x, cell_z)


func _stage6_candidate_common_ok(
	center: Vector2i,
	radius_max: float,
	inland_min: float,
	max_structure: float,
	accept_roll: float,
	base_chance: float,
	moisture_bonus: float
) -> Dictionary:
	var center_xf := float(center.x)
	var center_zf := float(center.y)
	var continentalness: float = continentalness_noise.get_noise_2d(center_xf, center_zf)
	if continentalness < inland_min:
		return {}
	var moisture: float = biome_moisture_noise.get_noise_2d(center_xf, center_zf)
	if accept_roll >= _stage6_moisture_chance(moisture, base_chance, moisture_bonus):
		return {}
	var structure: float = stage3_terrain_structure(center.x, center.y)
	if structure > max_structure:
		return {}
	var river_value := stage5_river_signal(center.x, center.y)
	var river_clearance := (
		radius_max
		+ STAGE5_VALLEY_OUTER * stage5_river_width_scale(continentalness)
		+ STAGE6_RIVER_CLEARANCE_MARGIN
	)
	if river_value <= river_clearance:
		return {}

	# Every accepted Stage 6 feature requires continentalness >= 0.06/0.08,
	# while Stage 4's coast ends at -0.08. Therefore the candidate center is
	# always fully inland: Stage 4 leaves its provisional height unchanged.
	# Reusing the continentalness, structure and river value already sampled
	# above is exactly equivalent to stage6_stage5_height_at(), but avoids the
	# duplicate continentalness/structure/climate/river sampling pass.
	var terrain_fields := Vector4(continentalness, structure, 0.0, 0.0)
	var provisional_height := build_provisional_terrain(terrain_fields)
	var center_height := finalize_height(
		stage5_shape_height_from_signal(
			continentalness,
			provisional_height,
			river_value
		)
	)
	if center_height < SEA_LEVEL + STAGE6_MIN_WATER_ALTITUDE:
		return {}
	return {
		"continentalness": continentalness,
		"moisture": moisture,
		"structure": structure,
		"center_height": center_height,
	}


func _stage6_center_can_reach_bounds(
	center: Vector2i,
	maximum_radius: float,
	min_x: int,
	min_z: int,
	max_x: int,
	max_z: int
) -> bool:
	return not (
		float(center.x) + maximum_radius < float(min_x)
		or float(center.x) - maximum_radius > float(max_x)
		or float(center.y) + maximum_radius < float(min_z)
		or float(center.y) - maximum_radius > float(max_z)
	)


func stage6_collect_features_for_bounds(
	min_x: int,
	min_z: int,
	max_x: int,
	max_z: int
) -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	var lake_min_x := floori(float(min_x) * STAGE6_LAKE_CELL_RECIPROCAL)
	var lake_max_x := floori(float(max_x) * STAGE6_LAKE_CELL_RECIPROCAL)
	var lake_min_z := floori(float(min_z) * STAGE6_LAKE_CELL_RECIPROCAL)
	var lake_max_z := floori(float(max_z) * STAGE6_LAKE_CELL_RECIPROCAL)
	var lake_probability_ceiling := STAGE6_LAKE_BASE_CHANCE + STAGE6_LAKE_MOISTURE_BONUS
	for cell_z in range(lake_min_z, lake_max_z + 1):
		for cell_x in range(lake_min_x, lake_max_x + 1):
			if _stage3_hash01(cell_x, cell_z, STAGE6_LAKE_SALT_ACCEPT) >= lake_probability_ceiling:
				continue
			var center := _stage6_candidate_center(
				cell_x,
				cell_z,
				STAGE6_LAKE_CELL_SPACING,
				STAGE6_LAKE_CELL_HALF,
				STAGE6_LAKE_JITTER,
				STAGE6_LAKE_SALT_X,
				STAGE6_LAKE_SALT_Z
			)
			if not _stage6_center_can_reach_bounds(
				center,
				STAGE6_LAKE_RADIUS_MAX,
				min_x,
				min_z,
				max_x,
				max_z
			):
				continue
			var lake := stage6_lake_candidate(cell_x, cell_z)
			if not lake.is_empty():
				features.append(lake)

	var pond_min_x := floori(float(min_x) * STAGE6_POND_CELL_RECIPROCAL)
	var pond_max_x := floori(float(max_x) * STAGE6_POND_CELL_RECIPROCAL)
	var pond_min_z := floori(float(min_z) * STAGE6_POND_CELL_RECIPROCAL)
	var pond_max_z := floori(float(max_z) * STAGE6_POND_CELL_RECIPROCAL)
	var pond_probability_ceiling := STAGE6_POND_BASE_CHANCE + STAGE6_POND_MOISTURE_BONUS
	for cell_z in range(pond_min_z, pond_max_z + 1):
		for cell_x in range(pond_min_x, pond_max_x + 1):
			if _stage3_hash01(cell_x, cell_z, STAGE6_POND_SALT_ACCEPT) >= pond_probability_ceiling:
				continue
			var center := _stage6_candidate_center(
				cell_x,
				cell_z,
				STAGE6_POND_CELL_SPACING,
				STAGE6_POND_CELL_HALF,
				STAGE6_POND_JITTER,
				STAGE6_POND_SALT_X,
				STAGE6_POND_SALT_Z
			)
			if not _stage6_center_can_reach_bounds(
				center,
				STAGE6_POND_RADIUS_MAX,
				min_x,
				min_z,
				max_x,
				max_z
			):
				continue
			var pond := stage6_pond_candidate(cell_x, cell_z)
			if not pond.is_empty():
				features.append(pond)
	return features


func _stage6_pond_overlaps_lake(
	center: Vector2i,
	radius_x: float,
	radius_z: float
) -> bool:
	var lake_cell_x := floori(float(center.x) * STAGE6_LAKE_CELL_RECIPROCAL)
	var lake_cell_z := floori(float(center.y) * STAGE6_LAKE_CELL_RECIPROCAL)
	var pond_radius := maxf(radius_x, radius_z)
	var maximum_separation := (
		pond_radius
		+ STAGE6_LAKE_RADIUS_MAX
		+ STAGE6_FEATURE_SEPARATION_MARGIN
	)
	var maximum_separation_squared := maximum_separation * maximum_separation
	for offset_z in range(-1, 2):
		for offset_x in range(-1, 2):
			var candidate_cell_x := lake_cell_x + offset_x
			var candidate_cell_z := lake_cell_z + offset_z
			var candidate_center := _stage6_candidate_center(
				candidate_cell_x,
				candidate_cell_z,
				STAGE6_LAKE_CELL_SPACING,
				STAGE6_LAKE_CELL_HALF,
				STAGE6_LAKE_JITTER,
				STAGE6_LAKE_SALT_X,
				STAGE6_LAKE_SALT_Z
			)
			var coarse_dx := float(center.x - candidate_center.x)
			var coarse_dz := float(center.y - candidate_center.y)
			if coarse_dx * coarse_dx + coarse_dz * coarse_dz >= maximum_separation_squared:
				continue
			var lake := stage6_lake_candidate(candidate_cell_x, candidate_cell_z)
			if lake.is_empty():
				continue
			var dx := float(center.x - int(lake["center_x"]))
			var dz := float(center.y - int(lake["center_z"]))
			var lake_radius := maxf(float(lake["radius_x"]), float(lake["radius_z"]))
			var separation := pond_radius + lake_radius + STAGE6_FEATURE_SEPARATION_MARGIN
			if dx * dx + dz * dz < separation * separation:
				return true
	return false
