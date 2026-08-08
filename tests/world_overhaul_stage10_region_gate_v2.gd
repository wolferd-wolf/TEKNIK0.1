extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage10_region_data.gd")
const STAGE9_CACHE := preload("res://scripts/world/playable_world_stage9_cache_fast.gd")
const STAGE10_CACHE := preload("res://scripts/world/playable_world_stage10_cache_fast.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := 16
const P95_LIMIT_USEC := 1000
const TRANSITION_PREP_P95_LIMIT_USEC := 300
const WARMUPS := 4
const REPEATS := 20
const MAP_SPACING := 2
const MAP_DIAMETER := 49

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var runtime = RUNTIME.new()
	var contract: Dictionary = _validate_contract()
	var synthetic: Dictionary = _validate_synthetic(data)
	var equivalence: Dictionary = _validate_stage9_equivalence(data, runtime)
	var world_audit: Dictionary = _audit_world(data)
	var regional: Dictionary = _audit_regions(data)
	var seams: Dictionary = _validate_seams(runtime, data)
	var determinism: Dictionary = _validate_determinism(data)
	var benchmark: Dictionary = _benchmark(runtime)
	var transition_benchmark: Dictionary = _benchmark_transition_preparation(runtime, data)
	if int(benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail(
			"Stage 10 generation exceeded the 1.0 ms p95 gate: %d usec"
			% int(benchmark["p95_usec"])
		)
	if int(transition_benchmark["p95_usec"]) >= TRANSITION_PREP_P95_LIMIT_USEC:
		_fail(
			"Stage 10 transition preparation exceeded 0.3 ms p95: %d usec"
			% int(transition_benchmark["p95_usec"])
		)
	runtime.free()

	var report := {
		"contract": contract,
		"synthetic": synthetic,
		"stage9_equivalence": equivalence,
		"world_audit": world_audit,
		"regional_2_block": regional,
		"seams": seams,
		"determinism": determinism,
		"benchmark": benchmark,
		"transition_preparation_benchmark": transition_benchmark,
		"generation_p95_limit_usec": P95_LIMIT_USEC,
		"transition_prep_p95_limit_usec": TRANSITION_PREP_P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE10_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE10_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _validate_contract() -> Dictionary:
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 10 lost the 150-block legal world height")
	if DATA.STAGE8_ACTIVE_BIOME_COUNT != 6:
		_fail("Stage 10 changed the six accepted Stage 8 ecology IDs")
	if DATA.STAGE9_TERRAIN_MODIFIER_COUNT != 5:
		_fail("Stage 10 changed the accepted Stage 9 terrain modifier contract")
	if DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY != 0.0012:
		_fail("Stage 10 changed the broad temperature field frequency")
	if DATA.BIOME_MOISTURE_NOISE_FREQUENCY != 0.0014:
		_fail("Stage 10 changed the broad moisture field frequency")
	if DATA.STAGE10_TRANSITION_SCORE_WIDTH <= 0.0:
		_fail("Stage 10 transition score width is not positive")

	var data_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage10_region_data.gd"
	)
	var cache_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage10_cache_fast.gd"
	)
	if data_source.contains("FastNoiseLite.new") or cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 10 added a new noise stack")
	if cache_source.contains("get_noise_2d"):
		_fail("Stage 10 resamples noise instead of reusing cached climate fields")
	if not cache_source.contains("STAGE9_CACHE.build"):
		_fail("Stage 10 generation cache is no longer Stage 9-equivalent")
	if not cache_source.contains("build_transition_codes"):
		_fail("Stage 10 no longer separates expression transition preparation")

	return {
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"base_ecology_count": DATA.STAGE8_ACTIVE_BIOME_COUNT,
		"terrain_modifier_count": DATA.STAGE9_TERRAIN_MODIFIER_COUNT,
		"temperature_frequency": DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY,
		"moisture_frequency": DATA.BIOME_MOISTURE_NOISE_FREQUENCY,
		"transition_score_width": DATA.STAGE10_TRANSITION_SCORE_WIDTH,
		"transition_levels": DATA.STAGE10_TRANSITION_LEVELS,
		"transition_prep_phase": "post-cache mesh preparation",
	}


func _validate_synthetic(data) -> Dictionary:
	var plains_side := Vector2(0.0, 0.179)
	var forest_side := Vector2(0.0, 0.181)
	var plains_biome: int = data.stage8_classify_climate(plains_side, DATA.WATER_NONE)
	var forest_biome: int = data.stage8_classify_climate(forest_side, DATA.WATER_NONE)
	var plains_code: int = data.stage10_transition_code_for_climate(plains_side, DATA.WATER_NONE)
	var forest_code: int = data.stage10_transition_code_for_climate(forest_side, DATA.WATER_NONE)
	if plains_biome != DATA.BIOME_PLAINS:
		_fail("Stage 10 changed the Plains side of the Plains/Forest climate boundary")
	if forest_biome != DATA.BIOME_FOREST:
		_fail("Stage 10 changed the Forest side of the Plains/Forest climate boundary")
	if data.stage10_transition_partner(plains_code) != DATA.BIOME_FOREST:
		_fail("Stage 10 Plains boundary does not transition toward Forest")
	if data.stage10_transition_partner(forest_code) != DATA.BIOME_PLAINS:
		_fail("Stage 10 Forest boundary does not transition toward Plains")
	if data.stage10_transition_level(plains_code) < DATA.STAGE10_TRANSITION_LEVELS - 2:
		_fail("Stage 10 Plains-side boundary strength is unexpectedly weak")
	if data.stage10_transition_level(forest_code) < DATA.STAGE10_TRANSITION_LEVELS - 2:
		_fail("Stage 10 Forest-side boundary strength is unexpectedly weak")
	if data.stage10_transition_code_for_climate(plains_side, DATA.WATER_RIVER) != 0:
		_fail("Stage 10 emits transition metadata on physical water")
	var interior_code: int = data.stage10_transition_code_for_climate(
		DATA.STAGE8_DENSE_FOREST_TARGET, DATA.WATER_NONE
	)
	if interior_code != 0:
		_fail("Stage 10 marks a biome prototype center as a transition zone")
	return {
		"plains_side_biome": plains_biome,
		"plains_side_partner": data.stage10_transition_partner(plains_code),
		"plains_side_level": data.stage10_transition_level(plains_code),
		"forest_side_biome": forest_biome,
		"forest_side_partner": data.stage10_transition_partner(forest_code),
		"forest_side_level": data.stage10_transition_level(forest_code),
		"dense_target_transition_code": interior_code,
	}


func _validate_stage9_equivalence(data, runtime) -> Dictionary:
	var coords: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(4, -3),
		Vector2i(-7, 6),
		Vector2i(15, 12),
	]
	var comparisons: int = 0
	var transition_columns: int = 0
	for coord: Vector2i in coords:
		var stage9: Dictionary = STAGE9_CACHE.build(coord, data)
		var stage10: Dictionary = runtime._build_column_caches(coord)
		for key in ["heights", "biomes", "stage7_water_types", "stage9_terrain_modifiers"]:
			if stage9.get(key) != stage10.get(key):
				_fail("Stage 10 changed Stage 9 cache output '%s' in chunk %s" % [key, coord])
		var transitions: PackedByteArray = STAGE10_CACHE.build_transition_codes(stage10, data)
		if transitions.size() != WIDTH * WIDTH:
			_fail("Stage 10 transition preparation has the wrong padded size in chunk %s" % coord)
			continue
		var water_types: PackedByteArray = stage10.get("stage7_water_types", PackedByteArray())
		var origin_x: int = coord.x * CHUNK_SIZE
		var origin_z: int = coord.y * CHUNK_SIZE
		for local_z in range(CHUNK_SIZE):
			for local_x in range(CHUNK_SIZE):
				var index: int = (local_z + PADDING) * WIDTH + local_x + PADDING
				var world_x: int = origin_x + local_x
				var world_z: int = origin_z + local_z
				var expected: int = data.stage10_transition_code_at(world_x, world_z)
				if int(transitions[index]) != expected:
					_fail("Stage 10 prepared/direct transition mismatch at (%d,%d)" % [world_x, world_z])
				if int(water_types[index]) != DATA.WATER_NONE and int(transitions[index]) != 0:
					_fail("Stage 10 transition metadata leaked onto water at (%d,%d)" % [world_x, world_z])
				comparisons += 1
				transition_columns += 1
	return {
		"chunks": coords.size(),
		"stage9_array_contracts": 4,
		"direct_transition_comparisons": comparisons,
		"transition_columns": transition_columns,
	}


