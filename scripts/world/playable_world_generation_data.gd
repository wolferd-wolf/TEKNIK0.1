extends "res://scripts/world/playable_world_data.gd"

# Stage 1 compatibility layer.
#
# The inherited sampler remains the accepted world-generation oracle. These
# named stages make the generation responsibilities explicit without changing
# any terrain, biome, block, tree, seed, or save behavior. Stage 2 can replace
# individual stages while the legacy implementation remains available for
# assertion-equivalence tests.


func sample_world_fields(x: int, z: int) -> Vector4:
	return sample_column_noise(x, z)


func build_provisional_terrain(fields: Vector4) -> int:
	return terrain_height_from_samples(fields)


func apply_water_topology(
	_fields: Vector4,
	provisional_height: int,
	_x: int,
	_z: int
) -> int:
	# Stage 1 is deliberately a no-op. Water topology starts in Stage 4.
	return provisional_height


func finalize_height(water_shaped_height: int) -> int:
	return water_shaped_height


func classify_biome(climate: Vector2, x: int, z: int) -> int:
	# Keep this scalar selector mathematically identical to the accepted
	# _resolve_large_zone_biome() hot path, but accept already-sampled climate
	# so a per-chunk field cache can own the noise work.
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
	# The mesher remains the bulk surface/decorations consumer in Stage 1.
	# This stage keeps direct block queries on the same explicit pipeline.
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
	if cell.y >= WORLD_HEIGHT:
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
