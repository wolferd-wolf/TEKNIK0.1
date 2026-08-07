extends RefCounted

const BASE_CACHE := preload("res://scripts/world/playable_world_stage3_cache_fast.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const FIELD_STRIDE := 6


static func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func build(coord: Vector2i, sampler) -> Dictionary:
	# Stage 4 remains the authoritative base cache. Stage 5 adds one compact
	# river pass: about 25 river nodes per padded chunk plus interpolation over
	# the existing 16x16 columns. No FastNoiseLite call is added here.
	var result: Dictionary = BASE_CACHE.build(coord, sampler)
	var fields: PackedFloat32Array = result["world_fields"]
	var heights: PackedInt32Array = result["heights"]
	var width := CHUNK_SIZE + PADDING * 2
	var count := width * width
	var river_signal := PackedFloat32Array()
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
	var river_nodes := PackedFloat32Array()
	river_nodes.resize(node_width * node_height)
	for nz in range(node_height):
		var world_z := node_min_z + nz * spacing
		for nx in range(node_width):
			var world_x := node_min_x + nx * spacing
			river_nodes[nz * node_width + nx] = sampler.stage5_sample_river_structure_node(
				world_x,
				world_z
			)

	var ocean_start: float = sampler.STAGE4_OCEAN_WATER_START
	var channel_inner: float = sampler.STAGE5_CHANNEL_INNER
	var channel_outer: float = sampler.STAGE5_CHANNEL_OUTER
	var valley_inner: float = sampler.STAGE5_VALLEY_INNER
	var valley_outer: float = sampler.STAGE5_VALLEY_OUTER
	var coast_width: float = sampler.STAGE5_COAST_WIDTH_SCALE
	var inland_width: float = sampler.STAGE5_INLAND_WIDTH_SCALE
	var width_range: float = sampler.STAGE5_WIDTH_CONTINENTAL_RANGE
	var max_carve: int = sampler.STAGE5_MAX_VALLEY_CARVE
	var channel_depth: int = sampler.STAGE5_CHANNEL_DEPTH
	var sea_level: int = sampler.SEA_LEVEL

	for cz in range(width):
		var world_z := min_z + cz
		var nz := floori(float(world_z - node_min_z) * reciprocal)
		var node_origin_z := node_min_z + nz * spacing
		var tz := _smooth(float(world_z - node_origin_z) * reciprocal)
		var north_base := nz * node_width
		var south_base := north_base + node_width
		var row := cz * width
		for cx in range(width):
			var world_x := min_x + cx
			var nx := floori(float(world_x - node_min_x) * reciprocal)
			var node_origin_x := node_min_x + nx * spacing
			var tx := _smooth(float(world_x - node_origin_x) * reciprocal)
			var nw := river_nodes[north_base + nx]
			var ne := river_nodes[north_base + nx + 1]
			var sw := river_nodes[south_base + nx]
			var se := river_nodes[south_base + nx + 1]
			var north := nw + (ne - nw) * tx
			var south := sw + (se - sw) * tx
			var signal := north + (south - north) * tz
			var column := row + cx
			river_signal[column] = signal

			var c: float = fields[column * FIELD_STRIDE]
			if c <= ocean_start:
				continue
			var inland_t := _smooth((c - ocean_start) / width_range)
			var width_scale := coast_width + (inland_width - coast_width) * inland_t
			var scaled_distance := absf(signal) / width_scale
			var valley_t := clampf(
				(scaled_distance - valley_inner) / (valley_outer - valley_inner),
				0.0,
				1.0
			)
			valley_t = valley_t * valley_t * (3.0 - 2.0 * valley_t)
			var valley_strength := 1.0 - valley_t
			if valley_strength <= 0.0:
				continue

			var current_height: int = heights[column]
			var continental_target := roundi(sampler.continental_base_elevation(c) + 1.0)
			var carve_limited_target := current_height - max_carve
			var valley_floor := mini(
				current_height,
				maxi(sea_level, maxi(continental_target, carve_limited_target))
			)
			var shaped_height := roundi(
				float(current_height)
				+ float(valley_floor - current_height) * valley_strength
			)

			var channel_t := clampf(
				(scaled_distance - channel_inner) / (channel_outer - channel_inner),
				0.0,
				1.0
			)
			channel_t = channel_t * channel_t * (3.0 - 2.0 * channel_t)
			var channel_strength := 1.0 - channel_t
			if channel_strength > 0.0:
				var channel_floor := maxi(sea_level - 1, shaped_height - channel_depth)
				shaped_height = roundi(
					float(shaped_height)
					+ float(channel_floor - shaped_height) * channel_strength
				)
			heights[column] = clampi(shaped_height, 3, sampler.STAGE2_SAFE_TERRAIN_TOP)

	result["heights"] = heights
	result["river_signal"] = river_signal
	return result