func _cached_slope(cache_x: int, cache_z: int, heights: PackedInt32Array) -> float:
	var index: int = cache_z * WIDTH + cache_x
	var center: int = int(heights[index])
	var slope: int = 0
	slope = maxi(slope, absi(int(heights[index - 1]) - center))
	slope = maxi(slope, absi(int(heights[index + 1]) - center))
	slope = maxi(slope, absi(int(heights[index - WIDTH]) - center))
	slope = maxi(slope, absi(int(heights[index + WIDTH]) - center))
	return float(slope)


func _audit_world(data) -> Dictionary:
	var chunk_axis: Array[int] = [-128, -96, -64, -32, 0, 32, 64, 96, 128]
	var biome_counts := PackedInt32Array()
	biome_counts.resize(DATA.STAGE8_MAX_BIOME_ID + 1)
	var land_columns: int = 0
	var water_columns: int = 0
	var transition_columns: int = 0
	var transition_pairs: Dictionary = {}
	var tree_expression_changes: int = 0
	var ground_expression_changes: int = 0
	var transition_tree_candidates: int = 0
	var interior_tree_candidates: int = 0

	for chunk_z: int in chunk_axis:
		for chunk_x: int in chunk_axis:
			var coord := Vector2i(chunk_x, chunk_z)
			var cache: Dictionary = STAGE10_CACHE.build(coord, data)
			var transitions: PackedByteArray = STAGE10_CACHE.build_transition_codes(cache, data)
			var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
			var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
			var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
			var modifiers: PackedByteArray = cache.get("stage9_terrain_modifiers", PackedByteArray())
			if transitions.size() != WIDTH * WIDTH:
				_fail("Stage 10 broad audit encountered malformed transition preparation")
				continue
			var origin_x: int = coord.x * CHUNK_SIZE
			var origin_z: int = coord.y * CHUNK_SIZE
			for cache_z in range(PADDING, PADDING + CHUNK_SIZE):
				for cache_x in range(PADDING, PADDING + CHUNK_SIZE):
					var index: int = cache_z * WIDTH + cache_x
					if int(water_types[index]) != DATA.WATER_NONE:
						water_columns += 1
						if int(transitions[index]) != 0:
							_fail("Stage 10 broad audit found transition metadata on water")
						continue
					land_columns += 1
					var biome: int = int(biomes[index])
					if biome >= 0 and biome < biome_counts.size():
						biome_counts[biome] += 1
					var code: int = int(transitions[index])
					var world_x: int = origin_x + cache_x - PADDING
					var world_z: int = origin_z + cache_z - PADDING
					var surface: int = int(heights[index])
					var modifier: int = int(modifiers[index])
					var slope: float = _cached_slope(cache_x, cache_z, heights)
					var stage9_tree: bool = data.stage9_tree_candidate_for_biome(
						world_x, world_z, surface, biome, modifier, slope
					)
					var stage10_tree: bool = data.stage10_tree_candidate_for_biome(
						world_x, world_z, surface, biome, code, modifier, slope
					)
					if code != 0:
						transition_columns += 1
						var partner: int = data.stage10_transition_partner(code)
						if partner == biome or partner < 0:
							_fail("Stage 10 transition partner is invalid at (%d,%d)" % [world_x, world_z])
						var pair_key: String = "%d>%d" % [biome, partner]
						transition_pairs[pair_key] = int(transition_pairs.get(pair_key, 0)) + 1
						if stage10_tree:
							transition_tree_candidates += 1
					else:
						if stage10_tree:
							interior_tree_candidates += 1
					if stage9_tree != stage10_tree:
						tree_expression_changes += 1
					var top_cell := Vector3i(world_x, surface, world_z)
					var stage9_surface: int = data.stage9_surface_block(
						top_cell, surface, biome, modifier, slope
					)
					var stage10_surface: int = data.stage10_surface_block(
						top_cell, surface, biome, code, modifier, slope
					)
					if stage9_surface != stage10_surface:
						ground_expression_changes += 1

	var plains_land: int = int(biome_counts[DATA.BIOME_PLAINS])
	var plains_ratio: float = float(plains_land) / float(maxi(1, land_columns))
	var transition_ratio: float = float(transition_columns) / float(maxi(1, land_columns))
	if plains_ratio < 0.20:
		_fail("Stage 10 Plains no longer occupies a substantial land region")
	if transition_ratio < 0.01:
		_fail("Stage 10 transition zones are too narrow to be meaningful")
	if transition_ratio > 0.35:
		_fail("Stage 10 transition zones consume too much of the land area")
	if transition_pairs.size() < 3:
		_fail("Stage 10 transition metadata does not span enough ecology boundaries")
	if tree_expression_changes <= 0:
		_fail("Stage 10 transition metadata never changes vegetation expression")
	if ground_expression_changes <= 0:
		_fail("Stage 10 transition metadata never changes ground-decoration expression")

	return {
		"land_columns": land_columns,
		"water_columns": water_columns,
		"biome_counts": biome_counts,
		"plains_land_ratio": plains_ratio,
		"transition_columns": transition_columns,
		"transition_land_ratio": transition_ratio,
		"transition_pair_count": transition_pairs.size(),
		"transition_pairs": transition_pairs,
		"tree_expression_changes": tree_expression_changes,
		"ground_expression_changes": ground_expression_changes,
		"transition_tree_candidates": transition_tree_candidates,
		"interior_tree_candidates": interior_tree_candidates,
	}


