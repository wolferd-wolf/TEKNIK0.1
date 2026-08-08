extends "res://scripts/world/playable_world_stage4_generation_data.gd"

# Stage 5 rivers are deterministic continuous centerlines. Each corridor is a
# graph in world space: x + diagonal_drift(z) + low-frequency meander(z).
# The shipping field stores physical block-distance from the nearest centerline,
# avoiding per-column trigonometry while retaining the accepted river geometry.
const WATER_RIVER := 2

const STAGE5_RIVER_LATTICE_SPACING := 192
const STAGE5_RIVER_LATTICE_RECIPROCAL := 1.0 / 192.0
const STAGE5_RIVER_SPACING := 224.0
const STAGE5_RIVER_HALF_SPACING := 112.0
const STAGE5_RIVER_DIAGONAL_SLOPE := 0.28
const STAGE5_RIVER_MEANDER_AMPLITUDE := 48.0
const STAGE5_RIVER_HASH_SALT := 0x3d93cb17

# Physical block distances from the centerline. These are equivalent to the
# previously accepted sin-distance bands at 224-block river spacing.
const STAGE5_CHANNEL_INNER := 1.8
const STAGE5_CHANNEL_OUTER := 6.8
const STAGE5_VALLEY_INNER := 7.2
const STAGE5_VALLEY_OUTER := 14.4
const STAGE5_CHANNEL_WATER_CUTOFF := 0.50

const STAGE5_COAST_WIDTH_SCALE := 1.04
const STAGE5_INLAND_WIDTH_SCALE := 0.96
const STAGE5_WIDTH_CONTINENTAL_RANGE := 1.34

const STAGE5_MAX_VALLEY_CARVE := 24
const STAGE5_CHANNEL_DEPTH := 2
const STAGE5_VALLEY_RELIEF_FRACTION := 0.55


func stage5_river_lattice_value(lattice_index: int) -> float:
	return _stage3_hash01(lattice_index, 0, STAGE5_RIVER_HASH_SALT) * 2.0 - 1.0


func stage5_meander_at(world_z: float) -> float:
	var lattice_index := floori(world_z * STAGE5_RIVER_LATTICE_RECIPROCAL)
	var lattice_origin := float(lattice_index * STAGE5_RIVER_LATTICE_SPACING)
	var t := _stage3_smooth01((world_z - lattice_origin) * STAGE5_RIVER_LATTICE_RECIPROCAL)
	return lerpf(
		stage5_river_lattice_value(lattice_index),
		stage5_river_lattice_value(lattice_index + 1),
		t
	)


func stage5_river_row_phase(world_z: int) -> float:
	return (
		float(world_z) * STAGE5_RIVER_DIAGONAL_SLOPE
		+ stage5_meander_at(float(world_z)) * STAGE5_RIVER_MEANDER_AMPLITUDE
	)


func stage5_periodic_block_distance(position: float) -> float:
	return absf(
		fposmod(position + STAGE5_RIVER_HALF_SPACING, STAGE5_RIVER_SPACING)
		- STAGE5_RIVER_HALF_SPACING
	)


func stage5_river_raw_at(world_x: float, world_z: float) -> float:
	var phase := (
		world_x
		+ world_z * STAGE5_RIVER_DIAGONAL_SLOPE
		+ stage5_meander_at(world_z) * STAGE5_RIVER_MEANDER_AMPLITUDE
	)
	return stage5_periodic_block_distance(phase)


func stage5_sample_river_structure_node(world_x: int, world_z: int) -> float:
	return stage5_river_raw_at(float(world_x), float(world_z))


func stage5_river_signal(x: int, z: int) -> float:
	return stage5_river_raw_at(float(x), float(z))


func stage5_river_width_scale(continentalness: float) -> float:
	var inland_t := _stage3_smooth01(
		(continentalness - STAGE4_OCEAN_WATER_START) / STAGE5_WIDTH_CONTINENTAL_RANGE
	)
	return lerpf(STAGE5_COAST_WIDTH_SCALE, STAGE5_INLAND_WIDTH_SCALE, inland_t)


func stage5_river_strengths_from_signal(continentalness: float, river_value: float) -> Vector2:
	var scaled_distance := river_value / stage5_river_width_scale(continentalness)
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


func stage5_valley_drop(stage4_height: int) -> int:
	var relief := maxi(0, stage4_height - SEA_LEVEL)
	return mini(
		STAGE5_MAX_VALLEY_CARVE,
		maxi(2, roundi(float(relief) * STAGE5_VALLEY_RELIEF_FRACTION))
	)


func stage5_shape_height_from_signal(
	continentalness: float,
	stage4_height: int,
	river_value: float
) -> int:
	if continentalness <= STAGE4_OCEAN_WATER_START:
		return stage4_height
	var strengths := stage5_river_strengths_from_signal(continentalness, river_value)
	var channel_strength := strengths.x
	var valley_strength := strengths.y
	if valley_strength <= 0.0:
		return stage4_height
	var valley_floor := maxi(SEA_LEVEL, stage4_height - stage5_valley_drop(stage4_height))
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
	var river_value := stage5_river_signal(x, z)
	var strengths := stage5_river_strengths_from_signal(fields.x, river_value)
	var final_height := finalize_height(
		stage5_shape_height_from_signal(fields.x, stage4_height, river_value)
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
