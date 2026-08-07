extends RefCounted

# Shipping-only Stage 3 cache builder. Stage 2 made terrain height independent
# of temperature/moisture, while biome identity already samples its own accepted
# climate pair. Reuse that pair in the reserved terrain-climate cache slots so
# chunk generation does not pay for two additional noise samples per column.
const CHUNK_SIZE := 12
const PADDING := 2
const FIELD_CONTINENTALNESS := 0
const FIELD_TERRAIN_STRUCTURE := 1
const FIELD_TERRAIN_TEMPERATURE := 2
const FIELD_TERRAIN_MOISTURE := 3
const FIELD_BIOME_TEMPERATURE := 4
const FIELD_BIOME_MOISTURE := 5
const FIELD_STRIDE := 6


static func _smooth01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func build(coord: Vector2i, sampler) -> Dictionary:
	var width := CHUNK_SIZE + PADDING * 2
	var column_count := width * width
	var field_cache := PackedFloat32Array()
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	field_cache.resize(column_count * FIELD_STRIDE)
	heights.resize(column_count)
	biomes.resize(column_count)

	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	var min_world_x := origin_x - PADDING
	var max_world_x := origin_x + CHUNK_SIZE + PADDING - 1
	var min_world_z := origin_z - PADDING
	var max_world_z := origin_z + CHUNK_SIZE + PADDING - 1

	var structure_spacing: int = sampler.STAGE3_FIELD_LATTICE_SPACING
	var structure_reciprocal: float = sampler.STAGE3_FIELD_LATTICE_RECIPROCAL
	var structure_min_x := floori(float(min_world_x) * structure_reciprocal) * structure_spacing
	var structure_min_z := floori(float(min_world_z) * structure_reciprocal) * structure_spacing
	var structure_max_x := (
		floori(float(max_world_x) * structure_reciprocal) + 1
	) * structure_spacing
	var structure_max_z := (
		floori(float(max_world_z) * structure_reciprocal) + 1
	) * structure_spacing
	var structure_width := int((structure_max_x - structure_min_x) / structure_spacing) + 1
	var structure_height := int((structure_max_z - structure_min_z) / structure_spacing) + 1

	# Cache the tiny set of 64-block warp vectors that can influence this padded
	# chunk, then interpolate them for every 4-block structure node.
	var warp_spacing: int = sampler.STAGE3_WARP_LATTICE_SPACING
	var warp_reciprocal: float = sampler.STAGE3_WARP_LATTICE_RECIPROCAL
	var warp_min_lx := floori(float(structure_min_x) * warp_reciprocal)
	var warp_min_lz := floori(float(structure_min_z) * warp_reciprocal)
	var warp_max_lx := floori(float(structure_max_x) * warp_reciprocal) + 1
	var warp_max_lz := floori(float(structure_max_z) * warp_reciprocal) + 1
	var warp_width := warp_max_lx - warp_min_lx + 1
	var warp_height := warp_max_lz - warp_min_lz + 1
	var warp_nodes := PackedVector2Array()
	warp_nodes.resize(warp_width * warp_height)
	for warp_z_index in range(warp_height):
		var lattice_z := warp_min_lz + warp_z_index
		for warp_x_index in range(warp_width):
			var lattice_x := warp_min_lx + warp_x_index
			warp_nodes[warp_z_index * warp_width + warp_x_index] = (
				sampler.stage3_warp_lattice_vector(lattice_x, lattice_z)
			)

	var structure_nodes := PackedFloat32Array()
	structure_nodes.resize(structure_width * structure_height)
	for node_z_index in range(structure_height):
		var node_world_z := structure_min_z + node_z_index * structure_spacing
		var warp_lz := floori(float(node_world_z) * warp_reciprocal)
		var warp_origin_z := warp_lz * warp_spacing
		var warp_tz := _smooth01(float(node_world_z - warp_origin_z) * warp_reciprocal)
		var warp_z_index := warp_lz - warp_min_lz
		for node_x_index in range(structure_width):
			var node_world_x := structure_min_x + node_x_index * structure_spacing
			var warp_lx := floori(float(node_world_x) * warp_reciprocal)
			var warp_origin_x := warp_lx * warp_spacing
			var warp_tx := _smooth01(float(node_world_x - warp_origin_x) * warp_reciprocal)
			var warp_x_index := warp_lx - warp_min_lx
			var warp_nw := warp_nodes[warp_z_index * warp_width + warp_x_index]
			var warp_ne := warp_nodes[warp_z_index * warp_width + warp_x_index + 1]
			var warp_sw := warp_nodes[(warp_z_index + 1) * warp_width + warp_x_index]
			var warp_se := warp_nodes[(warp_z_index + 1) * warp_width + warp_x_index + 1]
			var warp := warp_nw.lerp(warp_ne, warp_tx).lerp(
				warp_sw.lerp(warp_se, warp_tx),
				warp_tz
			)
			structure_nodes[node_z_index * structure_width + node_x_index] = (
				sampler.terrain_shape_noise.get_noise_2d(
					float(node_world_x) + warp.x,
					float(node_world_z) + warp.y
				)
			)

	for local_z in range(-PADDING, CHUNK_SIZE + PADDING):
		for local_x in range(-PADDING, CHUNK_SIZE + PADDING):
			var column_index := (local_z + PADDING) * width + local_x + PADDING
			var field_index := column_index * FIELD_STRIDE
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var structure_x_index := floori(
				float(world_x - structure_min_x) * structure_reciprocal
			)
			var structure_z_index := floori(
				float(world_z - structure_min_z) * structure_reciprocal
			)
			var structure_origin_x := structure_min_x + structure_x_index * structure_spacing
			var structure_origin_z := structure_min_z + structure_z_index * structure_spacing
			var tx := _smooth01(float(world_x - structure_origin_x) * structure_reciprocal)
			var tz := _smooth01(float(world_z - structure_origin_z) * structure_reciprocal)
			var nw := structure_nodes[structure_z_index * structure_width + structure_x_index]
			var ne := structure_nodes[structure_z_index * structure_width + structure_x_index + 1]
			var sw := structure_nodes[(structure_z_index + 1) * structure_width + structure_x_index]
			var se := structure_nodes[(structure_z_index + 1) * structure_width + structure_x_index + 1]
			var structure := lerpf(lerpf(nw, ne, tx), lerpf(sw, se, tx), tz)

			var world_xf := float(world_x)
			var world_zf := float(world_z)
			var continentalness: float = sampler.continentalness_noise.get_noise_2d(world_xf, world_zf)
			var biome_temperature: float = sampler.biome_temperature_noise.get_noise_2d(world_xf, world_zf)
			var biome_moisture: float = sampler.biome_moisture_noise.get_noise_2d(world_xf, world_zf)
			var terrain_fields := Vector4(
				continentalness,
				structure,
				biome_temperature,
				biome_moisture
			)
			var biome_climate := Vector2(biome_temperature, biome_moisture)
			field_cache[field_index + FIELD_CONTINENTALNESS] = continentalness
			field_cache[field_index + FIELD_TERRAIN_STRUCTURE] = structure
			field_cache[field_index + FIELD_TERRAIN_TEMPERATURE] = biome_temperature
			field_cache[field_index + FIELD_TERRAIN_MOISTURE] = biome_moisture
			field_cache[field_index + FIELD_BIOME_TEMPERATURE] = biome_temperature
			field_cache[field_index + FIELD_BIOME_MOISTURE] = biome_moisture
			heights[column_index] = sampler.build_provisional_terrain(terrain_fields)
			biomes[column_index] = sampler.classify_biome(biome_climate, world_x, world_z)

	return {
		"world_fields": field_cache,
		"heights": heights,
		"biomes": biomes,
	}
