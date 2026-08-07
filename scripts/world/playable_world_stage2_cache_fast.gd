extends RefCounted

# Frozen Stage 2 fast cache.
#
# Stage 2 made terrain height independent from terrain temperature/moisture, so
# the historical six-noise cache was doing two expensive noise samples that no
# longer affected Stage 2 height or biome output. This cache preserves the
# accepted Stage 2 terrain and biome formulas exactly while sampling only the
# fields that can affect those outputs.

const CHUNK_SIZE := 12
const PADDING := 2
const FIELD_STRIDE := 6


static func build(coord: Vector2i, sampler) -> Dictionary:
	var width: int = CHUNK_SIZE + PADDING * 2
	var count: int = width * width
	var fields := PackedFloat32Array()
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	fields.resize(count * FIELD_STRIDE)
	heights.resize(count)
	biomes.resize(count)

	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING

	# Stage 2 terrain constants cached once per padded chunk.
	var continental_base: float = sampler.STAGE2_CONTINENTAL_BASE_HEIGHT
	var continental_scale: float = sampler.STAGE2_CONTINENTAL_HEIGHT_SCALE
	var shelf_start: float = sampler.STAGE2_OCEAN_SHELF_START
	var basin_full: float = sampler.STAGE2_OCEAN_BASIN_FULL
	var basin_depth: float = sampler.STAGE2_OCEAN_BASIN_DEPTH
	var rolling_start: float = sampler.STAGE2_ROLLING_START
	var plains_end: float = sampler.STAGE2_PLAINS_END
	var rolling_end: float = sampler.STAGE2_ROLLING_END
	var mountain_start: float = sampler.STAGE2_MOUNTAIN_START
	var mountain_full: float = sampler.STAGE2_MOUNTAIN_FULL
	var rolling_rise: float = sampler.STAGE2_ROLLING_RISE
	var upland_rise: float = sampler.STAGE2_UPLAND_RISE
	var mountain_base_rise: float = sampler.STAGE2_MOUNTAIN_BASE_RISE
	var mountain_ridge_rise: float = sampler.STAGE2_MOUNTAIN_RIDGE_RISE
	var valley_cut: float = sampler.STAGE2_VALLEY_CUT
	var safe_top: int = sampler.STAGE2_SAFE_TERRAIN_TOP
	var basin_reciprocal: float = 1.0 / (shelf_start - basin_full)
	var plains_blend_reciprocal: float = 1.0 / (plains_end - rolling_start)
	var upland_blend_reciprocal: float = 1.0 / (mountain_start - rolling_end)
	var mountain_blend_reciprocal: float = 1.0 / (mountain_full - mountain_start)

	# Accepted Stage 1 biome classifier constants cached once per chunk.
	var hot_start: float = sampler.BIOME_HOT_THRESHOLD - sampler.BIOME_BLEND_WIDTH
	var cold_start: float = sampler.BIOME_COLD_THRESHOLD - sampler.BIOME_BLEND_WIDTH
	var dry_start: float = sampler.BIOME_DRY_THRESHOLD - sampler.BIOME_BLEND_WIDTH
	var wet_start: float = sampler.BIOME_WET_THRESHOLD - sampler.BIOME_BLEND_WIDTH
	var biome_blend_reciprocal: float = sampler.BIOME_BLEND_RANGE_RECIPROCAL
	var biome_patch_reciprocal: float = sampler.BIOME_BLEND_PATCH_RECIPROCAL
	var world_seed: int = sampler.WORLD_SEED
	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_rocky: int = sampler.BIOME_ROCKY

	var biome_patch_x := PackedInt32Array()
	biome_patch_x.resize(width)
	for cx in range(width):
		biome_patch_x[cx] = floori(float(min_x + cx) * biome_patch_reciprocal)

	for cz in range(width):
		var world_z: int = min_z + cz
		var zf: float = float(world_z)
		var patch_z: int = floori(zf * biome_patch_reciprocal)
		var row: int = cz * width
		for cx in range(width):
			var world_x: int = min_x + cx
			var xf: float = float(world_x)
			var column: int = row + cx
			var field: int = column * FIELD_STRIDE

			# Stage 2 terrain depends only on continentalness and terrain structure.
			var continentalness: float = sampler.continentalness_noise.get_noise_2d(xf, zf)
			var structure: float = sampler.terrain_shape_noise.get_noise_2d(xf, zf)
			# Biome classification uses its own slow climate pair.
			var temperature: float = sampler.biome_temperature_noise.get_noise_2d(xf, zf)
			var moisture: float = sampler.biome_moisture_noise.get_noise_2d(xf, zf)

			fields[field] = continentalness
			fields[field + 1] = structure
			# Stage 2 terrain-climate slots remain present for the six-field cache
			# layout, but are deliberately unsampled because Stage 2 made terrain
			# climate-independent. Public sample_world_fields() remains unchanged.
			fields[field + 2] = 0.0
			fields[field + 3] = 0.0
			fields[field + 4] = temperature
			fields[field + 5] = moisture

			# Exact accepted Stage 2 provisional terrain formula, scalar/inlined.
			var c: float = clampf(continentalness, -1.0, 1.0)
			var s: float = clampf(structure, -1.0, 1.0)
			var shaped_continent: float = c * 0.35 + c * c * c * 0.65
			var base_height: float = continental_base + shaped_continent * continental_scale
			if c < shelf_start:
				var basin_t: float = clampf((shelf_start - c) * basin_reciprocal, 0.0, 1.0)
				basin_t = basin_t * basin_t * (3.0 - 2.0 * basin_t)
				base_height -= basin_t * basin_depth

			var rolling_target: float = base_height + 2.0 + absf(c) * rolling_rise
			var height: int
			if s <= rolling_start:
				height = clampi(roundi(base_height), 3, safe_top)
			elif s < plains_end:
				var terrain_t: float = (s - rolling_start) * plains_blend_reciprocal
				terrain_t = terrain_t * terrain_t * (3.0 - 2.0 * terrain_t)
				height = clampi(roundi(lerpf(base_height, rolling_target, terrain_t)), 3, safe_top)
			elif s <= rolling_end:
				height = clampi(roundi(rolling_target), 3, safe_top)
			else:
				var upland_target: float = base_height + 6.0 + upland_rise
				if s < mountain_start:
					var terrain_t: float = (s - rolling_end) * upland_blend_reciprocal
					terrain_t = terrain_t * terrain_t * (3.0 - 2.0 * terrain_t)
					height = clampi(roundi(lerpf(rolling_target, upland_target, terrain_t)), 3, safe_top)
				else:
					var ridge_base: float = 1.0 - absf(c)
					var ridge: float = ridge_base * ridge_base
					var mountain_target: float = (
						base_height
						+ mountain_base_rise
						+ ridge * mountain_ridge_rise
						- (1.0 - ridge) * valley_cut
					)
					if s < mountain_full:
						var terrain_t: float = (s - mountain_start) * mountain_blend_reciprocal
						terrain_t = terrain_t * terrain_t * (3.0 - 2.0 * terrain_t)
						height = clampi(roundi(lerpf(upland_target, mountain_target, terrain_t)), 3, safe_top)
					else:
						height = clampi(roundi(mountain_target), 3, safe_top)
			heights[column] = height

			# Exact accepted biome classifier, scalar/inlined.
			var hot_t: float = clampf((temperature - hot_start) * biome_blend_reciprocal, 0.0, 1.0)
			var hot: float = hot_t * hot_t * (3.0 - 2.0 * hot_t)
			var cold_t: float = clampf((temperature - cold_start) * biome_blend_reciprocal, 0.0, 1.0)
			var cold: float = 1.0 - cold_t * cold_t * (3.0 - 2.0 * cold_t)
			var dry_t: float = clampf((moisture - dry_start) * biome_blend_reciprocal, 0.0, 1.0)
			var dry: float = 1.0 - dry_t * dry_t * (3.0 - 2.0 * dry_t)
			var wet_t: float = clampf((moisture - wet_start) * biome_blend_reciprocal, 0.0, 1.0)
			var wet: float = wet_t * wet_t * (3.0 - 2.0 * wet_t)
			var desert: float = hot * dry
			var forest: float = wet * (1.0 - desert)
			var rocky: float = cold * (1.0 - wet) * (1.0 - desert)
			var plains: float = maxf(0.0, 1.0 - maxf(desert, maxf(forest, rocky)))
			var total: float = plains + forest + desert + rocky
			var biome: int = biome_plains
			if total > 0.000001:
				var reciprocal_total: float = 1.0 / total
				plains *= reciprocal_total
				forest *= reciprocal_total
				desert *= reciprocal_total
				var hash_value: int = (
					(biome_patch_x[cx] * 73856093)
					^ (patch_z * 19349663)
					^ (world_seed * 83492791)
				)
				hash_value = absi(hash_value)
				var selector: float = float(hash_value % 1000003) / 1000003.0
				if selector < plains:
					biome = biome_plains
				elif selector < plains + forest:
					biome = biome_forest
				elif selector < plains + forest + desert:
					biome = biome_desert
				else:
					biome = biome_rocky
			biomes[column] = biome

	return {
		"world_fields": fields,
		"heights": heights,
		"biomes": biomes,
	}
