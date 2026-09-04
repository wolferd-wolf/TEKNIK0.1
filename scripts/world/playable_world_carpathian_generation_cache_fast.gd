extends RefCounted

const STAGE13_CACHE := preload("res://scripts/world/playable_world_stage13_generation_cache_fast.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const FIELD_STRIDE := 6

# Exact Stage 8 Voronoi envelope breakpoints and Stage 9 modifier constants.
# Ecology/modifier behavior is intentionally unchanged in this terrain-only test.
const PLAINS_FOREST_MOISTURE_BOUNDARY := 0.18
const DENSE_FOREST_ENVELOPE_START := 0.348326996197719
const FOREST_ENVELOPE_END := 0.671395348837208
const PLATEAU_START := 0.22
const MOUNTAIN_START := 0.34
const MOUNTAIN_FULL := 0.68
const MOUNTAIN_RANGE_RECIPROCAL := 2.9411764705882353
const VALLEY_MIN := 0.22
const MODIFIER_NONE := 0
const MODIFIER_HILL := 1
const MODIFIER_PLATEAU := 2
const MODIFIER_MOUNTAIN := 3
const MODIFIER_VALLEY := 4


static func _smooth(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func build(coord: Vector2i, sampler) -> Dictionary:
	# Historical/headless workflows that do not build the native extension retain
	# the accepted Stage 13 cache exactly. Shipping Android/Linux native builds
	# take the one-pass Carpathian path below.
	if not sampler.has_method("carpathian_enabled") or not sampler.carpathian_enabled():
		return STAGE13_CACHE.build(coord, sampler)

	var width: int = CHUNK_SIZE + PADDING * 2
	var count: int = width * width
	var fields := PackedFloat32Array()
	var biomes := PackedByteArray()
	var water_types := PackedByteArray()
	var modifiers := PackedByteArray()
	fields.resize(count * FIELD_STRIDE)
	biomes.resize(count)
	water_types.resize(count)
	modifiers.resize(count)

	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING
	var max_x: int = min_x + width - 1
	var max_z: int = min_z + width - 1

	# This is the only Stage 13 terrain substitution: one native batch produces
	# all padded provisional heights. No old Stage 2 height calculation is run.
	var heights: PackedInt32Array = sampler.carpathian_generate_grid(
		min_x, min_z, width, width, 1
	)
	if heights.size() != count:
		push_error("One-pass Carpathian cache received invalid native height grid")
		return {}

	# Preserve the accepted Stage 3 warped terrain-structure field because later
	# biome-expression/modifier systems still consume it. It no longer drives the
	# physical base elevation in this test integration.
	var spacing: int = sampler.STAGE3_FIELD_LATTICE_SPACING
	var reciprocal: float = sampler.STAGE3_FIELD_LATTICE_RECIPROCAL
	var node_min_x: int = floori(float(min_x) * reciprocal) * spacing
	var node_min_z: int = floori(float(min_z) * reciprocal) * spacing
	var node_max_x: int = (floori(float(max_x) * reciprocal) + 1) * spacing
	var node_max_z: int = (floori(float(max_z) * reciprocal) + 1) * spacing
	var node_width: int = int((node_max_x - node_min_x) / spacing) + 1
	var node_height: int = int((node_max_z - node_min_z) / spacing) + 1

	var warp_reciprocal: float = sampler.STAGE3_WARP_LATTICE_RECIPROCAL
	var warp_spacing: int = sampler.STAGE3_WARP_LATTICE_SPACING
	var warp_min_x: int = floori(float(node_min_x) * warp_reciprocal)
	var warp_min_z: int = floori(float(node_min_z) * warp_reciprocal)
	var warp_max_x: int = floori(float(node_max_x) * warp_reciprocal) + 1
	var warp_max_z: int = floori(float(node_max_z) * warp_reciprocal) + 1
	var warp_width: int = warp_max_x - warp_min_x + 1
	var warp_height: int = warp_max_z - warp_min_z + 1
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
		var world_z: int = node_min_z + nz * spacing
		var lattice_z: int = floori(float(world_z) * warp_reciprocal)
		var wz: int = lattice_z - warp_min_z
		var tz: float = _smooth(float(world_z - lattice_z * warp_spacing) * warp_reciprocal)
		for nx in range(node_width):
			var world_x: int = node_min_x + nx * spacing
			var lattice_x: int = floori(float(world_x) * warp_reciprocal)
			var wx: int = lattice_x - warp_min_x
			var tx: float = _smooth(float(world_x - lattice_x * warp_spacing) * warp_reciprocal)
			var nw: Vector2 = warp_nodes[wz * warp_width + wx]
			var ne: Vector2 = warp_nodes[wz * warp_width + wx + 1]
			var sw: Vector2 = warp_nodes[(wz + 1) * warp_width + wx]
			var se: Vector2 = warp_nodes[(wz + 1) * warp_width + wx + 1]
			var north: Vector2 = nw + (ne - nw) * tx
			var south: Vector2 = sw + (se - sw) * tx
			var warp: Vector2 = north + (south - north) * tz
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
		var world_x: int = min_x + i
		var nx: int = floori(float(world_x - node_min_x) * reciprocal)
		x_world[i] = world_x
		x_node[i] = nx
		x_weight[i] = _smooth(float(world_x - (node_min_x + nx * spacing)) * reciprocal)
		var world_z: int = min_z + i
		var nz: int = floori(float(world_z - node_min_z) * reciprocal)
		z_world[i] = world_z
		z_node[i] = nz
		z_weight[i] = _smooth(float(world_z - (node_min_z + nz * spacing)) * reciprocal)

	# Accepted Stage 4 ocean/coast constants.
	var ocean_start: float = sampler.STAGE4_OCEAN_WATER_START
	var ocean_full: float = sampler.STAGE4_OCEAN_BASIN_FULL
	var coast_end: float = sampler.STAGE4_COAST_INLAND_END
	var ocean_edge_floor: int = sampler.STAGE4_OCEAN_EDGE_FLOOR
	var ocean_core_floor: int = sampler.STAGE4_OCEAN_CORE_FLOOR
	var sea_level: int = sampler.SEA_LEVEL
	var safe_top: int = sampler.STAGE2_SAFE_TERRAIN_TOP
	var ocean_reciprocal: float = 1.0 / (ocean_start - ocean_full)
	var coast_reciprocal: float = 1.0 / (coast_end - ocean_start)

	# Accepted Stage 5 / Stage 13 river constants.
	var river_spacing: float = sampler.STAGE5_RIVER_SPACING
	var river_half_spacing: float = sampler.STAGE5_RIVER_HALF_SPACING
	var river_lattice_spacing: int = sampler.STAGE5_RIVER_LATTICE_SPACING
	var river_lattice_reciprocal: float = sampler.STAGE5_RIVER_LATTICE_RECIPROCAL
	var river_diagonal_slope: float = sampler.STAGE5_RIVER_DIAGONAL_SLOPE
	var river_meander_amplitude: float = sampler.STAGE5_RIVER_MEANDER_AMPLITUDE
	var channel_inner: float = sampler.STAGE5_CHANNEL_INNER
	var channel_outer: float = sampler.STAGE5_CHANNEL_OUTER
	var channel_cutoff: float = sampler.STAGE5_CHANNEL_WATER_CUTOFF
	var valley_inner: float = sampler.STAGE5_VALLEY_INNER
	var valley_outer: float = sampler.STAGE5_VALLEY_OUTER
	var coast_width: float = sampler.STAGE5_COAST_WIDTH_SCALE
	var inland_width: float = sampler.STAGE5_INLAND_WIDTH_SCALE
	var width_range: float = sampler.STAGE5_WIDTH_CONTINENTAL_RANGE
	var max_carve: int = sampler.STAGE5_MAX_VALLEY_CARVE
	var channel_depth: int = sampler.STAGE5_CHANNEL_DEPTH
	var relief_fraction: float = sampler.STAGE5_VALLEY_RELIEF_FRACTION
	var river_early_out: float = valley_outer * coast_width
	var stage13_rivers: bool = sampler.has_method("stage13_river_center_x")
	var chunk_mid_x: float = float(min_x) + float(width - 1) * 0.5

	var biome_plains: int = sampler.BIOME_PLAINS
	var biome_forest: int = sampler.BIOME_FOREST
	var biome_dense: int = sampler.BIOME_DENSE_FOREST
	var biome_desert: int = sampler.BIOME_DESERT
	var biome_dry: int = sampler.BIOME_DRY_GRASSLAND
	var biome_cold: int = sampler.BIOME_COLD_FOREST
	var water_none: int = sampler.WATER_NONE
	var water_ocean: int = sampler.WATER_OCEAN
	var water_river: int = sampler.WATER_RIVER
	var flat_terrain_max: float = sampler.STAGE13_FLAT_TERRAIN_MAX

	var river_lattice_min: int = floori(float(min_z) * river_lattice_reciprocal)
	var river_lattice_max: int = floori(float(max_z) * river_lattice_reciprocal) + 1
	var river_lattice_values := PackedFloat32Array()
	if not stage13_rivers:
		river_lattice_values.resize(river_lattice_max - river_lattice_min + 1)
		for river_node in range(river_lattice_values.size()):
			river_lattice_values[river_node] = sampler.stage5_river_lattice_value(
				river_lattice_min + river_node
			)

	for cz in range(width):
		var world_z: int = z_world[cz]
		var zf: float = float(world_z)
		var river_signed_start: float
		if stage13_rivers:
			var lane_estimate: int = roundi(
				(chunk_mid_x + zf * river_diagonal_slope) / river_spacing
			)
			var best_center: float = 0.0
			var best_mid_distance: float = INF
			for lane_index in range(lane_estimate - 1, lane_estimate + 2):
				var center_x: float = sampler.stage13_river_center_x(lane_index, zf)
				var mid_distance: float = absf(chunk_mid_x - center_x)
				if mid_distance < best_mid_distance:
					best_mid_distance = mid_distance
					best_center = center_x
			river_signed_start = float(min_x) - best_center
		else:
			var river_lattice_index: int = floori(zf * river_lattice_reciprocal)
			var river_node_offset: int = river_lattice_index - river_lattice_min
			var river_lattice_origin: int = river_lattice_index * river_lattice_spacing
			var river_t: float = _smooth(float(world_z - river_lattice_origin) * river_lattice_reciprocal)
			var river_meander: float = lerpf(
				river_lattice_values[river_node_offset],
				river_lattice_values[river_node_offset + 1],
				river_t
			)
			var river_row_phase: float = zf * river_diagonal_slope + river_meander * river_meander_amplitude
			river_signed_start = (
				fposmod(float(min_x) + river_row_phase + river_half_spacing, river_spacing)
				- river_half_spacing
			)
		var river_active_min: int = maxi(0, ceili(-river_early_out - river_signed_start))
		var river_active_max: int = mini(width - 1, floori(river_early_out - river_signed_start))

		var nz: int = z_node[cz]
		var tz: float = z_weight[cz]
		var north_base: int = nz * node_width
		var south_base: int = north_base + node_width
		var row: int = cz * width
		for cx in range(width):
			var world_x: int = x_world[cx]
			var xf: float = float(world_x)
			var nx: int = x_node[cx]
			var tx: float = x_weight[cx]
			var nw: float = structure_nodes[north_base + nx]
			var ne: float = structure_nodes[north_base + nx + 1]
			var sw: float = structure_nodes[south_base + nx]
			var se: float = structure_nodes[south_base + nx + 1]
			var north: float = nw + (ne - nw) * tx
			var south: float = sw + (se - sw) * tx
			var structure: float = north + (south - north) * tz

			var continentalness: float = sampler.continentalness_noise.get_noise_2d(xf, zf)
			var temperature: float = sampler.biome_temperature_noise.get_noise_2d(xf, zf)
			var moisture: float = sampler.biome_moisture_noise.get_noise_2d(xf, zf)
			var column: int = row + cx
			var field: int = column * FIELD_STRIDE
			fields[field] = continentalness
			fields[field + 1] = structure
			fields[field + 2] = temperature
			fields[field + 3] = moisture
			fields[field + 4] = temperature
			fields[field + 5] = moisture

			# Native Carpathian provisional height is already in heights[column].
			var height: int = heights[column]

			# Stage 4 ocean/coast shaping and immediate water ownership.
			var water_type: int = water_none
			if continentalness <= ocean_start:
				var ocean_t: float = clampf((ocean_start - continentalness) * ocean_reciprocal, 0.0, 1.0)
				ocean_t = ocean_t * ocean_t * (3.0 - 2.0 * ocean_t)
				var ocean_floor: int = roundi(
					float(ocean_edge_floor) + float(ocean_core_floor - ocean_edge_floor) * ocean_t
				)
				height = mini(height, ocean_floor)
				if height < sea_level:
					water_type = water_ocean
			elif continentalness < coast_end:
				var inland_t: float = (continentalness - ocean_start) * coast_reciprocal
				inland_t = inland_t * inland_t * (3.0 - 2.0 * inland_t)
				height = roundi(float(sea_level) + float(height - sea_level) * inland_t)

			# Stage 5 river shaping, unchanged from the Stage 13 hot cache.
			if continentalness > ocean_start and cx >= river_active_min and cx <= river_active_max:
				var river_value: float = absf(river_signed_start + float(cx))
				var width_t: float = clampf((continentalness - ocean_start) / width_range, 0.0, 1.0)
				width_t = width_t * width_t * (3.0 - 2.0 * width_t)
				var width_scale: float = coast_width + (inland_width - coast_width) * width_t
				var scaled_distance: float = river_value / width_scale
				if scaled_distance < valley_outer:
					var valley_t: float = clampf(
						(scaled_distance - valley_inner) / (valley_outer - valley_inner),
						0.0,
						1.0
					)
					valley_t = valley_t * valley_t * (3.0 - 2.0 * valley_t)
					var valley_strength: float = 1.0 - valley_t
					var relief: int = maxi(0, height - sea_level)
					var valley_drop: int = mini(max_carve, maxi(2, roundi(float(relief) * relief_fraction)))
					var valley_floor: int = maxi(sea_level, height - valley_drop)
					height = roundi(float(height) + float(valley_floor - height) * valley_strength)
					if scaled_distance < channel_outer:
						var channel_t: float = clampf(
							(scaled_distance - channel_inner) / (channel_outer - channel_inner),
							0.0,
							1.0
						)
						channel_t = channel_t * channel_t * (3.0 - 2.0 * channel_t)
						var channel_strength: float = 1.0 - channel_t
						var channel_floor: int = maxi(sea_level - 1, height - channel_depth)
						height = roundi(float(height) + float(channel_floor - height) * channel_strength)
						if channel_strength >= channel_cutoff:
							water_type = water_river
				height = clampi(height, 3, safe_top)
			heights[column] = height
			water_types[column] = water_type

			# Stage 8 ecology remains climate-only exactly as before.
			if water_type != water_none:
				biomes[column] = biome_plains
				modifiers[column] = MODIFIER_NONE
				continue

			var biome: int
			if moisture <= PLAINS_FOREST_MOISTURE_BOUNDARY:
				if 1.04 * temperature < 0.72 * moisture - 0.3856:
					biome = biome_cold
				elif structure <= flat_terrain_max and 0.80 * temperature <= 0.44 * moisture + 0.2172:
					biome = biome_plains
				elif 0.16 * temperature >= 0.36 * moisture + 0.1892:
					biome = biome_desert
				else:
					biome = biome_dry
			elif moisture < DENSE_FOREST_ENVELOPE_START:
				if 1.04 * temperature < -0.08 * moisture - 0.2416:
					biome = biome_cold
				elif 0.80 * temperature > 1.24 * moisture + 0.0732:
					biome = biome_dry
				else:
					biome = biome_forest
			elif moisture <= FOREST_ENVELOPE_END:
				if 1.04 * temperature < -0.08 * moisture - 0.2416:
					biome = biome_cold
				elif 0.24 * temperature <= 0.3884 - 0.68 * moisture:
					biome = biome_forest
				elif 0.56 * temperature > 1.92 * moisture - 0.3152:
					biome = biome_dry
				else:
					biome = biome_dense
			else:
				if 1.28 * temperature + 0.76 * moisture - 0.1468 < 0.0:
					biome = biome_cold
				elif 0.56 * temperature > 1.92 * moisture - 0.3152:
					biome = biome_dry
				else:
					biome = biome_dense
			biomes[column] = biome

			# Terrain modifier remains the accepted Stage 9 expression context for
			# this terrain-only test. It does not control Carpathian elevation.
			var modifier: int = MODIFIER_NONE
			if structure >= MOUNTAIN_START:
				var mountain_strength: float = 1.0
				if structure < MOUNTAIN_FULL:
					var mountain_t: float = (structure - MOUNTAIN_START) * MOUNTAIN_RANGE_RECIPROCAL
					mountain_strength = mountain_t * mountain_t * (3.0 - 2.0 * mountain_t)
				var ridge_base: float = 1.0 - absf(continentalness)
				var ridge: float = ridge_base * ridge_base
				var modifier_valley_strength: float = mountain_strength * (1.0 - ridge)
				modifier = MODIFIER_VALLEY if modifier_valley_strength >= VALLEY_MIN else MODIFIER_MOUNTAIN
			elif structure >= PLATEAU_START:
				modifier = MODIFIER_PLATEAU
			elif structure > flat_terrain_max:
				modifier = MODIFIER_HILL
			modifiers[column] = modifier

	# Stage 6 uses the same cached-field/cached-height fast path as Stage 13, so
	# lakes/ponds are evaluated once against Carpathian terrain rather than by a
	# second high-level sampling pass.
	var features: Array[Dictionary] = sampler.stage6_collect_features_for_cached_bounds(
		min_x,
		min_z,
		max_x,
		max_z,
		width,
		fields,
		heights
	)
	if not features.is_empty():
		for feature: Dictionary in features:
			var center_x: int = int(feature["center_x"])
			var center_z: int = int(feature["center_z"])
			var radius_x: float = float(feature["radius_x"])
			var radius_z: float = float(feature["radius_z"])
			var reciprocal_radius_x: float = 1.0 / radius_x
			var reciprocal_radius_z: float = 1.0 / radius_z
			var water_radius: float = float(feature["water_radius"])
			var water_radius_squared: float = water_radius * water_radius
			var hard_rim_radius: float = float(feature["hard_rim_radius"])
			var hard_rim_squared: float = hard_rim_radius * hard_rim_radius
			var inverse_outer_rim_range: float = 1.0 / (1.0 - hard_rim_squared)
			var water_level: int = int(feature["water_level"])
			var water_level_plus_one: int = water_level + 1
			var depth: int = int(feature["depth"])
			var feature_type: int = int(feature["type"])
			var feature_min_x: int = maxi(min_x, floori(float(center_x) - radius_x))
			var feature_max_x: int = mini(max_x, ceili(float(center_x) + radius_x))
			var feature_min_z: int = maxi(min_z, floori(float(center_z) - radius_z))
			var feature_max_z: int = mini(max_z, ceili(float(center_z) + radius_z))
			for world_z in range(feature_min_z, feature_max_z + 1):
				var normalized_z: float = float(world_z - center_z) * reciprocal_radius_z
				var normalized_z_squared: float = normalized_z * normalized_z
				var cache_z: int = world_z - min_z
				var row: int = cache_z * width
				for world_x in range(feature_min_x, feature_max_x + 1):
					var normalized_x: float = float(world_x - center_x) * reciprocal_radius_x
					var distance_squared: float = normalized_x * normalized_x + normalized_z_squared
					if distance_squared >= 1.0:
						continue
					var cache_x: int = world_x - min_x
					var index: int = row + cache_x
					var stage5_height: int = int(heights[index])
					if distance_squared <= water_radius_squared:
						var core_t: float = clampf(distance_squared / water_radius_squared, 0.0, 1.0)
						core_t = core_t * core_t * (3.0 - 2.0 * core_t)
						var floor_height: int = water_level - 1 - roundi(float(depth) * (1.0 - core_t))
						heights[index] = clampi(mini(stage5_height, floor_height), 3, safe_top)
						water_types[index] = feature_type
						biomes[index] = biome_plains
						modifiers[index] = MODIFIER_NONE
						continue
					if distance_squared <= hard_rim_squared:
						heights[index] = clampi(maxi(stage5_height, water_level_plus_one), 3, safe_top)
						continue
					if stage5_height >= water_level_plus_one:
						continue
					var rim_t: float = clampf(
						(distance_squared - hard_rim_squared) * inverse_outer_rim_range,
						0.0,
						1.0
					)
					rim_t = rim_t * rim_t * (3.0 - 2.0 * rim_t)
					var blended_rim: int = roundi(lerpf(
						float(water_level_plus_one),
						float(stage5_height),
						rim_t
					))
					heights[index] = clampi(maxi(stage5_height, blended_rim), 3, safe_top)

	return {
		"world_fields": fields,
		"heights": heights,
		"biomes": biomes,
		"stage7_water_types": water_types,
		"stage6_features": features,
		"stage8_active_biome_count": sampler.STAGE8_ACTIVE_BIOME_COUNT,
		"stage9_terrain_modifiers": modifiers,
		"stage9_terrain_modifier_count": sampler.STAGE9_TERRAIN_MODIFIER_COUNT,
	}
