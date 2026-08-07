extends "res://scripts/world/playable_world_generation_data.gd"

# Stage 5 adds rivers as a first-class terrain field before final surface height.
# The field is deterministic hash/value noise on a coarse 96-block lattice. It
# reuses the accepted Stage 3 macro warp and is resampled on the same 4-block
# structure lattice used by the chunk cache, so the hot path adds no new
# FastNoiseLite sampler.
const WATER_RIVER := 2

const STAGE5_RIVER_LATTICE_SPACING := 96
const STAGE5_RIVER_LATTICE_RECIPROCAL := 1.0 / 96.0
const STAGE5_RIVER_WARP_SCALE := 0.75
const STAGE5_RIVER_HASH_SALT := 0x3d93cb17

# abs(river_signal) near zero is the corridor. The inner/outer pairs create
# smooth bands rather than a binary trench. Width broadens gradually toward the
# coast so mouths meet oceans naturally and narrows inland.
const STAGE5_CHANNEL_INNER := 0.012
const STAGE5_CHANNEL_OUTER := 0.040
const STAGE5_VALLEY_INNER := 0.045
const STAGE5_VALLEY_OUTER := 0.120
const STAGE5_CHANNEL_WATER_CUTOFF := 0.50
const STAGE5_COAST_WIDTH_SCALE := 1.35
const STAGE5_INLAND_WIDTH_SCALE := 0.85
const STAGE5_WIDTH_CONTINENTAL_RANGE := 0.90

const STAGE5_MAX_VALLEY_CARVE := 24
const STAGE5_CHANNEL_DEPTH := 2


func stage5_river_lattice_value(lattice_x: int, lattice_z: int) -> float:
	return _stage3_hash01(lattice_x, lattice_z, STAGE5_RIVER_HASH_SALT) * 2.0 - 1.0


func stage5_river_raw_at(world_x: float, world_z: float) -> float:
	var lattice_x := floori(world_x * STAGE5_RIVER_LATTICE_RECIPROCAL)
	var lattice_z := floori(world_z * STAGE5_RIVER_LATTICE_RECIPROCAL)
	var origin_x := lattice_x * STAGE5_RIVER_LATTICE_SPACING
	var origin_z := lattice_z * STAGE5_RIVER_LATTICE_SPACING
	var tx := _stage3_smooth01(
		(world_x - float(origin_x)) * STAGE5_RIVER_LATTICE_RECIPROCAL
	)
	var tz := _stage3_smooth01(
		(world_z - float(origin_z)) * STAGE5_RIVER_LATTICE_RECIPROCAL
	)
	var north_west := stage5_river_lattice_value(lattice_x, lattice_z)
	var north_east := stage5_river_lattice_value(lattice_x + 1, lattice_z)
	var south_west := stage5_river_lattice_value(lattice_x, lattice_z + 1)
	var south_east := stage5_river_lattice_value(lattice_x + 1, lattice_z + 1)
	return lerpf(
		lerpf(north_west, north_east, tx),
		lerpf(south_west, south_east, tx),
		tz
	)


func stage5_sample_river_structure_node(world_x: int, world_z: int) -> float:
	var warp := stage3_macro_warp_offset(world_x, world_z) * STAGE5_RIVER_WARP_SCALE
	return stage5_river_raw_at(float(world_x) + warp.x, float(world_z) + warp.y)


func stage5_river_signal(x: int, z: int) -> float:
	# River signal is cached on the same 4-block lattice as terrain structure.
	# This public path reproduces that lattice exactly for direct queries.
	var spacing := STAGE3_FIELD_LATTICE_SPACING
	var reciprocal := STAGE3_FIELD_LATTICE_RECIPROCAL
	var node_x := floori(float(x) * reciprocal)
	var node_z := floori(float(z) * reciprocal)
	var origin_x := node_x * spacing
	var origin_z := node_z * spacing
	var tx := _stage3_smooth01(float(x - origin_x) * reciprocal)
	var tz := _stage3_smooth01(float(z - origin_z) * reciprocal)
	var north_west := stage5_sample_river_structure_node(origin_x, origin_z)
	var north_east := stage5_sample_river_structure_node(origin_x + spacing, origin_z)
	var south_west := stage5_sample_river_structure_node(origin_x, origin_z + spacing)
	var south_east := stage5_sample_river_structure_node(origin_x + spacing, origin_z + spacing)
	return lerpf(
		lerpf(north_west, north_east, tx),
		lerpf(south_west, south_east, tx),
		tz
	)


