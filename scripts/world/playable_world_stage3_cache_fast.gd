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
			var nw := structure_nodes[north_base + nx]
			var ne := structure_nodes[north_base + nx + 1]
			var sw := structure_nodes[south_base + nx]
			var se := structure_nodes[south_base + nx + 1]
			var north := nw + (ne - nw) * tx
			var south := sw + (se - sw) * tx
			var structure := north + (south - north) * tz
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
			var terrain_fields := Vector4(continentalness, structure, 0.0, 0.0)
			var height: int = sampler.build_provisional_terrain(terrain_fields)
			# Most columns remain on the Stage 3 fast path. Stage 4 arithmetic is
			# evaluated only in the ocean/coast continentalness band.
			if continentalness < sampler.STAGE4_COAST_INLAND_END:
				height = sampler.apply_water_topology(
					terrain_fields,
					height,
					world_x,
					world_z
				)
			heights[column] = height
			biomes[column] = sampler.classify_biome(Vector2(temperature, moisture), world_x, world_z)

	return {"world_fields": fields, "heights": heights, "biomes": biomes}