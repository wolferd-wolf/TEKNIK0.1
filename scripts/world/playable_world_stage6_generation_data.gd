extends "res://scripts/world/playable_world_stage5_generation_data.gd"

# Stage 6 adds sparse deterministic surface basins. These are feature placements,
# not an aquifer or watershed simulation: each accepted inland candidate owns a
# contained elliptical basin, a local water level and a narrow dry rim.
#
# The feature cells are deliberately much larger than chunks and every feature
# remains inside its own feature cell. Therefore direct world queries and chunk
# caches agree without any global mutable state or cross-chunk coordination.
const WATER_LAKE := 3
const WATER_POND := 4

const STAGE6_LAKE_CELL_SPACING := 128
const STAGE6_LAKE_CELL_RECIPROCAL := 1.0 / 128.0
const STAGE6_LAKE_CELL_HALF := 64
const STAGE6_LAKE_JITTER := 24.0
const STAGE6_LAKE_RADIUS_MIN := 14.0
const STAGE6_LAKE_RADIUS_MAX := 24.0
const STAGE6_LAKE_ASPECT_MIN := 0.72
const STAGE6_LAKE_ASPECT_MAX := 1.00
const STAGE6_LAKE_WATER_RADIUS := 0.70
const STAGE6_LAKE_HARD_RIM_RADIUS := 0.82
const STAGE6_LAKE_DEPTH_MIN := 2
const STAGE6_LAKE_DEPTH_MAX := 5
const STAGE6_LAKE_BASE_CHANCE := 0.18
const STAGE6_LAKE_MOISTURE_BONUS := 0.14
const STAGE6_LAKE_MAX_STRUCTURE := 0.30
const STAGE6_LAKE_INLAND_MIN := 0.06

const STAGE6_POND_CELL_SPACING := 64
const STAGE6_POND_CELL_RECIPROCAL := 1.0 / 64.0
const STAGE6_POND_CELL_HALF := 32
const STAGE6_POND_JITTER := 12.0
const STAGE6_POND_RADIUS_MIN := 4.0
const STAGE6_POND_RADIUS_MAX := 8.0
const STAGE6_POND_ASPECT_MIN := 0.78
const STAGE6_POND_ASPECT_MAX := 1.00
const STAGE6_POND_WATER_RADIUS := 0.64
const STAGE6_POND_HARD_RIM_RADIUS := 0.82
const STAGE6_POND_DEPTH_MIN := 1
const STAGE6_POND_DEPTH_MAX := 2
const STAGE6_POND_BASE_CHANCE := 0.16
const STAGE6_POND_MOISTURE_BONUS := 0.12
const STAGE6_POND_MAX_STRUCTURE := 0.34
const STAGE6_POND_INLAND_MIN := 0.08

const STAGE6_RIVER_CLEARANCE_MARGIN := 4.0
const STAGE6_FEATURE_SEPARATION_MARGIN := 5.0
const STAGE6_MIN_WATER_ALTITUDE := 2

const STAGE6_LAKE_SALT_X := 0x11f31a29
const STAGE6_LAKE_SALT_Z := 0x52a70f6d
const STAGE6_LAKE_SALT_ACCEPT := 0x74c2859b
const STAGE6_LAKE_SALT_RADIUS := 0x2bd91e43
const STAGE6_LAKE_SALT_ASPECT := 0x4e6b3175
const STAGE6_LAKE_SALT_DEPTH := 0x6c8d24af
const STAGE6_POND_SALT_X := 0x1ad7c593
const STAGE6_POND_SALT_Z := 0x3f64a82d
const STAGE6_POND_SALT_ACCEPT := 0x5b91e347
const STAGE6_POND_SALT_RADIUS := 0x7892bc15
const STAGE6_POND_SALT_ASPECT := 0x27e4d0b9
const STAGE6_POND_SALT_DEPTH := 0x63a14f2b


func _stage6_candidate_center(
	cell_x: int,
	cell_z: int,
	spacing: int,
	half_spacing: int,
	jitter: float,
	salt_x: int,
	salt_z: int
) -> Vector2i:
	var offset_x := roundi((_stage3_hash01(cell_x, cell_z, salt_x) * 2.0 - 1.0) * jitter)
	var offset_z := roundi((_stage3_hash01(cell_x, cell_z, salt_z) * 2.0 - 1.0) * jitter)
	return Vector2i(
		cell_x * spacing + half_spacing + offset_x,
		cell_z * spacing + half_spacing + offset_z
	)


func _stage6_moisture_chance(
	moisture: float,
	base_chance: float,
	moisture_bonus: float
) -> float:
	# Moisture increases probability but never directly commands a basin.
	var moisture01 := clampf((moisture + 1.0) * 0.5, 0.0, 1.0)
	return base_chance + moisture01 * moisture_bonus


