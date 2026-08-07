extends RefCounted

const CHUNK_SIZE := 12
const PADDING := 2
const FIELD_STRIDE := 6


static func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func build(coord: Vector2i, sampler) -> Dictionary:
	var width := CHUNK_SIZE + PADDING * 2
	var count := width * width
	var fields := PackedFloat32Array()
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	fields.resize(count * FIELD_STRIDE)
	heights.resize(count)
	biomes.resize(count)

	var min_x := coord.x * CHUNK_SIZE - PADDING
	var min_z := coord.y * CHUNK_SIZE - PADDING
	var max_x := min_x + width - 1
	var max_z := min_z + width - 1
	var spacing: int = sampler.STAGE3_FIELD_LATTICE_SPACING
	var reciprocal: float = sampler.STAGE3_FIELD_LATTICE_RECIPROCAL
	var node_min_x := floori(float(min_x) * reciprocal) * spacing
	var node_min_z := floori(float(min_z) * reciprocal) * spacing
	var node_max_x := (floori(float(max_x) * reciprocal) + 1) * spacing
	var node_max_z := (floori(float(max_z) * reciprocal) + 1) * spacing
	var node_width := int((node_max_x - node_min_x) / spacing) + 1
	var node_height := int((node_max_z - node_min_z) / spacing) + 1

	var warp_reciprocal: float = sampler.STAGE3_WARP_LATTICE_RECIPROCAL
	var warp_spacing: int = sampler.STAGE3_WARP_LATTICE_SPACING
	var warp_min_x := floori(float(node_min_x) * warp_reciprocal)
	var warp_min_z := floori(float(node_min_z) * warp_reciprocal)
	var warp_max_x := floori(float(node_max_x) * warp_reciprocal) + 1
	var warp_max_z := floori(float(node_max_z) * warp_reciprocal) + 1
	var warp_width := warp_max_x - warp_min_x + 1
	var warp_height := warp_max_z - warp_min_z + 1
	var warp_nodes := PackedVector2Array()
	warp_nodes.resize(warp_width * warp_height)
	for wz in range(warp_height):
		for wx in range(warp_width):
			warp_nodes[wz * warp_width + wx] = sampler.stage3_warp_lattice_vector(
				warp_min_x + wx,
				warp_min_z + wz
			)

	var structure_nodes := PackedFloat32Array()
	structure_nodes.resize(node_width * node_height)
	for nz in range(node_height):
		var world_z := node_min_z + nz * spacing
		var lattice_z := floori(float(world_z) * warp_reciprocal)
		var wz := lattice_z - warp_min_z
		var tz := _smooth(float(world_z - lattice_z * warp_spacing) * warp_reciprocal)
		for nx in range(node_width):
			var world_x := node_min_x + nx * spacing
			var lattice_x := floori(float(world_x) * warp_reciprocal)
			var wx := lattice_x - warp_min_x
			var tx := _smooth(float(world_x - lattice_x * warp_spacing) * warp_reciprocal)
			var nw := warp_nodes[wz * warp_width + wx]
			var ne := warp_nodes[wz * warp_width + wx + 1]
			var sw := warp_nodes[(wz + 1) * warp_width + wx]
			var se := warp_nodes[(wz + 1) * warp_width + wx + 1]
			var north := nw + (ne - nw) * tx
			var south := sw + (se - sw) * tx
			var warp := north + (south - north) * tz
			structure_nodes[nz * node_width + nx] = sampler.terrain_shape_noise.get_noise_2d(
				float(world_x) + warp.x,
				float(world_z) + warp.y
			)

	var x_node := PackedInt32Array()
	var x_weight := PackedFloat32Array()
	var x_world := PackedInt32Array()
	var z_node := PackedInt32Array()
	var z_weight := PackedFloat32Array()
	var z_world := PackedInt32Array()
	x_node.resize(width)
	x_weight.resize(width)
	x_world.resize(width)
	z_node.resize(width)
	z_weight.resize(width)
	z_world.resize(width)
	for i in range(width):
		var world_x := min_x + i
		var nx := floori(float(world_x - node_min_x) * reciprocal)
		x_world[i] = world_x
		x_node[i] = nx
		x_weight[i] = _smooth(float(world_x - (node_min_x + nx * spacing)) * reciprocal)
		var world_z := min_z + i
		var nz := floori(float(world_z - node_min_z) * reciprocal)
		z_world[i] = world_z
		z_node[i] = nz
		z_weight[i] = _smooth(float(world_z - (node_min_z + nz * spacing)) * reciprocal)

	# Cache Stage 2 terrain constants and inline the accepted formula. Stage 3
	# changes only the terrain-structure coordinate; the height formula itself is
	# identical to Stage 2.
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
	var basin_reciprocal := 1.0 / (shelf_start - basin_full)
	var plains_blend_reciprocal := 1.0 / (plains_end - rolling_start)
	var upland_blend_reciprocal := 1.0 / (mountain_start - rolling_end)
	var mountain_blend_reciprocal := 1.0 / (mountain_full - mountain_start)

	# Accepted biome classifier constants. Stage 3 did not change ecology.
	var hot_start: float = sampler.BIOME_HOT_THRESHOLD - sampler.BIOME_BLEND_WIDTH
	var cold_start: float = sampler.BIOME_COLD_THRESHOLD - sampler.BIOME_BLEND_WIDTH
	var dry_start: float = sampler.BIOME_DRY_THRESHOLD - sampler.BIOME_BLEND_WIDTH
	var wet_start: float = sampler.BIOME_WET_THRESHOLD - sampler.BIOME_BLEND_WIDTH
	var blend_reciprocal: float = sampler.BIOME_BLEND_RANGE_RECIPROCAL
	var patch_reciprocal: float = sampler.BIOME_BLEND_PATCH_RECIPROCAL
	var world_seed: int = sampler.WORLD_SEED
	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_rocky: int = sampler.BIOME_ROCKY
	var patch_x := PackedInt32Array()
	patch_x.resize(width)
	for cx in range(width):
		patch_x[cx] = floori(float(x_world[cx]) * patch_reciprocal)

	for cz in range(width):
		var world_z: int = z_world[cz]
		var zf := float(world_z)
		var nz: int = z_node[cz]
		var tz: float = z_weight[cz]
		var north_base := nz * node_width
		var south_base := north_base + node_width
		var row := cz * width
		var patch_z := floori(zf * patch_reciprocal)
		for cx in range(width):
			var world_x: int = x_world[cx]
			var xf := float(world_x)
			var nx: int = x_node[cx]
			var tx: float = x_weight[cx]
			var nw := structure_nodes[north_base + nx]
			var ne := structure_nodes[north_base + nx + 1]
			var sw := structure_nodes[south_base + nx]
			var se := structure_nodes[south_base + nx + 1]
			var north := nw + (ne - nw) * tx
			var south := sw + (se - sw) * tx
			var structure := north + (south - north) * tz

			var continentalness: float = sampler.continentalness_noise.get_noise_2d(xf, zf)
			var temperature: float = sampler.biome_temperature_noise.get_noise_2d(xf, zf)
			var moisture: float = sampler.biome_moisture_noise.get_noise_2d(xf, zf)
			var column := row + cx
			var field := column * FIELD_STRIDE
			fields[field] = continentalness
			fields[field + 1] = structure
			fields[field + 2] = temperature
			fields[field + 3] = moisture
			fields[field + 4] = temperature
			fields[field + 5] = moisture

			var c := clampf(continentalness, -1.0, 1.0)
			var s := clampf(structure, -1.0, 1.0)
			var shaped_continent := c * 0.35 + c * c * c * 0.65
			var base_height := continental_base + shaped_continent * continental_scale
			if c < shelf_start:
				var basin_t := clampf((shelf_start - c) * basin_reciprocal, 0.0, 1.0)
				basin_t = basin_t * basin_t * (3.0 - 2.0 * basin_t)
				base_height -= basin_t * basin_depth
			var rolling_target := base_height + 2.0 + absf(c) * rolling_rise
			var height: int
			if s <= rolling_start:
				height = clampi(roundi(base_height), 3, safe_top)
			elif s < plains_end:
				var terrain_t := (s - rolling_start) * plains_blend_reciprocal
				terrain_t = terrain_t * terrain_t * (3.0 - 2.0 * terrain_t)
				height = clampi(roundi(lerpf(base_height, rolling_target, terrain_t)), 3, safe_top)
			elif s <= rolling_end:
				height = clampi(roundi(rolling_target), 3, safe_top)
			else:
				var upland_target := base_height + 6.0 + upland_rise
				if s < mountain_start:
					var terrain_t := (s - rolling_end) * upland_blend_reciprocal
					terrain_t = terrain_t * terrain_t * (3.0 - 2.0 * terrain_t)
					height = clampi(roundi(lerpf(rolling_target, upland_target, terrain_t)), 3, safe_top)
				else:
					var ridge_base := 1.0 - absf(c)
					var ridge := ridge_base * ridge_base
					var mountain_target := (
						base_height
						+ mountain_base_rise
						+ ridge * mountain_ridge_rise
						- (1.0 - ridge) * valley_cut
					)
					if s < mountain_full:
						var terrain_t := (s - mountain_start) * mountain_blend_reciprocal
						terrain_t = terrain_t * terrain_t * (3.0 - 2.0 * terrain_t)
						height = clampi(roundi(lerpf(upland_target, mountain_target, terrain_t)), 3, safe_top)
					else:
						height = clampi(roundi(mountain_target), 3, safe_top)
			heights[column] = height

			var hot_t := clampf((temperature - hot_start) * blend_reciprocal, 0.0, 1.0)
			var hot := hot_t * hot_t * (3.0 - 2.0 * hot_t)
			var cold_t := clampf((temperature - cold_start) * blend_reciprocal, 0.0, 1.0)
			var cold := 1.0 - cold_t * cold_t * (3.0 - 2.0 * cold_t)
			var dry_t := clampf((moisture - dry_start) * blend_reciprocal, 0.0, 1.0)
			var dry := 1.0 - dry_t * dry_t * (3.0 - 2.0 * dry_t)
			var wet_t := clampf((moisture - wet_start) * blend_reciprocal, 0.0, 1.0)
			var wet := wet_t * wet_t * (3.0 - 2.0 * wet_t)
			var desert := hot * dry
			var forest := wet * (1.0 - desert)
			var rocky := cold * (1.0 - wet) * (1.0 - desert)
			var plains := maxf(0.0, 1.0 - maxf(desert, maxf(forest, rocky)))
			var total := plains + forest + desert + rocky
			var biome := biome_plains
			if total > 0.000001:
				var inverse_total := 1.0 / total
				plains *= inverse_total
				forest *= inverse_total
				desert *= inverse_total
				var hash_value := (
					(patch_x[cx] * 73856093)
					^ (patch_z * 19349663)
					^ (world_seed * 83492791)
				)
				hash_value = absi(hash_value)
				var selector := float(hash_value % 1000003) / 1000003.0
				if selector < plains:
					biome = biome_plains
				elif selector < plains + forest:
					biome = biome_forest
				elif selector < plains + forest + desert:
					biome = biome_desert
				else:
					biome = biome_rocky
			biomes[column] = biome

	return {"world_fields": fields, "heights": heights, "biomes": biomes}
