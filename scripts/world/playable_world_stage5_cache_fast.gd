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
	var river_signal := PackedFloat32Array()
	fields.resize(count * FIELD_STRIDE)
	heights.resize(count)
	biomes.resize(count)
	river_signal.resize(count)

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

	# Reuse the exact Stage 3 macro-warp lattice for both terrain structure and
	# Stage 5 river nodes. This is the key Stage 5 hot-path optimization: river
	# generation does not recalculate warp vectors and does not do a second
	# 16x16 post-pass over the completed Stage 4 cache.
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
	var river_nodes := PackedFloat32Array()
	structure_nodes.resize(node_width * node_height)
	river_nodes.resize(node_width * node_height)
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
			var node_index := nz * node_width + nx
			structure_nodes[node_index] = sampler.terrain_shape_noise.get_noise_2d(
				float(world_x) + warp.x,
				float(world_z) + warp.y
			)
			river_nodes[node_index] = sampler.stage5_river_raw_at_with_warp(
				world_x,
				world_z,
				warp
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

	# Stage 4 constants.
	var ocean_start: float = sampler.STAGE4_OCEAN_WATER_START
	var ocean_full: float = sampler.STAGE4_OCEAN_BASIN_FULL
	var coast_end: float = sampler.STAGE4_COAST_INLAND_END
	var ocean_edge_floor: int = sampler.STAGE4_OCEAN_EDGE_FLOOR
	var ocean_core_floor: int = sampler.STAGE4_OCEAN_CORE_FLOOR
	var sea_level: int = sampler.SEA_LEVEL
	var ocean_reciprocal := 1.0 / (ocean_start - ocean_full)
	var coast_reciprocal := 1.0 / (coast_end - ocean_start)

	# Stage 5 constants cached once per chunk.
	var channel_inner: float = sampler.STAGE5_CHANNEL_INNER
	var channel_outer: float = sampler.STAGE5_CHANNEL_OUTER
	var valley_inner: float = sampler.STAGE5_VALLEY_INNER
	var valley_outer: float = sampler.STAGE5_VALLEY_OUTER
	var coast_width: float = sampler.STAGE5_COAST_WIDTH_SCALE
	var inland_width: float = sampler.STAGE5_INLAND_WIDTH_SCALE
	var width_range: float = sampler.STAGE5_WIDTH_CONTINENTAL_RANGE
	var max_carve: int = sampler.STAGE5_MAX_VALLEY_CARVE
	var channel_depth: int = sampler.STAGE5_CHANNEL_DEPTH
	var safe_top: int = sampler.STAGE2_SAFE_TERRAIN_TOP
	var river_early_out := valley_outer * coast_width

	# Stage 2 continental-base constants are used only for valley-active columns.
	var continental_base_height: float = sampler.STAGE2_CONTINENTAL_BASE_HEIGHT
	var continental_height_scale: float = sampler.STAGE2_CONTINENTAL_HEIGHT_SCALE
	var shelf_start: float = sampler.STAGE2_OCEAN_SHELF_START
	var basin_full: float = sampler.STAGE2_OCEAN_BASIN_FULL
	var basin_depth: float = sampler.STAGE2_OCEAN_BASIN_DEPTH
	var basin_reciprocal := 1.0 / (shelf_start - basin_full)

	for cz in range(width):
		var world_z: int = z_world[cz]
		var nz: int = z_node[cz]
		var tz: float = z_weight[cz]
		var north_base := nz * node_width
		var south_base := north_base + node_width
		var row := cz * width
		for cx in range(width):
			var world_x: int = x_world[cx]
			var nx: int = x_node[cx]
			var tx: float = x_weight[cx]
			var structure_nw := structure_nodes[north_base + nx]
			var structure_ne := structure_nodes[north_base + nx + 1]
			var structure_sw := structure_nodes[south_base + nx]
			var structure_se := structure_nodes[south_base + nx + 1]
			var structure_north := structure_nw + (structure_ne - structure_nw) * tx
			var structure_south := structure_sw + (structure_se - structure_sw) * tx
			var structure := structure_north + (structure_south - structure_north) * tz

			var river_nw := river_nodes[north_base + nx]
			var river_ne := river_nodes[north_base + nx + 1]
			var river_sw := river_nodes[south_base + nx]
			var river_se := river_nodes[south_base + nx + 1]
			var river_north := river_nw + (river_ne - river_nw) * tx
			var river_south := river_sw + (river_se - river_sw) * tx
			var river_value := river_north + (river_south - river_north) * tz

			var xf := float(world_x)
			var zf := float(world_z)
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
			river_signal[column] = river_value

			var terrain_fields := Vector4(continentalness, structure, 0.0, 0.0)
			var height: int = sampler.build_provisional_terrain(terrain_fields)
			if continentalness <= ocean_start:
				var ocean_t := (ocean_start - continentalness) * ocean_reciprocal
				ocean_t = clampf(ocean_t, 0.0, 1.0)
				ocean_t = ocean_t * ocean_t * (3.0 - 2.0 * ocean_t)
				var ocean_floor := roundi(
					float(ocean_edge_floor)
					+ float(ocean_core_floor - ocean_edge_floor) * ocean_t
				)
				height = mini(height, ocean_floor)
			elif continentalness < coast_end:
				var inland_t := (continentalness - ocean_start) * coast_reciprocal
				inland_t = inland_t * inland_t * (3.0 - 2.0 * inland_t)
				height = roundi(float(sea_level) + float(height - sea_level) * inland_t)

			# Most columns are not near a river. Early-out before width/valley math.
			if continentalness > ocean_start and river_value < river_early_out:
				var width_t := clampf((continentalness - ocean_start) / width_range, 0.0, 1.0)
				width_t = width_t * width_t * (3.0 - 2.0 * width_t)
				var width_scale := coast_width + (inland_width - coast_width) * width_t
				var scaled_distance := river_value / width_scale
				if scaled_distance < valley_outer:
					var valley_t := clampf(
						(scaled_distance - valley_inner) / (valley_outer - valley_inner),
						0.0,
						1.0
					)
					valley_t = valley_t * valley_t * (3.0 - 2.0 * valley_t)
					var valley_strength := 1.0 - valley_t

					var c := clampf(continentalness, -1.0, 1.0)
					var shaped_c := c * 0.35 + c * c * c * 0.65
					var continental_target := continental_base_height + shaped_c * continental_height_scale
					if c < shelf_start:
						var basin_t := clampf((shelf_start - c) * basin_reciprocal, 0.0, 1.0)
						basin_t = basin_t * basin_t * (3.0 - 2.0 * basin_t)
						continental_target -= basin_t * basin_depth
					var valley_floor := mini(
						height,
						maxi(
							sea_level,
							maxi(roundi(continental_target + 1.0), height - max_carve)
						)
					)
					height = roundi(
						float(height) + float(valley_floor - height) * valley_strength
					)

					if scaled_distance < channel_outer:
						var channel_t := clampf(
							(scaled_distance - channel_inner) / (channel_outer - channel_inner),
							0.0,
							1.0
						)
						channel_t = channel_t * channel_t * (3.0 - 2.0 * channel_t)
						var channel_strength := 1.0 - channel_t
						var channel_floor := maxi(sea_level - 1, height - channel_depth)
						height = roundi(
							float(height) + float(channel_floor - height) * channel_strength
						)
				height = clampi(height, 3, safe_top)

			heights[column] = height
			biomes[column] = sampler.classify_biome(Vector2(temperature, moisture), world_x, world_z)

	return {
		"world_fields": fields,
		"heights": heights,
		"biomes": biomes,
		"river_signal": river_signal,
	}