func stage6_stage5_height_at(x: int, z: int) -> int:
	# Do not call the parent terrain_height() implementation here. Its internal
	# unqualified apply_water_topology() call can dispatch back into Stage 6.
	# Calling the immediate parent's topology method directly keeps the dependency
	# graph acyclic: fields -> provisional terrain -> Stage 5 hydrology -> height.
	var fields := sample_world_fields(x, z)
	var provisional_height := build_provisional_terrain(fields)
	var stage5_height := super.apply_water_topology(fields, provisional_height, x, z)
	return finalize_height(stage5_height)


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
	var river_clearance := (
		radius_max
		+ STAGE5_VALLEY_OUTER * stage5_river_width_scale(continentalness)
		+ STAGE6_RIVER_CLEARANCE_MARGIN
	)
	if stage5_river_signal(center.x, center.y) <= river_clearance:
		return {}
	var center_height: int = stage6_stage5_height_at(center.x, center.y)
	if center_height < SEA_LEVEL + STAGE6_MIN_WATER_ALTITUDE:
		return {}
	return {
		"continentalness": continentalness,
		"moisture": moisture,
		"structure": structure,
		"center_height": center_height,
	}


func stage6_lake_candidate(cell_x: int, cell_z: int) -> Dictionary:
	var center := _stage6_candidate_center(
		cell_x,
		cell_z,
		STAGE6_LAKE_CELL_SPACING,
		STAGE6_LAKE_CELL_HALF,
		STAGE6_LAKE_JITTER,
		STAGE6_LAKE_SALT_X,
		STAGE6_LAKE_SALT_Z
	)
	var accept_roll := _stage3_hash01(cell_x, cell_z, STAGE6_LAKE_SALT_ACCEPT)
	var common := _stage6_candidate_common_ok(
		center,
		STAGE6_LAKE_RADIUS_MAX,
		STAGE6_LAKE_INLAND_MIN,
		STAGE6_LAKE_MAX_STRUCTURE,
		accept_roll,
		STAGE6_LAKE_BASE_CHANCE,
		STAGE6_LAKE_MOISTURE_BONUS
	)
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
	var water_level := int(common["center_height"]) - 1
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
		"water_level": water_level,
		"moisture": float(common["moisture"]),
		"structure": float(common["structure"]),
	}


func _stage6_pond_overlaps_lake(
	center: Vector2i,
	radius_x: float,
	radius_z: float
) -> bool:
	var lake_cell_x := floori(float(center.x) * STAGE6_LAKE_CELL_RECIPROCAL)
	var lake_cell_z := floori(float(center.y) * STAGE6_LAKE_CELL_RECIPROCAL)
	var pond_radius := maxf(radius_x, radius_z)
	for offset_z in range(-1, 2):
		for offset_x in range(-1, 2):
			var lake := stage6_lake_candidate(
				lake_cell_x + offset_x,
				lake_cell_z + offset_z
			)
			if lake.is_empty():
				continue
			var dx := float(center.x - int(lake["center_x"]))
			var dz := float(center.y - int(lake["center_z"]))
			var lake_radius := maxf(float(lake["radius_x"]), float(lake["radius_z"]))
			var separation := pond_radius + lake_radius + STAGE6_FEATURE_SEPARATION_MARGIN
			if dx * dx + dz * dz < separation * separation:
				return true
	return false


func stage6_pond_candidate(cell_x: int, cell_z: int) -> Dictionary:
	var center := _stage6_candidate_center(
		cell_x,
		cell_z,
		STAGE6_POND_CELL_SPACING,
		STAGE6_POND_CELL_HALF,
		STAGE6_POND_JITTER,
		STAGE6_POND_SALT_X,
		STAGE6_POND_SALT_Z
	)
	var accept_roll := _stage3_hash01(cell_x, cell_z, STAGE6_POND_SALT_ACCEPT)
	var common := _stage6_candidate_common_ok(
		center,
		STAGE6_POND_RADIUS_MAX,
		STAGE6_POND_INLAND_MIN,
		STAGE6_POND_MAX_STRUCTURE,
		accept_roll,
		STAGE6_POND_BASE_CHANCE,
		STAGE6_POND_MOISTURE_BONUS
	)
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
	var water_level := int(common["center_height"]) - 1
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
		"water_level": water_level,
		"moisture": float(common["moisture"]),
		"structure": float(common["structure"]),
	}


func stage6_feature_distance_squared(x: int, z: int, feature: Dictionary) -> float:
	if feature.is_empty():
		return INF
	var dx := float(x - int(feature["center_x"])) / float(feature["radius_x"])
	var dz := float(z - int(feature["center_z"])) / float(feature["radius_z"])
	return dx * dx + dz * dz


func stage6_feature_for_point(x: int, z: int) -> Dictionary:
	var lake_cell_x := floori(float(x) * STAGE6_LAKE_CELL_RECIPROCAL)
	var lake_cell_z := floori(float(z) * STAGE6_LAKE_CELL_RECIPROCAL)
	var lake := stage6_lake_candidate(lake_cell_x, lake_cell_z)
	if not lake.is_empty() and stage6_feature_distance_squared(x, z, lake) < 1.0:
		return lake
	var pond_cell_x := floori(float(x) * STAGE6_POND_CELL_RECIPROCAL)
	var pond_cell_z := floori(float(z) * STAGE6_POND_CELL_RECIPROCAL)
	var pond := stage6_pond_candidate(pond_cell_x, pond_cell_z)
	if not pond.is_empty() and stage6_feature_distance_squared(x, z, pond) < 1.0:
		return pond
	return {}