func _component_stats(grid: PackedInt32Array, diameter: int) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(grid.size())
	var component_count: int = 0
	var tiny_cells: int = 0
	var largest: int = 0
	for start in range(grid.size()):
		if visited[start] != 0:
			continue
		component_count += 1
		var biome: int = int(grid[start])
		var queue: Array[int] = [start]
		visited[start] = 1
		var head: int = 0
		var size: int = 0
		while head < queue.size():
			var index: int = queue[head]
			head += 1
			size += 1
			var x: int = index % diameter
			var z: int = floori(float(index) / float(diameter))
			for neighbor in [
				index - 1 if x > 0 else -1,
				index + 1 if x < diameter - 1 else -1,
				index - diameter if z > 0 else -1,
				index + diameter if z < diameter - 1 else -1,
			]:
				var next_index: int = int(neighbor)
				if next_index < 0 or visited[next_index] != 0:
					continue
				if int(grid[next_index]) != biome:
					continue
				visited[next_index] = 1
				queue.append(next_index)
		largest = maxi(largest, size)
		if size <= 2:
			tiny_cells += size
	return {
		"component_count": component_count,
		"tiny_cells": tiny_cells,
		"largest_component": largest,
	}


func _append_transition_runs(mask: PackedByteArray, diameter: int, runs: Array[int]) -> void:
	for z in range(diameter):
		var run: int = 0
		for x in range(diameter):
			if mask[z * diameter + x] != 0:
				run += 1
			elif run > 0:
				runs.append(run)
				run = 0
		if run > 0:
			runs.append(run)
	for x in range(diameter):
		var run: int = 0
		for z in range(diameter):
			if mask[z * diameter + x] != 0:
				run += 1
			elif run > 0:
				runs.append(run)
				run = 0
		if run > 0:
			runs.append(run)