func stage5_river_width_scale(continentalness: float) -> float:
	var inland_t := _stage3_smooth01(
		(continentalness - STAGE4_OCEAN_WATER_START) / STAGE5_WIDTH_CONTINENTAL_RANGE
	)
	return lerpf(STAGE5_COAST_WIDTH_SCALE, STAGE5_INLAND_WIDTH_SCALE, inland_t)


func stage5_river_strengths_from_signal(continentalness: float, signal: float) -> Vector2:
	var scaled_distance := absf(signal) / stage5_river_width_scale(continentalness)
	var channel_t := clampf(
		(scaled_distance - STAGE5_CHANNEL_INNER)
		/ (STAGE5_CHANNEL_OUTER - STAGE5_CHANNEL_INNER),
		0.0,
		1.0
	)
	channel_t = channel_t * channel_t * (3.0 - 2.0 * channel_t)
	var valley_t := clampf(
		(scaled_distance - STAGE5_VALLEY_INNER)
		/ (STAGE5_VALLEY_OUTER - STAGE5_VALLEY_INNER),
		0.0,
		1.0
	)
	valley_t = valley_t * valley_t * (3.0 - 2.0 * valley_t)
	return Vector2(1.0 - channel_t, 1.0 - valley_t)


func stage5_shape_height_from_signal(
	continentalness: float,
	stage4_height: int,
	signal: float
) -> int:
	if continentalness <= STAGE4_OCEAN_WATER_START:
		return stage4_height
	var strengths := stage5_river_strengths_from_signal(continentalness, signal)
	var channel_strength := strengths.x
	var valley_strength := strengths.y
	if valley_strength <= 0.0:
		return stage4_height

	# Mountain rivers lower a broad valley toward continental base elevation, but
	# a hard maximum carve prevents a sheer full-height trench through a ridge.
	var continental_target := roundi(continental_base_elevation(continentalness) + 1.0)
	var carve_limited_target := stage4_height - STAGE5_MAX_VALLEY_CARVE
	var valley_floor := mini(
		stage4_height,
		maxi(SEA_LEVEL, maxi(continental_target, carve_limited_target))
	)
	var shaped_height := roundi(lerpf(
		float(stage4_height),
		float(valley_floor),
		valley_strength
	))

	if channel_strength > 0.0:
		var channel_floor := maxi(SEA_LEVEL - 1, shaped_height - STAGE5_CHANNEL_DEPTH)
		shaped_height = roundi(lerpf(
			float(shaped_height),
			float(channel_floor),
			channel_strength
		))
	return clampi(shaped_height, 3, STAGE2_SAFE_TERRAIN_TOP)


func apply_water_topology(
	fields: Vector4,
	provisional_height: int,
	x: int,
	z: int
) -> int:
	var stage4_height := super.apply_water_topology(fields, provisional_height, x, z)
	if fields.x <= STAGE4_OCEAN_WATER_START:
		return stage4_height
	return stage5_shape_height_from_signal(
		fields.x,
		stage4_height,
		stage5_river_signal(x, z)
	)


func water_info_at(x: int, z: int) -> Vector2i:
	var fields := sample_world_fields(x, z)
	var provisional_height := build_provisional_terrain(fields)
	var stage4_height := super.apply_water_topology(fields, provisional_height, x, z)
	if fields.x <= STAGE4_OCEAN_WATER_START:
		var ocean_height := finalize_height(stage4_height)
		if water_type_from_fields(fields, ocean_height) == WATER_OCEAN:
			return Vector2i(WATER_OCEAN, SEA_LEVEL)
		return Vector2i(WATER_NONE, -1)

	var signal := stage5_river_signal(x, z)
	var strengths := stage5_river_strengths_from_signal(fields.x, signal)
	var final_height := finalize_height(
		stage5_shape_height_from_signal(fields.x, stage4_height, signal)
	)
	if strengths.x >= STAGE5_CHANNEL_WATER_CUTOFF:
		return Vector2i(WATER_RIVER, final_height + 1)
	return Vector2i(WATER_NONE, -1)


func water_type_at(x: int, z: int) -> int:
	return water_info_at(x, z).x


func is_river_column(x: int, z: int) -> bool:
	return water_type_at(x, z) == WATER_RIVER


func water_surface_height_at(x: int, z: int) -> int:
	return water_info_at(x, z).y


func terrain_height(x: int, z: int) -> int:
	var fields := sample_world_fields(x, z)
	var provisional_height := build_provisional_terrain(fields)
	return finalize_height(apply_water_topology(fields, provisional_height, x, z))


func is_tree_origin(x: int, z: int) -> bool:
	if water_type_at(x, z) != WATER_NONE:
		return false
	return super.is_tree_origin(x, z)
