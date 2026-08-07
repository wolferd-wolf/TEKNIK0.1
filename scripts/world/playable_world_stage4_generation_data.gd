extends "res://scripts/world/playable_world_stage3_generation_data.gd"

# Frozen Stage 4 data implementation. Oceans/coasts were originally appended to
# the public generation-data facade; keeping them here lets later hydrology
# stages extend a stable Stage 4 oracle while the public facade can represent
# the current shipping generator.
const WATER_NONE := 0
const WATER_OCEAN := 1
const STAGE4_OCEAN_WATER_START := -0.34
const STAGE4_OCEAN_BASIN_FULL := -0.48
const STAGE4_COAST_INLAND_END := -0.08
const STAGE4_OCEAN_EDGE_FLOOR := 6
const STAGE4_OCEAN_CORE_FLOOR := 3


func stage4_ocean_strength(continentalness: float) -> float:
	if continentalness >= STAGE4_OCEAN_WATER_START:
		return 0.0
	return _stage3_smooth01(
		(STAGE4_OCEAN_WATER_START - continentalness)
		/ (STAGE4_OCEAN_WATER_START - STAGE4_OCEAN_BASIN_FULL)
	)


func stage4_coast_inland_weight(continentalness: float) -> float:
	if continentalness <= STAGE4_OCEAN_WATER_START:
		return 0.0
	if continentalness >= STAGE4_COAST_INLAND_END:
		return 1.0
	return _stage3_smooth01(
		(continentalness - STAGE4_OCEAN_WATER_START)
		/ (STAGE4_COAST_INLAND_END - STAGE4_OCEAN_WATER_START)
	)


func apply_water_topology(
	fields: Vector4,
	provisional_height: int,
	_x: int,
	_z: int
) -> int:
	var continentalness := clampf(fields.x, -1.0, 1.0)
	if continentalness <= STAGE4_OCEAN_WATER_START:
		var ocean_strength := stage4_ocean_strength(continentalness)
		var ocean_floor := roundi(lerpf(
			float(STAGE4_OCEAN_EDGE_FLOOR),
			float(STAGE4_OCEAN_CORE_FLOOR),
			ocean_strength
		))
		return mini(provisional_height, ocean_floor)
	if continentalness < STAGE4_COAST_INLAND_END:
		var inland_weight := stage4_coast_inland_weight(continentalness)
		return roundi(lerpf(float(SEA_LEVEL), float(provisional_height), inland_weight))
	return provisional_height


func water_type_from_fields(fields: Vector4, final_height: int) -> int:
	if fields.x <= STAGE4_OCEAN_WATER_START and final_height < SEA_LEVEL:
		return WATER_OCEAN
	return WATER_NONE


func water_type_at(x: int, z: int) -> int:
	var fields := sample_world_fields(x, z)
	var provisional_height := build_provisional_terrain(fields)
	var water_shaped_height := apply_water_topology(fields, provisional_height, x, z)
	var final_height := finalize_height(water_shaped_height)
	return water_type_from_fields(fields, final_height)


func is_ocean_column(x: int, z: int) -> bool:
	return water_type_at(x, z) == WATER_OCEAN


func is_coast_column(x: int, z: int) -> bool:
	var continentalness := continentalness_noise.get_noise_2d(float(x), float(z))
	return (
		continentalness > STAGE4_OCEAN_WATER_START
		and continentalness < STAGE4_COAST_INLAND_END
	)
