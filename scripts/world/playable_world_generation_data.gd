extends "res://scripts/world/playable_world_data.gd"

# Stage 2 terrain architecture.
#
# The overhaul keeps the accepted deterministic samplers and 150-block legal
# vertical range, but terrain height is now derived from geography instead of
# the legacy climate-coupled mountain formula. No extra noise layer is sampled
# here: existing fields are remapped into macro elevation, terrain regimes and
# ridged mountain structure so the Android hot path remains column-based.
const OVERHAUL_WORLD_HEIGHT := 150

const STAGE2_CONTINENTAL_BASE_HEIGHT := 18.0
const STAGE2_CONTINENTAL_HEIGHT_SCALE := 14.0
const STAGE2_PLAINS_END := -0.28
const STAGE2_ROLLING_START := -0.38
const STAGE2_ROLLING_END := 0.22
const STAGE2_UPLAND_START := 0.04
const STAGE2_UPLAND_END := 0.48
const STAGE2_MOUNTAIN_START := 0.34
const STAGE2_MOUNTAIN_FULL := 0.68
const STAGE2_ROLLING_RISE := 8.0
const STAGE2_UPLAND_RISE := 16.0
const STAGE2_MOUNTAIN_BASE_RISE := 18.0
const STAGE2_MOUNTAIN_RIDGE_RISE := 50.0
const STAGE2_VALLEY_CUT := 7.0
const STAGE2_SAFE_TERRAIN_TOP := OVERHAUL_WORLD_HEIGHT - 12


func sample_world_fields(x: int, z: int) -> Vector4:
	return sample_column_noise(x, z)


func _smooth01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _smooth_range(value: float, start: float, finish: float) -> float:
	return _smooth01((value - start) / (finish - start))


func continental_base_elevation(continentalness: float) -> float:
	var c := clampf(continentalness, -1.0, 1.0)
	var shaped := c * 0.35 + c * c * c * 0.65
	return STAGE2_CONTINENTAL_BASE_HEIGHT + shaped * STAGE2_CONTINENTAL_HEIGHT_SCALE


func terrain_regime_weights(terrain_structure: float) -> Vector4:
	# x=plains, y=rolling, z=upland/plateau, w=mountain.
	var structure := clampf(terrain_structure, -1.0, 1.0)
	var rolling_in := _smooth_range(structure, STAGE2_ROLLING_START, STAGE2_PLAINS_END)
	var rolling_out := 1.0 - _smooth_range(structure, STAGE2_ROLLING_END, STAGE2_UPLAND_END)
	var rolling := rolling_in * rolling_out
	var upland_in := _smooth_range(structure, STAGE2_UPLAND_START, STAGE2_UPLAND_END)
	var mountain := _smooth_range(structure, STAGE2_MOUNTAIN_START, STAGE2_MOUNTAIN_FULL)
	var upland := upland_in * (1.0 - mountain)
	var plains := 1.0 - _smooth_range(structure, STAGE2_PLAINS_END, STAGE2_ROLLING_END)
	return Vector4(
		clampf(plains, 0.0, 1.0),
		clampf(rolling, 0.0, 1.0),
		clampf(upland, 0.0, 1.0),
		clampf(mountain, 0.0, 1.0)
	)


func ridge_strength(continentalness: float) -> float:
	# Square the classic 1-|noise| ridge signal. This is visibly sharp enough
	# for voxel terrain and avoids a general pow() call in the column hot path.
	var ridge := 1.0 - absf(clampf(continentalness, -1.0, 1.0))
	ridge = clampf(ridge, 0.0, 1.0)
	return ridge * ridge


