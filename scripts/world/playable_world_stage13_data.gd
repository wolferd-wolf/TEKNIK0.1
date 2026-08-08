extends "res://scripts/world/playable_world_stage11_water_biome_data.gd"

# Stage 13 terrain-distribution correction.
#
# STAGE13_FLAT_TERRAIN_MAX is intentionally the single source of truth for the
# flat->rolling transition. Both the physical height formula and the terrain
# modifier classifier consume this same boundary so "none" can never become a
# relabelled rolling-terrain interval again.
const STAGE13_LEGACY_HILL_STRUCTURE_MIN := STAGE2_PLAINS_END
const STAGE13_FLAT_TERRAIN_MAX := -0.10
# Compatibility name retained for existing audit/report code. Do not give this
# an independent numeric value: it must remain an alias of the physical edge.
const STAGE13_HILL_STRUCTURE_MIN := STAGE13_FLAT_TERRAIN_MAX


func build_provisional_terrain(fields: Vector4) -> int:
	# Stage 2 originally began the flat->rolling blend at -0.38 and reached full
	# rolling terrain by -0.28. The prior Stage 13 distribution fix moved only the
	# modifier label to -0.10, leaving physically rolling columns labelled none.
	#
	# The shipping Stage 13 terrain now stays on the base-height path through the
	# shared -0.10 boundary, then smoothly ramps toward the existing rolling target
	# between -0.10 and the accepted plateau boundary at STAGE2_ROLLING_END. This
	# physically opens the complained-about -0.28..-0.10 band without changing
	# plateau, mountain, valley, continentalness, hydrology, or world-height rules.
	var c: float = clampf(fields.x, -1.0, 1.0)
	var structure: float = clampf(fields.y, -1.0, 1.0)
	var shaped_continent: float = c * 0.35 + c * c * c * 0.65
	var base_height: float = (
		STAGE2_CONTINENTAL_BASE_HEIGHT
		+ shaped_continent * STAGE2_CONTINENTAL_HEIGHT_SCALE
	)
	if c < STAGE2_OCEAN_SHELF_START:
		var basin_t: float = clampf(
			(STAGE2_OCEAN_SHELF_START - c)
			/ (STAGE2_OCEAN_SHELF_START - STAGE2_OCEAN_BASIN_FULL),
			0.0,
			1.0
		)
		basin_t = basin_t * basin_t * (3.0 - 2.0 * basin_t)
		base_height -= basin_t * STAGE2_OCEAN_BASIN_DEPTH

	if structure <= STAGE13_FLAT_TERRAIN_MAX:
		return clampi(roundi(base_height), 3, STAGE2_SAFE_TERRAIN_TOP)

	var rolling_target: float = base_height + 2.0 + absf(c) * STAGE2_ROLLING_RISE
	if structure <= STAGE2_ROLLING_END:
		var terrain_t: float = clampf(
			(structure - STAGE13_FLAT_TERRAIN_MAX)
			/ (STAGE2_ROLLING_END - STAGE13_FLAT_TERRAIN_MAX),
			0.0,
			1.0
		)
		terrain_t = terrain_t * terrain_t * (3.0 - 2.0 * terrain_t)
		return clampi(
			roundi(lerpf(base_height, rolling_target, terrain_t)),
			3,
			STAGE2_SAFE_TERRAIN_TOP
		)

	var upland_target: float = base_height + 6.0 + STAGE2_UPLAND_RISE
	if structure < STAGE2_MOUNTAIN_START:
		var terrain_t: float = clampf(
			(structure - STAGE2_ROLLING_END)
			/ (STAGE2_MOUNTAIN_START - STAGE2_ROLLING_END),
			0.0,
			1.0
		)
		terrain_t = terrain_t * terrain_t * (3.0 - 2.0 * terrain_t)
		return clampi(
			roundi(lerpf(rolling_target, upland_target, terrain_t)),
			3,
			STAGE2_SAFE_TERRAIN_TOP
		)

	var ridge_base: float = 1.0 - absf(c)
	var ridge: float = ridge_base * ridge_base
	var mountain_target: float = (
		base_height
		+ STAGE2_MOUNTAIN_BASE_RISE
		+ ridge * STAGE2_MOUNTAIN_RIDGE_RISE
		- (1.0 - ridge) * STAGE2_VALLEY_CUT
	)
	if structure < STAGE2_MOUNTAIN_FULL:
		var terrain_t: float = clampf(
			(structure - STAGE2_MOUNTAIN_START)
			/ (STAGE2_MOUNTAIN_FULL - STAGE2_MOUNTAIN_START),
			0.0,
			1.0
		)
		terrain_t = terrain_t * terrain_t * (3.0 - 2.0 * terrain_t)
		return clampi(
			roundi(lerpf(upland_target, mountain_target, terrain_t)),
			3,
			STAGE2_SAFE_TERRAIN_TOP
		)

	return clampi(roundi(mountain_target), 3, STAGE2_SAFE_TERRAIN_TOP)


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
	if terrain_structure > STAGE13_FLAT_TERRAIN_MAX:
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