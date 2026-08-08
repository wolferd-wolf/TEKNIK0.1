extends "res://scripts/world/playable_world_stage11_water_biome_data.gd"

# Stage 13 terrain-distribution correction. Keep the Stage 9 historical oracle
# frozen, but narrow the live hill interval so broad low-structure land reads as
# open terrain. Plateau, mountain, valley, terrain frequency and world height are
# intentionally unchanged.
const STAGE13_LEGACY_HILL_STRUCTURE_MIN := STAGE2_PLAINS_END
const STAGE13_HILL_STRUCTURE_MIN := -0.10


func stage9_terrain_modifier_from_fields(
	continentalness: float,
	terrain_structure: float,
	water_type: int
) -> int:
	if water_type != WATER_NONE:
		return TERRAIN_MODIFIER_NONE
	if terrain_structure >= STAGE9_MOUNTAIN_STRUCTURE_MIN:
		if stage9_valley_strength(continentalness, terrain_structure) >= STAGE9_VALLEY_STRENGTH_MIN:
			return TERRAIN_MODIFIER_VALLEY
		return TERRAIN_MODIFIER_MOUNTAIN
	if terrain_structure >= STAGE9_PLATEAU_STRUCTURE_MIN:
		return TERRAIN_MODIFIER_PLATEAU
	if terrain_structure >= STAGE13_HILL_STRUCTURE_MIN:
		return TERRAIN_MODIFIER_HILL
	return TERRAIN_MODIFIER_NONE


# Stage 13 corrects the visually repetitive Stage 5 river layout without adding
# another noise stack or a watershed simulation. The old field repeated one
# shared meander every STAGE5_RIVER_SPACING blocks. Stage 13 keeps the same
# corridor/valley shaping contract, but every river lane gets a deterministic
# lane offset and its own low-frequency meander sequence.
const STAGE13_RIVER_LANE_OFFSET_AMPLITUDE := 20.0
const STAGE13_RIVER_LANE_OFFSET_SALT := 0x51c37ad9
const STAGE13_RIVER_MEANDER_SALT := 0x2b7e4d13
const STAGE13_RIVER_MAX_LATERAL_OFFSET := (
	STAGE13_RIVER_LANE_OFFSET_AMPLITUDE + STAGE5_RIVER_MEANDER_AMPLITUDE
)
const STAGE13_RIVER_MIN_CENTER_SEPARATION := (
	STAGE5_RIVER_SPACING - 2.0 * STAGE13_RIVER_MAX_LATERAL_OFFSET
)


func stage13_river_lane_offset(lane_index: int) -> float:
	return (
		(_stage3_hash01(lane_index, 0, STAGE13_RIVER_LANE_OFFSET_SALT) * 2.0 - 1.0)
		* STAGE13_RIVER_LANE_OFFSET_AMPLITUDE
	)


func stage13_river_lane_meander_value(lane_index: int, lattice_index: int) -> float:
	return (
		_stage3_hash01(lane_index, lattice_index, STAGE13_RIVER_MEANDER_SALT) * 2.0
		- 1.0
	)


func stage13_river_center_x(lane_index: int, world_z: float) -> float:
	var lattice_index := floori(world_z * STAGE5_RIVER_LATTICE_RECIPROCAL)
	var lattice_origin := float(lattice_index * STAGE5_RIVER_LATTICE_SPACING)
	var t := _stage3_smooth01(
		(world_z - lattice_origin) * STAGE5_RIVER_LATTICE_RECIPROCAL
	)
	var meander := lerpf(
		stage13_river_lane_meander_value(lane_index, lattice_index),
		stage13_river_lane_meander_value(lane_index, lattice_index + 1),
		t
	)
	return (
		float(lane_index) * STAGE5_RIVER_SPACING
		+ stage13_river_lane_offset(lane_index)
		- world_z * STAGE5_RIVER_DIAGONAL_SLOPE
		- meander * STAGE5_RIVER_MEANDER_AMPLITUDE
	)


func stage13_river_signal(world_x: float, world_z: float) -> float:
	# Total per-lane lateral displacement is < half the lane spacing, so the
	# nearest true centerline is guaranteed to be one of the estimated lane or
	# its two immediate neighbors.
	var estimate := roundi(
		(world_x + world_z * STAGE5_RIVER_DIAGONAL_SLOPE)
		/ STAGE5_RIVER_SPACING
	)
	var best := INF
	for lane_index in range(estimate - 1, estimate + 2):
		best = minf(
			best,
			absf(world_x - stage13_river_center_x(lane_index, world_z))
		)
	return best


func stage5_river_raw_at(world_x: float, world_z: float) -> float:
	return stage13_river_signal(world_x, world_z)


func stage5_sample_river_structure_node(world_x: int, world_z: int) -> float:
	return stage13_river_signal(float(world_x), float(world_z))


func stage5_river_signal(x: int, z: int) -> float:
	return stage13_river_signal(float(x), float(z))
