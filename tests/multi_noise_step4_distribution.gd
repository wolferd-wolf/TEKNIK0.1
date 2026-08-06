extends RefCounted

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const SCAN_MIN := -1024
const SCAN_MAX := 1024
const SCAN_STEP := 8
const DIAG_SIZE := 384
const DIAG_SCALE := 5
const WEIGHT_DIAG_PATH := "res://artifacts/multi-noise-step4-weights.png"
const RESOLVED_DIAG_PATH := "res://artifacts/multi-noise-step4-resolved.png"


static func run(data, failures: Array[String]) -> Dictionary:
	var report := _scan(data, failures)
	_validate_local_coherence(data, failures)
	_validate_surfaces_and_trees(data, report["fixtures"], failures)
	_write_diagnostics(data, failures)
	return report


static func _scan(data, failures: Array[String]) -> Dictionary:
	var size := int((SCAN_MAX - SCAN_MIN) / SCAN_STEP) + 1
	var counts := PackedInt32Array()
	counts.resize(WORLD_DATA.BIOME_COUNT)
	var fixtures: Dictionary = {}
	var previous := PackedByteArray()
	previous.resize(size)
	var transitions := 0
	var edges := 0
	var mixed_points := 0
	var max_weight_total := 0.0
	for row in range(size):
		var z := SCAN_MIN + row * SCAN_STEP
		var left := -1
		for column in range(size):
			var x := SCAN_MIN + column * SCAN_STEP
			var samples: Vector4 = data.sample_column_noise(x, z)
			var weights: Vector4 = data.biome_weights_from_samples(samples)
			var biome: int = data.blended_biome_from_weights(weights, x, z)
			counts[biome] += 1
			var maximum_weight := maxf(weights.x, maxf(weights.y, maxf(weights.z, weights.w)))
			max_weight_total += maximum_weight
			var meaningful := 0
			for candidate in range(WORLD_DATA.BIOME_COUNT):
				if weights[candidate] >= 0.05:
					meaningful += 1
			if meaningful >= 2:
				mixed_points += 1
			var height: int = data.terrain_height_from_samples(samples)
			if not fixtures.has(biome) and height > WORLD_DATA.SEA_LEVEL + 1:
				fixtures[biome] = Vector2i(x, z)
			if left >= 0:
				edges += 1
				if left != biome:
					transitions += 1
			if row > 0:
				edges += 1
				if int(previous[column]) != biome:
					transitions += 1
			left = biome
			previous[column] = biome
	var points := size * size
	var count_report: Array[int] = []
	var ratios: Array[float] = []
	for biome in range(WORLD_DATA.BIOME_COUNT):
		var ratio := float(counts[biome]) / float(points)
		count_report.append(counts[biome])
		ratios.append(ratio)
		if counts[biome] < 100 or ratio < 0.005:
			_fail(failures, "Blended biome %s is absent or too rare: %d (%.4f)" % [data.biome_name(biome), counts[biome], ratio])
		if not fixtures.has(biome):
			_fail(failures, "No above-water fixture found for blended biome %s" % data.biome_name(biome))
	var transition_ratio := float(transitions) / float(maxi(edges, 1))
	if transition_ratio <= 0.001 or transition_ratio >= 0.45:
		_fail(failures, "Resolved blend is missing regions or resembles per-cell noise: %.6f" % transition_ratio)
	var mixed_ratio := float(mixed_points) / float(points)
	if mixed_ratio < 0.02 or mixed_ratio > 0.75:
		_fail(failures, "Weight transition band is absent or dominates the world: %.6f" % mixed_ratio)
	var average_max_weight := max_weight_total / float(points)
	if average_max_weight < 0.45 or average_max_weight > 0.995:
		_fail(failures, "Biome weights are collapsed or effectively still one-hot: %.6f" % average_max_weight)
	return {
		"grid": {
			"minimum_world_coordinate": SCAN_MIN,
			"maximum_world_coordinate": SCAN_MAX,
			"step": SCAN_STEP,
			"points": points,
		},
		"biome_names": ["plains", "forest", "desert", "rocky"],
		"counts": count_report,
		"ratios": ratios,
		"transition_count": transitions,
		"compared_edges": edges,
		"transition_ratio": transition_ratio,
		"mixed_weight_points": mixed_points,
		"mixed_weight_ratio": mixed_ratio,
		"average_max_weight": average_max_weight,
		"fixtures": fixtures,
	}