func _audit_regions(data) -> Dictionary:
	var centers: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(157, -16),
		Vector2i(512, 512),
		Vector2i(-512, 256),
		Vector2i(1024, -1024),
		Vector2i(-1536, -768),
	]
	var total_points: int = 0
	var total_edges: int = 0
	var total_transitions: int = 0
	var total_tiny_cells: int = 0
	var total_components: int = 0
	var largest_component: int = 0
	var transition_points: int = 0
	var transition_runs: Array[int] = []

	for center: Vector2i in centers:
		var grid := PackedInt32Array()
		var mask := PackedByteArray()
		grid.resize(MAP_DIAMETER * MAP_DIAMETER)
		mask.resize(MAP_DIAMETER * MAP_DIAMETER)
		var half: int = floori(float(MAP_DIAMETER) * 0.5)
		for gz in range(MAP_DIAMETER):
			for gx in range(MAP_DIAMETER):
				var world_x: int = center.x + (gx - half) * MAP_SPACING
				var world_z: int = center.y + (gz - half) * MAP_SPACING
				var index: int = gz * MAP_DIAMETER + gx
				grid[index] = data.biome_at(world_x, world_z)
				var code: int = data.stage10_transition_code_at(world_x, world_z)
				if code != 0:
					mask[index] = 1
					transition_points += 1
				if gx > 0:
					total_edges += 1
					if grid[index] != grid[index - 1]:
						total_transitions += 1
				if gz > 0:
					total_edges += 1
					if grid[index] != grid[index - MAP_DIAMETER]:
						total_transitions += 1
		var stats: Dictionary = _component_stats(grid, MAP_DIAMETER)
		total_components += int(stats["component_count"])
		total_tiny_cells += int(stats["tiny_cells"])
		largest_component = maxi(largest_component, int(stats["largest_component"]))
		_append_transition_runs(mask, MAP_DIAMETER, transition_runs)
		total_points += grid.size()

	transition_runs.sort()
	var median_run_samples: float = 0.0
	var p75_run_samples: int = 0
	var max_run_samples: int = 0
	if not transition_runs.is_empty():
		var middle: int = floori(float(transition_runs.size()) * 0.5)
		median_run_samples = float(transition_runs[middle])
		var p75_index: int = clampi(ceili(float(transition_runs.size()) * 0.75) - 1, 0, transition_runs.size() - 1)
		p75_run_samples = transition_runs[p75_index]
		max_run_samples = transition_runs[transition_runs.size() - 1]

	var identity_transition_ratio: float = float(total_transitions) / float(maxi(1, total_edges))
	var tiny_ratio: float = float(total_tiny_cells) / float(maxi(1, total_points))
	var transition_point_ratio: float = float(transition_points) / float(maxi(1, total_points))
	var components_per_1000: float = float(total_components) * 1000.0 / float(maxi(1, total_points))
	if identity_transition_ratio > 0.12:
		_fail("Stage 10 shipping biomes show salt-and-pepper identity transitions")
	if tiny_ratio > 0.01:
		_fail("Stage 10 shipping biomes contain too many 1–2 sample islands")
	if components_per_1000 > 20.0:
		_fail("Stage 10 shipping biomes are too fragmented at minimap resolution")
	if largest_component < 300:
		_fail("Stage 10 common biomes do not form large contiguous regions")
	if transition_point_ratio < 0.01:
		_fail("Stage 10 transition bands are not visible at 2-block minimap resolution")
	if transition_point_ratio > 0.35:
		_fail("Stage 10 transition bands are too broad at minimap resolution")
	if transition_runs.is_empty() or median_run_samples < 2.0:
		_fail("Stage 10 transition bands collapse to single minimap samples")
	if max_run_samples < 4:
		_fail("Stage 10 transition bands never become first-person-readable widths")

	return {
		"map_spacing_blocks": MAP_SPACING,
		"view_count": centers.size(),
		"sampled_points": total_points,
		"identity_transition_ratio": identity_transition_ratio,
		"tiny_island_ratio": tiny_ratio,
		"component_count": total_components,
		"components_per_1000": components_per_1000,
		"largest_component_cells": largest_component,
		"transition_point_ratio": transition_point_ratio,
		"transition_run_count": transition_runs.size(),
		"median_transition_run_samples": median_run_samples,
		"median_transition_width_blocks": median_run_samples * MAP_SPACING,
		"p75_transition_run_samples": p75_run_samples,
		"max_transition_run_samples": max_run_samples,
	}