func build_provisional_terrain(fields: Vector4) -> int:
	# This is intentionally fused. The first Stage 2 implementation expressed
	# every transform through helper calls and produced the right terrain but
	# measured 1.651 ms p95. The same transforms are expanded here so each
	# padded column pays one interpreted function call, matching Stage 1's hot
	# path discipline.
	var c := clampf(fields.x, -1.0, 1.0)
	var structure := clampf(fields.y, -1.0, 1.0)
	var shaped_continent := c * 0.35 + c * c * c * 0.65
	var base_height := (
		STAGE2_CONTINENTAL_BASE_HEIGHT
		+ shaped_continent * STAGE2_CONTINENTAL_HEIGHT_SCALE
	)

	var rolling_in_t := clampf(
		(structure - STAGE2_ROLLING_START)
		/ (STAGE2_PLAINS_END - STAGE2_ROLLING_START),
		0.0,
		1.0
	)
	var rolling_in := rolling_in_t * rolling_in_t * (3.0 - 2.0 * rolling_in_t)
	var rolling_out_t := clampf(
		(structure - STAGE2_ROLLING_END)
		/ (STAGE2_UPLAND_END - STAGE2_ROLLING_END),
		0.0,
		1.0
	)
	var rolling_out := 1.0 - (
		rolling_out_t * rolling_out_t * (3.0 - 2.0 * rolling_out_t)
	)
	var rolling := rolling_in * rolling_out

	var upland_t := clampf(
		(structure - STAGE2_UPLAND_START)
		/ (STAGE2_UPLAND_END - STAGE2_UPLAND_START),
		0.0,
		1.0
	)
	var upland_curve := upland_t * upland_t * (3.0 - 2.0 * upland_t)
	var mountain_t := clampf(
		(structure - STAGE2_MOUNTAIN_START)
		/ (STAGE2_MOUNTAIN_FULL - STAGE2_MOUNTAIN_START),
		0.0,
		1.0
	)
	var mountain := mountain_t * mountain_t * (3.0 - 2.0 * mountain_t)
	var upland := upland_curve * (1.0 - mountain)

	var ridge_base := clampf(1.0 - absf(c), 0.0, 1.0)
	var ridge := ridge_base * ridge_base
	var rolling_rise := rolling * (2.0 + absf(c) * STAGE2_ROLLING_RISE)
	var upland_rise := upland * (6.0 + upland_curve * STAGE2_UPLAND_RISE)
	var mountain_rise := mountain * (
		STAGE2_MOUNTAIN_BASE_RISE + ridge * STAGE2_MOUNTAIN_RIDGE_RISE
	)
	var valley_cut := mountain * (1.0 - ridge) * STAGE2_VALLEY_CUT
	var height := base_height + rolling_rise + upland_rise + mountain_rise - valley_cut
	return clampi(roundi(height), 3, STAGE2_SAFE_TERRAIN_TOP)


func apply_water_topology(
	_fields: Vector4,
	provisional_height: int,
	_x: int,
	_z: int
) -> int:
	# Stage 2 changes landform only. Water topology begins in Stage 4.
	return provisional_height


func finalize_height(water_shaped_height: int) -> int:
	return clampi(water_shaped_height, 3, STAGE2_SAFE_TERRAIN_TOP)


func classify_biome(climate: Vector2, x: int, z: int) -> int:
	# Biome behavior remains the accepted Stage 1 classifier. Stage 7 replaces
	# biome classification after terrain and hydrology context are complete.
	var temperature := climate.x
	var moisture := climate.y

	var hot_t := clampf(
		(temperature - (BIOME_HOT_THRESHOLD - BIOME_BLEND_WIDTH)) * BIOME_BLEND_RANGE_RECIPROCAL,
		0.0,
		1.0
	)
	var hot := hot_t * hot_t * (3.0 - 2.0 * hot_t)
	var cold_t := clampf(
		(temperature - (BIOME_COLD_THRESHOLD - BIOME_BLEND_WIDTH)) * BIOME_BLEND_RANGE_RECIPROCAL,
		0.0,
		1.0
	)
	var cold := 1.0 - cold_t * cold_t * (3.0 - 2.0 * cold_t)
	var dry_t := clampf(
		(moisture - (BIOME_DRY_THRESHOLD - BIOME_BLEND_WIDTH)) * BIOME_BLEND_RANGE_RECIPROCAL,
		0.0,
		1.0
	)
	var dry := 1.0 - dry_t * dry_t * (3.0 - 2.0 * dry_t)
	var wet_t := clampf(
		(moisture - (BIOME_WET_THRESHOLD - BIOME_BLEND_WIDTH)) * BIOME_BLEND_RANGE_RECIPROCAL,
		0.0,
		1.0
	)
	var wet := wet_t * wet_t * (3.0 - 2.0 * wet_t)

	var desert := hot * dry
	var forest := wet * (1.0 - desert)
	var rocky := cold * (1.0 - wet) * (1.0 - desert)
	var plains := maxf(0.0, 1.0 - maxf(desert, maxf(forest, rocky)))
	var total := plains + forest + desert + rocky
	if total <= 0.000001:
		return BIOME_PLAINS
	var reciprocal_total := 1.0 / total
	plains *= reciprocal_total
	forest *= reciprocal_total
	desert *= reciprocal_total

	var patch_x := floori(float(x) * BIOME_BLEND_PATCH_RECIPROCAL)
	var patch_z := floori(float(z) * BIOME_BLEND_PATCH_RECIPROCAL)
	var hash_value := (patch_x * 73856093) ^ (patch_z * 19349663) ^ (WORLD_SEED * 83492791)
	hash_value = absi(hash_value)
	var selector := float(hash_value % 1000003) / 1000003.0
	if selector < plains:
		return BIOME_PLAINS
	if selector < plains + forest:
		return BIOME_FOREST
	if selector < plains + forest + desert:
		return BIOME_DESERT
	return BIOME_ROCKY