static func _validate_local_coherence(data, failures: Array[String]) -> void:
	var local_min := -128
	var local_max := 128
	var width := local_max - local_min + 1
	var field := PackedByteArray()
	field.resize(width * width)
	for local_z in range(width):
		var world_z := local_min + local_z
		for local_x in range(width):
			var world_x := local_min + local_x
			field[local_z * width + local_x] = data.biome_at(world_x, world_z)
	var isolated := 0
	var compared := 0
	for local_z in range(1, width - 1):
		for local_x in range(1, width - 1):
			var center: int = int(field[local_z * width + local_x])
			var north: int = int(field[(local_z - 1) * width + local_x])
			var south: int = int(field[(local_z + 1) * width + local_x])
			var west: int = int(field[local_z * width + local_x - 1])
			var east: int = int(field[local_z * width + local_x + 1])
			compared += 1
			if north == south and south == west and west == east and east != center:
				isolated += 1
	var isolated_ratio := float(isolated) / float(maxi(compared, 1))
	if isolated_ratio > 0.01:
		_fail(failures, "Resolved blend contains isolated single-block biome speckle: %.6f" % isolated_ratio)


static func _validate_surfaces_and_trees(data, fixtures: Dictionary, failures: Array[String]) -> void:
	var surfaces := [
		WORLD_DATA.BLOCK_GRASS,
		WORLD_DATA.BLOCK_GRASS,
		WORLD_DATA.BLOCK_SAND,
		WORLD_DATA.BLOCK_STONE,
	]
	var subsurfaces := [
		WORLD_DATA.BLOCK_DIRT,
		WORLD_DATA.BLOCK_DIRT,
		WORLD_DATA.BLOCK_SAND,
		WORLD_DATA.BLOCK_STONE,
	]
	for biome in range(WORLD_DATA.BIOME_COUNT):
		if not fixtures.has(biome):
			continue
		var point: Vector2i = fixtures[biome]
		var samples: Vector4 = data.sample_column_noise(point.x, point.y)
		var height: int = data.terrain_height_from_samples(samples)
		var resolved: int = data.blended_biome_from_samples(samples, point.x, point.y)
		if resolved != biome:
			_fail(failures, "Fixture changed resolved biome during surface validation")
			continue
		if data.get_block(Vector3i(point.x, height, point.y)) != surfaces[biome]:
			_fail(failures, "Wrong blended surface block for biome %s" % data.biome_name(biome))
		if data.get_block(Vector3i(point.x, height - 1, point.y)) != subsurfaces[biome]:
			_fail(failures, "Wrong blended subsurface block for biome %s" % data.biome_name(biome))

	var candidates := PackedInt32Array()
	var origins := PackedInt32Array()
	candidates.resize(WORLD_DATA.BIOME_COUNT)
	origins.resize(WORLD_DATA.BIOME_COUNT)
	var supplemental := 0
	var first_origin: Dictionary = {}
	for z in range(-384, 385):
		for x in range(-384, 385):
			var baseline_grid := (
				posmod(x, WORLD_DATA.TREE_SPACING) == WORLD_DATA.TREE_OFFSET
				and posmod(z, WORLD_DATA.TREE_SPACING) == WORLD_DATA.TREE_OFFSET
			)
			var forest_grid := (
				posmod(x, WORLD_DATA.FOREST_TREE_SPACING) == WORLD_DATA.FOREST_TREE_OFFSET
				and posmod(z, WORLD_DATA.FOREST_TREE_SPACING) == WORLD_DATA.FOREST_TREE_OFFSET
			)
			if not baseline_grid and not forest_grid:
				continue
			var samples: Vector4 = data.sample_column_noise(x, z)
			var height: int = data.terrain_height_from_samples(samples)
			var biome: int = data.blended_biome_from_samples(samples, x, z)
			candidates[biome] += 1
			if not data.is_tree_origin_for_biome(x, z, height, biome):
				continue
			origins[biome] += 1
			if not first_origin.has(biome):
				first_origin[biome] = Vector2i(x, z)
			if biome == WORLD_DATA.BIOME_FOREST and forest_grid and not baseline_grid:
				supplemental += 1
	if origins[WORLD_DATA.BIOME_PLAINS] <= 0:
		_fail(failures, "Blending removed all deterministic plains trees")
	if origins[WORLD_DATA.BIOME_FOREST] <= 0 or supplemental <= 0:
		_fail(failures, "Blended forest did not retain its denser supplemental tree lattice")
	if origins[WORLD_DATA.BIOME_DESERT] != 0 or origins[WORLD_DATA.BIOME_ROCKY] != 0:
		_fail(failures, "Blended desert or rocky columns generated a tree origin")
	var plains_rate := float(origins[WORLD_DATA.BIOME_PLAINS]) / float(maxi(candidates[WORLD_DATA.BIOME_PLAINS], 1))
	var forest_rate := float(origins[WORLD_DATA.BIOME_FOREST]) / float(maxi(candidates[WORLD_DATA.BIOME_FOREST], 1))
	if forest_rate <= plains_rate:
		_fail(failures, "Blended forest tree density is not greater than plains")
	for biome in [WORLD_DATA.BIOME_PLAINS, WORLD_DATA.BIOME_FOREST]:
		if not first_origin.has(biome):
			continue
		var point: Vector2i = first_origin[biome]
		var surface: int = data.terrain_height(point.x, point.y)
		if data.get_block(Vector3i(point.x, surface, point.y)) != WORLD_DATA.BLOCK_GRASS:
			_fail(failures, "Blended tree root is not valid grass in biome %s" % data.biome_name(biome))
		if data.get_block(Vector3i(point.x, surface + 1, point.y)) != WORLD_DATA.BLOCK_LOG:
			_fail(failures, "Blended tree origin did not produce a trunk in biome %s" % data.biome_name(biome))