func stage6_shape_height_for_feature(
	stage5_height: int,
	x: int,
	z: int,
	feature: Dictionary
) -> int:
	if feature.is_empty():
		return stage5_height
	var distance_squared := stage6_feature_distance_squared(x, z, feature)
	if distance_squared >= 1.0:
		return stage5_height
	var water_radius := float(feature["water_radius"])
	var water_radius_squared := water_radius * water_radius
	var hard_rim_radius := float(feature["hard_rim_radius"])
	var hard_rim_squared := hard_rim_radius * hard_rim_radius
	var water_level := int(feature["water_level"])
	if distance_squared <= water_radius_squared:
		var core_t := clampf(distance_squared / water_radius_squared, 0.0, 1.0)
		core_t = core_t * core_t * (3.0 - 2.0 * core_t)
		var depth := int(feature["depth"])
		var floor_height := water_level - 1 - roundi(float(depth) * (1.0 - core_t))
		return clampi(mini(stage5_height, floor_height), 3, STAGE2_SAFE_TERRAIN_TOP)
	if distance_squared <= hard_rim_squared:
		return clampi(maxi(stage5_height, water_level + 1), 3, STAGE2_SAFE_TERRAIN_TOP)
	if stage5_height >= water_level + 1:
		return stage5_height
	var rim_t := clampf(
		(distance_squared - hard_rim_squared) / (1.0 - hard_rim_squared),
		0.0,
		1.0
	)
	rim_t = rim_t * rim_t * (3.0 - 2.0 * rim_t)
	var blended_rim := roundi(lerpf(float(water_level + 1), float(stage5_height), rim_t))
	return clampi(maxi(stage5_height, blended_rim), 3, STAGE2_SAFE_TERRAIN_TOP)


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
	for cell_z in range(lake_min_z, lake_max_z + 1):
		for cell_x in range(lake_min_x, lake_max_x + 1):
			var lake := stage6_lake_candidate(cell_x, cell_z)
			if not lake.is_empty():
				features.append(lake)
	var pond_min_x := floori(float(min_x) * STAGE6_POND_CELL_RECIPROCAL)
	var pond_max_x := floori(float(max_x) * STAGE6_POND_CELL_RECIPROCAL)
	var pond_min_z := floori(float(min_z) * STAGE6_POND_CELL_RECIPROCAL)
	var pond_max_z := floori(float(max_z) * STAGE6_POND_CELL_RECIPROCAL)
	for cell_z in range(pond_min_z, pond_max_z + 1):
		for cell_x in range(pond_min_x, pond_max_x + 1):
			var pond := stage6_pond_candidate(cell_x, cell_z)
			if not pond.is_empty():
				features.append(pond)
	return features


func apply_water_topology(
	fields: Vector4,
	provisional_height: int,
	x: int,
	z: int
) -> int:
	var stage5_height := super.apply_water_topology(fields, provisional_height, x, z)
	var feature := stage6_feature_for_point(x, z)
	if feature.is_empty():
		return stage5_height
	return stage6_shape_height_for_feature(stage5_height, x, z, feature)


func water_info_at(x: int, z: int) -> Vector2i:
	var stage5_info := super.water_info_at(x, z)
	if stage5_info.x != WATER_NONE:
		return stage5_info
	var feature := stage6_feature_for_point(x, z)
	if feature.is_empty():
		return Vector2i(WATER_NONE, -1)
	var water_radius := float(feature["water_radius"])
	if stage6_feature_distance_squared(x, z, feature) > water_radius * water_radius:
		return Vector2i(WATER_NONE, -1)
	var stage5_height := stage6_stage5_height_at(x, z)
	var final_height := stage6_shape_height_for_feature(stage5_height, x, z, feature)
	var water_level := int(feature["water_level"])
	if final_height >= water_level:
		return Vector2i(WATER_NONE, -1)
	return Vector2i(int(feature["type"]), water_level)


func water_type_at(x: int, z: int) -> int:
	return water_info_at(x, z).x


func water_surface_height_at(x: int, z: int) -> int:
	return water_info_at(x, z).y


func is_lake_column(x: int, z: int) -> bool:
	return water_type_at(x, z) == WATER_LAKE


func is_pond_column(x: int, z: int) -> bool:
	return water_type_at(x, z) == WATER_POND


func terrain_height(x: int, z: int) -> int:
	var fields := sample_world_fields(x, z)
	var provisional_height := build_provisional_terrain(fields)
	return finalize_height(apply_water_topology(fields, provisional_height, x, z))


func is_tree_origin(x: int, z: int) -> bool:
	if water_type_at(x, z) != WATER_NONE:
		return false
	return super.is_tree_origin(x, z)