func _cache_index(coord: Vector2i, world_x: int, world_z: int) -> int:
	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING
	return (world_z - min_z) * WIDTH + (world_x - min_x)


func _validate_seams(runtime, data) -> Dictionary:
	var pairs: Array = [
		[Vector2i.ZERO, Vector2i(1, 0)],
		[Vector2i.ZERO, Vector2i(0, 1)],
		[Vector2i(-4, 3), Vector2i(-3, 3)],
		[Vector2i(7, -6), Vector2i(7, -5)],
	]
	var comparisons: int = 0
	for pair in pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var cache_a: Dictionary = runtime._build_column_caches(a)
		var cache_b: Dictionary = runtime._build_column_caches(b)
		var transitions_a: PackedByteArray = STAGE10_CACHE.build_transition_codes(cache_a, data)
		var transitions_b: PackedByteArray = STAGE10_CACHE.build_transition_codes(cache_b, data)
		var min_ax: int = a.x * CHUNK_SIZE - PADDING
		var min_az: int = a.y * CHUNK_SIZE - PADDING
		var max_ax: int = min_ax + WIDTH - 1
		var max_az: int = min_az + WIDTH - 1
		var min_bx: int = b.x * CHUNK_SIZE - PADDING
		var min_bz: int = b.y * CHUNK_SIZE - PADDING
		var max_bx: int = min_bx + WIDTH - 1
		var max_bz: int = min_bz + WIDTH - 1
		for z in range(maxi(min_az, min_bz), mini(max_az, max_bz) + 1):
			for x in range(maxi(min_ax, min_bx), mini(max_ax, max_bx) + 1):
				var ia: int = _cache_index(a, x, z)
				var ib: int = _cache_index(b, x, z)
				for key in ["biomes", "heights", "stage9_terrain_modifiers"]:
					var values_a: Variant = cache_a.get(key)
					var values_b: Variant = cache_b.get(key)
					if values_a[ia] != values_b[ib]:
						_fail("Stage 10 %s seam mismatch at (%d,%d)" % [key, x, z])
				if transitions_a[ia] != transitions_b[ib]:
					_fail("Stage 10 transition seam mismatch at (%d,%d)" % [x, z])
				comparisons += 4
	return {"array_value_comparisons": comparisons}