static func _write_diagnostics(data, failures: Array[String]) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var weight_image := Image.create(DIAG_SIZE, DIAG_SIZE, false, Image.FORMAT_RGB8)
	var resolved_image := Image.create(DIAG_SIZE, DIAG_SIZE, false, Image.FORMAT_RGB8)
	var palette: Array[Color] = [
		Color(0.43, 0.72, 0.28),
		Color(0.12, 0.42, 0.16),
		Color(0.88, 0.74, 0.42),
		Color(0.48, 0.50, 0.54),
	]
	for pixel_z in range(DIAG_SIZE):
		var world_z := (pixel_z - int(DIAG_SIZE / 2)) * DIAG_SCALE
		for pixel_x in range(DIAG_SIZE):
			var world_x := (pixel_x - int(DIAG_SIZE / 2)) * DIAG_SCALE
			var samples: Vector4 = data.sample_column_noise(world_x, world_z)
			var weights: Vector4 = data.biome_weights_from_samples(samples)
			var weighted_color := (
				palette[0] * weights.x
				+ palette[1] * weights.y
				+ palette[2] * weights.z
				+ palette[3] * weights.w
			)
			var resolved: int = data.blended_biome_from_weights(weights, world_x, world_z)
			weight_image.set_pixel(pixel_x, pixel_z, weighted_color)
			resolved_image.set_pixel(pixel_x, pixel_z, palette[resolved])
	var weight_error := weight_image.save_png(WEIGHT_DIAG_PATH)
	if weight_error != OK:
		_fail(failures, "Failed to write Step 4 weight diagnostic: %s" % error_string(weight_error))
	var resolved_error := resolved_image.save_png(RESOLVED_DIAG_PATH)
	if resolved_error != OK:
		_fail(failures, "Failed to write Step 4 resolved diagnostic: %s" % error_string(resolved_error))


static func _fail(failures: Array[String], message: String) -> void:
	if not failures.has(message):
		failures.append(message)
