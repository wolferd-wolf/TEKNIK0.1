extends RefCounted

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const SCAN_MIN := -1024
const SCAN_MAX := 1024
const SCAN_STEP := 8
const DIAG_SIZE := 384
const DIAG_SCALE := 5
const DIAG_PATH := "res://artifacts/multi-noise-step3-biomes.png"

static func run(data, failures: Array[String]) -> Dictionary:
	var report := _scan(data, failures)
	_validate_surfaces_and_trees(data, report["fixtures"], failures)
	_write_diagnostic(data, failures)
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
	for row in range(size):
		var z := SCAN_MIN + row * SCAN_STEP
		var left := -1
		for column in range(size):
			var x := SCAN_MIN + column * SCAN_STEP
			var samples: Vector4 = data.sample_column_noise(x, z)
			var biome: int = data.select_biome_from_samples(samples)
			counts[biome] += 1
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
			_fail(failures, "Biome %s is absent or too rare: %d (%.4f)" % [data.biome_name(biome), counts[biome], ratio])
		if not fixtures.has(biome):
			_fail(failures, "No above-water fixture found for biome %s" % data.biome_name(biome))
	var transition_ratio := float(transitions) / float(maxi(edges, 1))
	if transition_ratio <= 0.001 or transition_ratio >= 0.20:
		_fail(failures, "Biome field is missing regional variation or resembles cell noise: %.6f" % transition_ratio)
	return {
		"grid": {"minimum_world_coordinate": SCAN_MIN, "maximum_world_coordinate": SCAN_MAX, "step": SCAN_STEP, "points": points},
		"biome_names": ["plains", "forest", "desert", "rocky"],
		"counts": count_report,
		"ratios": ratios,
		"transition_count": transitions,
		"compared_edges": edges,
		"transition_ratio": transition_ratio,
		"fixtures": fixtures,
	}

static func _validate_surfaces_and_trees(data, fixtures: Dictionary, failures: Array[String]) -> void:
	var surfaces := [WORLD_DATA.BLOCK_GRASS, WORLD_DATA.BLOCK_GRASS, WORLD_DATA.BLOCK_SAND, WORLD_DATA.BLOCK_STONE]
	var subsurfaces := [WORLD_DATA.BLOCK_DIRT, WORLD_DATA.BLOCK_DIRT, WORLD_DATA.BLOCK_SAND, WORLD_DATA.BLOCK_STONE]
	for biome in range(WORLD_DATA.BIOME_COUNT):
		if not fixtures.has(biome):
			continue
		var point: Vector2i = fixtures[biome]
		var samples: Vector4 = data.sample_column_noise(point.x, point.y)
		var height: int = data.terrain_height_from_samples(samples)
		if data.get_block(Vector3i(point.x, height, point.y)) != surfaces[biome]:
			_fail(failures, "Wrong surface block for biome %s" % data.biome_name(biome))
		if data.get_block(Vector3i(point.x, height - 1, point.y)) != subsurfaces[biome]:
			_fail(failures, "Wrong subsurface block for biome %s" % data.biome_name(biome))
	var candidates := PackedInt32Array()
	var origins := PackedInt32Array()
	candidates.resize(WORLD_DATA.BIOME_COUNT)
	origins.resize(WORLD_DATA.BIOME_COUNT)
	var supplemental := 0
	var first_origin: Dictionary = {}
	for z in range(-512, 513):
		for x in range(-512, 513):
			var baseline_grid := posmod(x, WORLD_DATA.TREE_SPACING) == WORLD_DATA.TREE_OFFSET and posmod(z, WORLD_DATA.TREE_SPACING) == WORLD_DATA.TREE_OFFSET
			var forest_grid := posmod(x, WORLD_DATA.FOREST_TREE_SPACING) == WORLD_DATA.FOREST_TREE_OFFSET and posmod(z, WORLD_DATA.FOREST_TREE_SPACING) == WORLD_DATA.FOREST_TREE_OFFSET
			if not baseline_grid and not forest_grid:
				continue
			var samples: Vector4 = data.sample_column_noise(x, z)
			var height: int = data.terrain_height_from_samples(samples)
			var biome: int = data.select_biome_from_samples(samples)
			candidates[biome] += 1
			if not data.is_tree_origin_for_biome(x, z, height, biome):
				continue
			origins[biome] += 1
			if not first_origin.has(biome):
				first_origin[biome] = Vector2i(x, z)
			if biome == WORLD_DATA.BIOME_FOREST and forest_grid and not baseline_grid:
				supplemental += 1
	if origins[WORLD_DATA.BIOME_PLAINS] <= 0:
		_fail(failures, "Plains lost all deterministic trees")
	if origins[WORLD_DATA.BIOME_FOREST] <= 0 or supplemental <= 0:
		_fail(failures, "Forest did not add a denser supplemental tree lattice")
	if origins[WORLD_DATA.BIOME_DESERT] != 0 or origins[WORLD_DATA.BIOME_ROCKY] != 0:
		_fail(failures, "Desert or rocky biome generated a tree origin")
	var plains_rate := float(origins[WORLD_DATA.BIOME_PLAINS]) / float(maxi(candidates[WORLD_DATA.BIOME_PLAINS], 1))
	var forest_rate := float(origins[WORLD_DATA.BIOME_FOREST]) / float(maxi(candidates[WORLD_DATA.BIOME_FOREST], 1))
	if forest_rate <= plains_rate:
		_fail(failures, "Forest tree density is not greater than plains")
	for biome in [WORLD_DATA.BIOME_PLAINS, WORLD_DATA.BIOME_FOREST]:
		if not first_origin.has(biome):
			continue
		var point: Vector2i = first_origin[biome]
		var surface: int = data.terrain_height(point.x, point.y)
		if data.get_block(Vector3i(point.x, surface, point.y)) != WORLD_DATA.BLOCK_GRASS:
			_fail(failures, "Tree root is not valid grass in biome %s" % data.biome_name(biome))
		if data.get_block(Vector3i(point.x, surface + 1, point.y)) != WORLD_DATA.BLOCK_LOG:
			_fail(failures, "Tree origin did not produce a trunk in biome %s" % data.biome_name(biome))

static func _write_diagnostic(data, failures: Array[String]) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var image := Image.create(DIAG_SIZE, DIAG_SIZE, false, Image.FORMAT_RGB8)
	var palette: Array[Color] = [Color(0.43, 0.72, 0.28), Color(0.12, 0.42, 0.16), Color(0.88, 0.74, 0.42), Color(0.48, 0.50, 0.54)]
	for pz in range(DIAG_SIZE):
		var z := (pz - int(DIAG_SIZE / 2)) * DIAG_SCALE
		for px in range(DIAG_SIZE):
			var x := (px - int(DIAG_SIZE / 2)) * DIAG_SCALE
			var biome: int = data.biome_at(x, z)
			image.set_pixel(px, pz, palette[biome])
	var error := image.save_png(DIAG_PATH)
	if error != OK:
		_fail(failures, "Failed to write Step 3 diagnostic: %s" % error_string(error))

static func _fail(failures: Array[String], message: String) -> void:
	if not failures.has(message):
		failures.append(message)