func _validate_determinism(data) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(9, -11), Vector2i(-17, 5)]
	for coord: Vector2i in coords:
		var first: Dictionary = STAGE10_CACHE.build(coord, data)
		var second: Dictionary = STAGE10_CACHE.build(coord, data)
		for key in ["heights", "biomes", "stage7_water_types", "stage9_terrain_modifiers"]:
			if first.get(key) != second.get(key):
				_fail("Stage 10 cache '%s' is nondeterministic in %s" % [key, coord])
		if STAGE10_CACHE.build_transition_codes(first, data) != STAGE10_CACHE.build_transition_codes(second, data):
			_fail("Stage 10 transition preparation is nondeterministic in %s" % coord)
	return {"chunks": coords.size()}


func _benchmark(runtime) -> Dictionary:
	var coords: Array[Vector2i] = []
	for z in range(-2, 2):
		for x in range(-2, 2):
			coords.append(Vector2i(x, z))
	for _warmup in range(WARMUPS):
		for coord: Vector2i in coords:
			runtime._build_column_caches(coord)
	var values: Array[int] = []
	for _repeat in range(REPEATS):
		for coord: Vector2i in coords:
			var started: int = Time.get_ticks_usec()
			var cache: Dictionary = runtime._build_column_caches(coord)
			var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
			var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
			var checksum: int = 0
			if not heights.is_empty():
				checksum += int(heights[0]) + int(heights[heights.size() - 1])
			if not biomes.is_empty():
				checksum += int(biomes[0]) + int(biomes[biomes.size() - 1])
			if checksum == -2147483648:
				_fail("Impossible Stage 10 benchmark checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	return _benchmark_report(values, "16 padded chunks, 4 warmups, 20 repeats; same 320-sample hard generation gate")


func _benchmark_transition_preparation(runtime, data) -> Dictionary:
	var coords: Array[Vector2i] = []
	var caches: Array[Dictionary] = []
	for z in range(-2, 2):
		for x in range(-2, 2):
			var coord := Vector2i(x, z)
			coords.append(coord)
			caches.append(runtime._build_column_caches(coord))
	for _warmup in range(WARMUPS):
		for cache: Dictionary in caches:
			STAGE10_CACHE.build_transition_codes(cache, data)
	var values: Array[int] = []
	for _repeat in range(REPEATS):
		for cache: Dictionary in caches:
			var started: int = Time.get_ticks_usec()
			var codes: PackedByteArray = STAGE10_CACHE.build_transition_codes(cache, data)
			var checksum: int = 0
			if not codes.is_empty():
				checksum = int(codes[0]) + int(codes[codes.size() - 1])
			if checksum == -2147483648:
				_fail("Impossible Stage 10 transition benchmark checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	return _benchmark_report(values, "16 prepared padded caches, 4 warmups, 20 repeats; expression-preparation timing only")


func _benchmark_report(values: Array[int], methodology: String) -> Dictionary:
	values.sort()
	var total: int = 0
	for value: int in values:
		total += value
	var p95_index: int = clampi(ceili(float(values.size()) * 0.95) - 1, 0, values.size() - 1)
	return {
		"sample_count": values.size(),
		"minimum_usec": values[0],
		"mean_usec": float(total) / float(values.size()),
		"p95_usec": values[p95_index],
		"p95_ms": float(values[p95_index]) / 1000.0,
		"maximum_usec": values[values.size() - 1],
		"methodology": methodology,
	}
