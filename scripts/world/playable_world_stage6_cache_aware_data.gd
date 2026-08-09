extends "res://scripts/world/playable_world_stage6_optimized_data.gd"

# Stage 6 shipping cache helper. When a feature center is already inside the
# padded Stage 5 cache, reuse the exact height plus cached world fields instead
# of sampling that center again. Cached fields are float32; near any acceptance
# boundary this deliberately falls back to the reference candidate path so a
# quantization edge cannot change world topology.
const STAGE6_CACHE_FIELD_STRIDE := 6
const STAGE6_CACHE_FIELD_CONTINENTALNESS := 0
const STAGE6_CACHE_FIELD_STRUCTURE := 1
const STAGE6_CACHE_FIELD_MOISTURE := 5
const STAGE6_CACHE_ACCEPTANCE_EPSILON := 0.00001


func _stage6_cached_center_index(
	center: Vector2i,
	min_x: int,
	min_z: int,
	max_x: int,
	max_z: int,
	width: int
) -> int:
	if center.x < min_x or center.x > max_x or center.y < min_z or center.y > max_z:
		return -1
	return (center.y - min_z) * width + center.x - min_x


func _stage6_cached_candidate_common(
	center: Vector2i,
	center_index: int,
	world_fields: PackedFloat32Array,
	heights: PackedInt32Array,
	radius_max: float,
	inland_min: float,
	max_structure: float,
	accept_roll: float,
	base_chance: float,
	moisture_bonus: float
) -> Dictionary:
	if center_index < 0:
		return {"fallback": true}
	var field_index := center_index * STAGE6_CACHE_FIELD_STRIDE
	if field_index + STAGE6_CACHE_FIELD_MOISTURE >= world_fields.size():
		return {"fallback": true}
	if center_index >= heights.size():
		return {"fallback": true}

	var continentalness := float(
		world_fields[field_index + STAGE6_CACHE_FIELD_CONTINENTALNESS]
	)
	var structure := float(world_fields[field_index + STAGE6_CACHE_FIELD_STRUCTURE])
	var moisture := float(world_fields[field_index + STAGE6_CACHE_FIELD_MOISTURE])
	var chance := _stage6_moisture_chance(moisture, base_chance, moisture_bonus)

	# PackedFloat32 storage differs from the direct double-precision sampler only
	# by tiny quantization. If any decision is close enough that this could matter,
	# use the reference path instead of risking a changed feature boundary.
	if (
		absf(continentalness - inland_min) <= STAGE6_CACHE_ACCEPTANCE_EPSILON
		or absf(structure - max_structure) <= STAGE6_CACHE_ACCEPTANCE_EPSILON
		or absf(accept_roll - chance) <= STAGE6_CACHE_ACCEPTANCE_EPSILON
	):
		return {"fallback": true}
	if continentalness < inland_min:
		return {}
	if accept_roll >= chance:
		return {}
	if structure > max_structure:
		return {}

	var river_value := stage5_river_signal(center.x, center.y)
	var river_clearance := (
		radius_max
		+ STAGE5_VALLEY_OUTER * stage5_river_width_scale(continentalness)
		+ STAGE6_RIVER_CLEARANCE_MARGIN
	)
	if absf(river_value - river_clearance) <= STAGE6_CACHE_ACCEPTANCE_EPSILON:
		return {"fallback": true}
	if river_value <= river_clearance:
		return {}

	var center_height := heights[center_index]
	if center_height < SEA_LEVEL + STAGE6_MIN_WATER_ALTITUDE:
		return {}
	return {
		"continentalness": continentalness,
		"moisture": moisture,
		"structure": structure,
		"center_height": center_height,
	}