func decorate_surface(y: int, height: int, biome: int) -> int:
	return terrain_block(y, height, biome)


func terrain_height(x: int, z: int) -> int:
	var fields := sample_world_fields(x, z)
	var provisional_height := build_provisional_terrain(fields)
	var water_shaped_height := apply_water_topology(fields, provisional_height, x, z)
	return finalize_height(water_shaped_height)


func biome_at(x: int, z: int) -> int:
	return classify_biome(sample_biome_climate(x, z), x, z)


func blended_biome_from_samples(_samples: Vector4, x: int, z: int) -> int:
	return biome_at(x, z)


func get_block(cell: Vector3i) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= OVERHAUL_WORLD_HEIGHT:
		return BLOCK_AIR
	var key := cell_key(cell)
	if overrides.has(key):
		return int(overrides[key])
	var fields := sample_world_fields(cell.x, cell.z)
	var provisional_height := build_provisional_terrain(fields)
	var water_shaped_height := apply_water_topology(
		fields,
		provisional_height,
		cell.x,
		cell.z
	)
	var height := finalize_height(water_shaped_height)
	var biome := classify_biome(sample_biome_climate(cell.x, cell.z), cell.x, cell.z)
	if cell.y <= height:
		return decorate_surface(cell.y, height, biome)
	return generated_tree_block(cell)


func is_tree_origin(x: int, z: int) -> bool:
	var fields := sample_world_fields(x, z)
	var provisional_height := build_provisional_terrain(fields)
	var water_shaped_height := apply_water_topology(fields, provisional_height, x, z)
	var surface := finalize_height(water_shaped_height)
	var biome := classify_biome(sample_biome_climate(x, z), x, z)
	return is_tree_origin_for_biome(x, z, surface, biome)


func is_tree_origin_for_biome(x: int, z: int, surface: int, biome: int) -> bool:
	if biome == BIOME_DESERT or biome == BIOME_ROCKY:
		return false
	if surface <= SEA_LEVEL + 1 or surface + TREE_TRUNK_HEIGHT + 1 >= OVERHAUL_WORLD_HEIGHT:
		return false
	var baseline_grid := (
		posmod(x, TREE_SPACING) == TREE_OFFSET
		and posmod(z, TREE_SPACING) == TREE_OFFSET
	)
	var forest_grid := (
		biome == BIOME_FOREST
		and posmod(x, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
		and posmod(z, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
	)
	if not baseline_grid and not forest_grid:
		return false
	var hash_value := absi((x * 73856093) ^ (z * 19349663) ^ WORLD_SEED)
	if forest_grid and not baseline_grid:
		return hash_value % 3 != 0
	return hash_value % 4 != 0


func set_block(cell: Vector3i, block_id: int) -> bool:
	if cell.y < 0 or cell.y >= OVERHAUL_WORLD_HEIGHT or get_block(cell) == block_id:
		return false
	overrides[cell_key(cell)] = block_id
	dirty = true
	save_delay = 1.5
	return true