func _stage6_cached_lake_candidate(
	cell_x: int,
	cell_z: int,
	center: Vector2i,
	center_index: int,
	world_fields: PackedFloat32Array,
	heights: PackedInt32Array
) -> Dictionary:
	var accept_roll := _stage3_hash01(cell_x, cell_z, STAGE6_LAKE_SALT_ACCEPT)
	var common := _stage6_cached_candidate_common(
		center,
		center_index,
		world_fields,
		heights,
		STAGE6_LAKE_RADIUS_MAX,
		STAGE6_LAKE_INLAND_MIN,
		STAGE6_LAKE_MAX_STRUCTURE,
		accept_roll,
		STAGE6_LAKE_BASE_CHANCE,
		STAGE6_LAKE_MOISTURE_BONUS
	)
	if bool(common.get("fallback", false)):
		return stage6_lake_candidate(cell_x, cell_z)
	if common.is_empty():
		return {}
	var radius_x := lerpf(
		STAGE6_LAKE_RADIUS_MIN,
		STAGE6_LAKE_RADIUS_MAX,
		_stage3_hash01(cell_x, cell_z, STAGE6_LAKE_SALT_RADIUS)
	)
	var aspect := lerpf(
		STAGE6_LAKE_ASPECT_MIN,
		STAGE6_LAKE_ASPECT_MAX,
		_stage3_hash01(cell_x, cell_z, STAGE6_LAKE_SALT_ASPECT)
	)
	var radius_z := radius_x * aspect
	var depth := clampi(
		roundi(lerpf(
			float(STAGE6_LAKE_DEPTH_MIN),
			float(STAGE6_LAKE_DEPTH_MAX),
			_stage3_hash01(cell_x, cell_z, STAGE6_LAKE_SALT_DEPTH)
		)),
		STAGE6_LAKE_DEPTH_MIN,
		STAGE6_LAKE_DEPTH_MAX
	)
	return {
		"type": WATER_LAKE,
		"cell_x": cell_x,
		"cell_z": cell_z,
		"center_x": center.x,
		"center_z": center.y,
		"radius_x": radius_x,
		"radius_z": radius_z,
		"water_radius": STAGE6_LAKE_WATER_RADIUS,
		"hard_rim_radius": STAGE6_LAKE_HARD_RIM_RADIUS,
		"depth": depth,
		"water_level": int(common["center_height"]) - 1,
		"moisture": float(common["moisture"]),
		"structure": float(common["structure"]),
	}


func _stage6_cached_pond_candidate(
	cell_x: int,
	cell_z: int,
	center: Vector2i,
	center_index: int,
	world_fields: PackedFloat32Array,
	heights: PackedInt32Array
) -> Dictionary:
	var accept_roll := _stage3_hash01(cell_x, cell_z, STAGE6_POND_SALT_ACCEPT)
	var common := _stage6_cached_candidate_common(
		center,
		center_index,
		world_fields,
		heights,
		STAGE6_POND_RADIUS_MAX,
		STAGE6_POND_INLAND_MIN,
		STAGE6_POND_MAX_STRUCTURE,
		accept_roll,
		STAGE6_POND_BASE_CHANCE,
		STAGE6_POND_MOISTURE_BONUS
	)
	if bool(common.get("fallback", false)):
		return stage6_pond_candidate(cell_x, cell_z)
	if common.is_empty():
		return {}
	var radius_x := lerpf(
		STAGE6_POND_RADIUS_MIN,
		STAGE6_POND_RADIUS_MAX,
		_stage3_hash01(cell_x, cell_z, STAGE6_POND_SALT_RADIUS)
	)
	var aspect := lerpf(
		STAGE6_POND_ASPECT_MIN,
		STAGE6_POND_ASPECT_MAX,
		_stage3_hash01(cell_x, cell_z, STAGE6_POND_SALT_ASPECT)
	)
	var radius_z := radius_x * aspect
	if _stage6_pond_overlaps_lake(center, radius_x, radius_z):
		return {}
	var depth := clampi(
		roundi(lerpf(
			float(STAGE6_POND_DEPTH_MIN),
			float(STAGE6_POND_DEPTH_MAX),
			_stage3_hash01(cell_x, cell_z, STAGE6_POND_SALT_DEPTH)
		)),
		STAGE6_POND_DEPTH_MIN,
		STAGE6_POND_DEPTH_MAX
	)
	return {
		"type": WATER_POND,
		"cell_x": cell_x,
		"cell_z": cell_z,
		"center_x": center.x,
		"center_z": center.y,
		"radius_x": radius_x,
		"radius_z": radius_z,
		"water_radius": STAGE6_POND_WATER_RADIUS,
		"hard_rim_radius": STAGE6_POND_HARD_RIM_RADIUS,
		"depth": depth,
		"water_level": int(common["center_height"]) - 1,
		"moisture": float(common["moisture"]),
		"structure": float(common["structure"]),
	}


func stage6_collect_features_for_cached_bounds(
	min_x: int,
	min_z: int,
	max_x: int,
	max_z: int,
	width: int,
	world_fields: PackedFloat32Array,
	heights: PackedInt32Array
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
			var center_index := _stage6_cached_center_index(
				center, min_x, min_z, max_x, max_z, width
			)
			var lake := _stage6_cached_lake_candidate(
				cell_x, cell_z, center, center_index, world_fields, heights
			)
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
			var center_index := _stage6_cached_center_index(
				center, min_x, min_z, max_x, max_z, width
			)
			var pond := _stage6_cached_pond_candidate(
				cell_x, cell_z, center, center_index, world_fields, heights
			)
			if not pond.is_empty():
				features.append(pond)
	return features
