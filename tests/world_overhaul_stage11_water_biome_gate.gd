extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage11_water_biome_data.gd")
const STAGE10_DATA := preload("res://scripts/world/playable_world_stage10_region_data.gd")
const STAGE10_RUNTIME := preload("res://scripts/world/playable_world_stage10_generation_runtime.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const STAGE11_CACHE := preload("res://scripts/world/playable_world_stage11_cache_fast.gd")
const STAGE10_MESHER := preload("res://scripts/world/playable_world_stage10_mesher.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := 16
const P95_LIMIT_USEC := 1000
const TRANSITION_PREP_P95_LIMIT_USEC := 300
const HYDROLOGY_PREP_P95_LIMIT_USEC := 500
const WARMUPS := 4
const REPEATS := 20

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var runtime = RUNTIME.new()
	var stage10_runtime = STAGE10_RUNTIME.new()
	var contract: Dictionary = _validate_contract(data)
	var synthetic: Dictionary = _validate_synthetic(data)
	var equivalence: Dictionary = _validate_stage10_equivalence(runtime, stage10_runtime)
	var prepared: Dictionary = _validate_prepared_hydrology(runtime, data)
	var feature_margins: Dictionary = _validate_lake_pond_margins(data)
	var world_audit: Dictionary = _audit_world(runtime, data)
	var seams: Dictionary = _validate_seams(runtime, data)
	var determinism: Dictionary = _validate_determinism(runtime, data)
	var benchmark: Dictionary = _benchmark_generation(runtime)
	var transition_benchmark: Dictionary = _benchmark_transition_preparation(runtime, data)
	var hydrology_benchmark: Dictionary = _benchmark_hydrology_preparation(runtime, data)
	if int(benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail(
			"Stage 11 generation exceeded the 1.0 ms p95 gate: %d usec"
			% int(benchmark["p95_usec"])
		)
	if int(transition_benchmark["p95_usec"]) >= TRANSITION_PREP_P95_LIMIT_USEC:
		_fail(
			"Stage 11 regressed Stage 10 transition preparation above 0.3 ms p95: %d usec"
			% int(transition_benchmark["p95_usec"])
		)
	if int(hydrology_benchmark["p95_usec"]) >= HYDROLOGY_PREP_P95_LIMIT_USEC:
		_fail(
			"Stage 11 hydrology preparation exceeded 0.5 ms p95: %d usec"
			% int(hydrology_benchmark["p95_usec"])
		)
	runtime.free()
	stage10_runtime.free()

	var report := {
		"contract": contract,
		"synthetic": synthetic,
		"stage10_equivalence": equivalence,
		"prepared_hydrology": prepared,
		"feature_margins": feature_margins,
		"world_audit": world_audit,
		"seams": seams,
		"determinism": determinism,
		"benchmark": benchmark,
		"transition_preparation_benchmark": transition_benchmark,
		"hydrology_preparation_benchmark": hydrology_benchmark,
		"generation_p95_limit_usec": P95_LIMIT_USEC,
		"transition_prep_p95_limit_usec": TRANSITION_PREP_P95_LIMIT_USEC,
		"hydrology_prep_p95_limit_usec": HYDROLOGY_PREP_P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE11_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE11_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _validate_contract(data) -> Dictionary:
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 11 lost the 150-block legal world height")
	if DATA.STAGE8_ACTIVE_BIOME_COUNT != 6:
		_fail("Stage 11 changed the six accepted Stage 8 ecology IDs")
	if DATA.STAGE9_TERRAIN_MODIFIER_COUNT != 5:
		_fail("Stage 11 changed the accepted Stage 9 terrain modifiers")
	if DATA.STAGE11_HYDROLOGY_MODIFIER_COUNT != 5:
		_fail("Stage 11 hydrology modifier contract is not none/coast/river/lake/pond")
	if DATA.STAGE11_WATER_MARGIN_RADIUS != 1:
		_fail("Stage 11 water margin no longer matches the accepted one-cell padded-cache design")

	var data_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage11_water_biome_data.gd"
	)
	var cache_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage11_cache_fast.gd"
	)
	var runtime_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_generation_runtime.gd"
	)
	if data_source.contains("FastNoiseLite.new") or cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 11 added a new procedural noise stack")
	if cache_source.contains("get_noise_2d"):
		_fail("Stage 11 hydrology expression resamples noise instead of using cached water ownership")
	if not runtime_source.contains("SHIPPING_STAGE10_GENERATION_CACHE.build"):
		_fail("Stage 11 no longer preserves the exact Stage 10 generation cache")
	if not runtime_source.contains("build_hydrology_codes"):
		_fail("Stage 11 runtime is not preparing explicit hydrology expression metadata")

	return {
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"base_ecology_count": DATA.STAGE8_ACTIVE_BIOME_COUNT,
		"terrain_modifier_count": DATA.STAGE9_TERRAIN_MODIFIER_COUNT,
		"hydrology_modifier_count": DATA.STAGE11_HYDROLOGY_MODIFIER_COUNT,
		"water_margin_radius": DATA.STAGE11_WATER_MARGIN_RADIUS,
		"generation_base": "exact Stage 10 generation cache",
		"hydrology_phase": "post-cache expression preparation",
	}


func _validate_synthetic(data) -> Dictionary:
	var transition_code: int = 0
	var terrain_none: int = DATA.TERRAIN_MODIFIER_NONE
	var river_top := Vector3i(7, 20, 9)
	var river_surface: int = data.stage11_surface_block(
		river_top,
		20,
		DATA.BIOME_DESERT,
		transition_code,
		terrain_none,
		0.0,
		DATA.HYDROLOGY_MODIFIER_RIVERBANK
	)
	if river_surface != DATA.BLOCK_GRASS:
		_fail("Stage 11 desert riverbank did not become hydrated grass")
	var river_subsoil: int = data.stage11_surface_block(
		Vector3i(7, 19, 9),
		20,
		DATA.BIOME_DESERT,
		transition_code,
		terrain_none,
		0.0,
		DATA.HYDROLOGY_MODIFIER_RIVERBANK
	)
	if river_subsoil != DATA.BLOCK_DIRT:
		_fail("Stage 11 hydrated desert bank did not replace shallow sand with dirt")

	var beach_height: int = DATA.SEA_LEVEL + 2
	var beach_surface: int = data.stage11_surface_block(
		Vector3i(5, beach_height, 5),
		beach_height,
		DATA.BIOME_FOREST,
		0,
		terrain_none,
		0.0,
		DATA.HYDROLOGY_MODIFIER_COAST
	)
	if beach_surface != DATA.BLOCK_SAND:
		_fail("Stage 11 gentle low coast did not become beach sand")

	var inland_cell := Vector3i(13, 24, 17)
	var stage10_inland: int = data.stage10_surface_block(
		inland_cell,
		24,
		DATA.BIOME_DRY_GRASSLAND,
		0,
		terrain_none,
		0.0
	)
	var stage11_inland: int = data.stage11_surface_block(
		inland_cell,
		24,
		DATA.BIOME_DRY_GRASSLAND,
		0,
		terrain_none,
		0.0,
		DATA.HYDROLOGY_MODIFIER_NONE
	)
	if stage10_inland != stage11_inland:
		_fail("Stage 11 changed inland Stage 10 surface expression")

	var mountain_surface: int = data.stage11_surface_block(
		Vector3i(0, 70, 0),
		70,
		DATA.BIOME_FOREST,
		0,
		DATA.TERRAIN_MODIFIER_MOUNTAIN,
		4.0,
		DATA.HYDROLOGY_MODIFIER_RIVERBANK
	)
	if mountain_surface != DATA.BLOCK_STONE:
		_fail("Stage 11 water expression overrode a geological mountain cliff")

	return {
		"riverbank_desert_top": river_surface,
		"riverbank_desert_subsoil": river_subsoil,
		"coast_beach_top": beach_surface,
		"inland_stage10_equivalent": stage10_inland == stage11_inland,
		"mountain_cliff_top": mountain_surface,
	}


func _validate_stage10_equivalence(runtime, stage10_runtime) -> Dictionary:
	var coords: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(4, -3),
		Vector2i(-7, 8),
		Vector2i(13, -11),
	]
	var array_contracts: int = 0
	for coord: Vector2i in coords:
		var current: Dictionary = runtime._build_column_caches(coord)
		var frozen: Dictionary = stage10_runtime._build_column_caches(coord)
		for key in ["world_fields", "heights", "biomes", "stage7_water_types", "stage9_terrain_modifiers"]:
			if current.get(key) != frozen.get(key):
				_fail("Stage 11 changed Stage 10 generation cache '%s' in %s" % [key, coord])
			else:
				array_contracts += 1
	return {
		"chunks": coords.size(),
		"array_contracts": array_contracts,
	}


func _expected_water_type_for_hydrology(code: int) -> int:
	match code:
		DATA.HYDROLOGY_MODIFIER_COAST:
			return DATA.WATER_OCEAN
		DATA.HYDROLOGY_MODIFIER_RIVERBANK:
			return DATA.WATER_RIVER
		DATA.HYDROLOGY_MODIFIER_LAKESIDE:
			return DATA.WATER_LAKE
		DATA.HYDROLOGY_MODIFIER_PONDSIDE:
			return DATA.WATER_POND
		_:
			return DATA.WATER_NONE


func _cache_has_neighbor_water(
	water_types: PackedByteArray,
	index: int,
	width: int,
	expected_water: int
) -> bool:
	var x: int = index % width
	var z: int = int(index / width)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			if int(water_types[(z + dz) * width + x + dx]) == expected_water:
				return true
	return false


func _validate_prepared_hydrology(runtime, data) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(5, 2), Vector2i(-6, -4), Vector2i(9, -7)]
	var direct_comparisons: int = 0
	var adjacency_checks: int = 0
	var water_leaks: int = 0
	for coord: Vector2i in coords:
		var cache: Dictionary = runtime._build_column_caches(coord)
		var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
		var hydrology: PackedByteArray = STAGE11_CACHE.build_hydrology_codes(cache, data)
		for local_z in range(CHUNK_SIZE):
			for local_x in range(CHUNK_SIZE):
				var cache_x: int = local_x + PADDING
				var cache_z: int = local_z + PADDING
				var index: int = cache_z * WIDTH + cache_x
				var world_x: int = coord.x * CHUNK_SIZE + local_x
				var world_z: int = coord.y * CHUNK_SIZE + local_z
				var code: int = int(hydrology[index])
				if int(water_types[index]) != DATA.WATER_NONE:
					if code != DATA.HYDROLOGY_MODIFIER_NONE:
						water_leaks += 1
					continue
				var direct: int = data.stage11_hydrology_modifier_at(world_x, world_z)
				direct_comparisons += 1
				if code != direct:
					_fail(
						"Stage 11 prepared/direct hydrology mismatch at (%d,%d): %d != %d"
						% [world_x, world_z, code, direct]
					)
				if code != DATA.HYDROLOGY_MODIFIER_NONE:
					adjacency_checks += 1
					var expected_water: int = _expected_water_type_for_hydrology(code)
					if not _cache_has_neighbor_water(water_types, index, WIDTH, expected_water):
						_fail("Stage 11 hydrology modifier has no matching adjacent physical water")
	if water_leaks != 0:
		_fail("Stage 11 assigned land hydrology modifiers to %d physical-water columns" % water_leaks)
	return {
		"direct_comparisons": direct_comparisons,
		"adjacency_checks": adjacency_checks,
		"water_leaks": water_leaks,
	}


func _find_feature(data, water_type: int) -> Dictionary:
	for cell_z in range(-10, 11):
		for cell_x in range(-10, 11):
			var feature: Dictionary
			if water_type == DATA.WATER_LAKE:
				feature = data.stage6_lake_candidate(cell_x, cell_z)
			else:
				feature = data.stage6_pond_candidate(cell_x, cell_z)
			if not feature.is_empty():
				return feature
	return {}


func _find_feature_margin(data, feature: Dictionary, expected_hydrology: int) -> Vector2i:
	if feature.is_empty():
		return Vector2i(2147483647, 2147483647)
	var center_x: int = int(feature["center_x"])
	var center_z: int = int(feature["center_z"])
	var radius: int = ceili(maxf(float(feature["radius_x"]), float(feature["radius_z"]))) + 3
	for z in range(center_z - radius, center_z + radius + 1):
		for x in range(center_x - radius, center_x + radius + 1):
			if data.water_type_at(x, z) != DATA.WATER_NONE:
				continue
			if data.stage11_hydrology_modifier_at(x, z) == expected_hydrology:
				return Vector2i(x, z)
	return Vector2i(2147483647, 2147483647)


func _validate_lake_pond_margins(data) -> Dictionary:
	var lake: Dictionary = _find_feature(data, DATA.WATER_LAKE)
	var pond: Dictionary = _find_feature(data, DATA.WATER_POND)
	if lake.is_empty():
		_fail("Stage 11 fixed-seed search found no accepted Stage 6 lake")
	if pond.is_empty():
		_fail("Stage 11 fixed-seed search found no accepted Stage 6 pond")
	var lake_margin: Vector2i = _find_feature_margin(
		data, lake, DATA.HYDROLOGY_MODIFIER_LAKESIDE
	)
	var pond_margin: Vector2i = _find_feature_margin(
		data, pond, DATA.HYDROLOGY_MODIFIER_PONDSIDE
	)
	if lake_margin.x == 2147483647:
		_fail("Stage 11 could not find a lakeside land margin around an accepted lake")
	if pond_margin.x == 2147483647:
		_fail("Stage 11 could not find a pondside land margin around an accepted pond")
	return {
		"lake_found": not lake.is_empty(),
		"pond_found": not pond.is_empty(),
		"lake_margin": [lake_margin.x, lake_margin.y],
		"pond_margin": [pond_margin.x, pond_margin.y],
	}


func _audit_world(runtime, data) -> Dictionary:
	var hydrology_counts: Array[int] = [0, 0, 0, 0, 0]
	var surface_changes: Array[int] = [0, 0, 0, 0, 0]
	var tree_changes: Array[int] = [0, 0, 0, 0, 0]
	var land_columns: int = 0
	var water_columns: int = 0
	var adjacency_failures: int = 0
	for chunk_z in range(-8, 9):
		for chunk_x in range(-8, 9):
			var coord := Vector2i(chunk_x, chunk_z)
			var cache: Dictionary = runtime._build_column_caches(coord)
			var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
			var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
			var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
			var terrain_modifiers: PackedByteArray = cache.get("stage9_terrain_modifiers", PackedByteArray())
			var transitions: PackedByteArray = STAGE11_CACHE.build_transition_codes(cache, data)
			var hydrology: PackedByteArray = STAGE11_CACHE.build_hydrology_codes(cache, data)
			for local_z in range(CHUNK_SIZE):
				for local_x in range(CHUNK_SIZE):
					var cache_x: int = local_x + PADDING
					var cache_z: int = local_z + PADDING
					var index: int = cache_z * WIDTH + cache_x
					var water_type: int = int(water_types[index])
					if water_type != DATA.WATER_NONE:
						water_columns += 1
						if int(hydrology[index]) != DATA.HYDROLOGY_MODIFIER_NONE:
							adjacency_failures += 1
						continue
					land_columns += 1
					var hydro: int = int(hydrology[index])
					if hydro < 0 or hydro >= hydrology_counts.size():
						_fail("Stage 11 emitted an invalid hydrology modifier ID %d" % hydro)
						continue
					hydrology_counts[hydro] += 1
					if hydro == DATA.HYDROLOGY_MODIFIER_NONE:
						continue
					var expected_water: int = _expected_water_type_for_hydrology(hydro)
					if not _cache_has_neighbor_water(water_types, index, WIDTH, expected_water):
						adjacency_failures += 1
					var world_x: int = coord.x * CHUNK_SIZE + local_x
					var world_z: int = coord.y * CHUNK_SIZE + local_z
					var surface: int = int(heights[index])
					var biome: int = int(biomes[index])
					var terrain_modifier: int = int(terrain_modifiers[index])
					var transition: int = int(transitions[index])
					var slope: float = STAGE10_MESHER._cached_slope(
						cache_x, cache_z, heights, WIDTH
					)
					var cell := Vector3i(world_x, surface, world_z)
					var old_surface: int = data.stage10_surface_block(
						cell, surface, biome, transition, terrain_modifier, slope
					)
					var new_surface: int = data.stage11_surface_block(
						cell, surface, biome, transition, terrain_modifier, slope, hydro
					)
					if old_surface != new_surface:
						surface_changes[hydro] += 1
					var old_tree: bool = data.stage10_tree_candidate_for_biome(
						world_x, world_z, surface, biome, transition, terrain_modifier, slope
					)
					var new_tree: bool = data.stage11_tree_candidate_for_biome(
						world_x,
						world_z,
						surface,
						biome,
						transition,
						terrain_modifier,
						slope,
						hydro
					)
					if old_tree != new_tree:
						tree_changes[hydro] += 1

	if adjacency_failures != 0:
		_fail("Stage 11 world audit found %d invalid hydrology/physical-water relationships" % adjacency_failures)
	if hydrology_counts[DATA.HYDROLOGY_MODIFIER_COAST] == 0:
		_fail("Stage 11 audit found no coastal expression margin")
	if hydrology_counts[DATA.HYDROLOGY_MODIFIER_RIVERBANK] == 0:
		_fail("Stage 11 audit found no riverbank expression margin")
	if surface_changes[DATA.HYDROLOGY_MODIFIER_COAST] == 0:
		_fail("Stage 11 coast modifier never changed visible surface expression")
	var wet_surface_changes: int = (
		surface_changes[DATA.HYDROLOGY_MODIFIER_RIVERBANK]
		+ surface_changes[DATA.HYDROLOGY_MODIFIER_LAKESIDE]
		+ surface_changes[DATA.HYDROLOGY_MODIFIER_PONDSIDE]
	)
	if wet_surface_changes == 0:
		_fail("Stage 11 wet margins never changed visible surface expression")
	var wet_tree_changes: int = (
		tree_changes[DATA.HYDROLOGY_MODIFIER_RIVERBANK]
		+ tree_changes[DATA.HYDROLOGY_MODIFIER_LAKESIDE]
		+ tree_changes[DATA.HYDROLOGY_MODIFIER_PONDSIDE]
	)
	if wet_tree_changes == 0:
		_fail("Stage 11 wet margins never changed vegetation eligibility")

	return {
		"land_columns": land_columns,
		"water_columns": water_columns,
		"hydrology_counts": hydrology_counts,
		"surface_changes": surface_changes,
		"tree_changes": tree_changes,
		"wet_surface_changes": wet_surface_changes,
		"wet_tree_changes": wet_tree_changes,
		"adjacency_failures": adjacency_failures,
	}


func _cache_index(world_x: int, world_z: int, coord: Vector2i) -> int:
	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING
	return (world_z - min_z) * WIDTH + (world_x - min_x)


func _validate_seams(runtime, data) -> Dictionary:
	var horizontal_a := Vector2i(0, 0)
	var horizontal_b := Vector2i(1, 0)
	var vertical_a := Vector2i(0, 0)
	var vertical_b := Vector2i(0, 1)
	var cache_ha: Dictionary = runtime._build_column_caches(horizontal_a)
	var cache_hb: Dictionary = runtime._build_column_caches(horizontal_b)
	var cache_va: Dictionary = runtime._build_column_caches(vertical_a)
	var cache_vb: Dictionary = runtime._build_column_caches(vertical_b)
	var h_a: PackedByteArray = STAGE11_CACHE.build_hydrology_codes(cache_ha, data)
	var h_b: PackedByteArray = STAGE11_CACHE.build_hydrology_codes(cache_hb, data)
	var v_a: PackedByteArray = STAGE11_CACHE.build_hydrology_codes(cache_va, data)
	var v_b: PackedByteArray = STAGE11_CACHE.build_hydrology_codes(cache_vb, data)
	var comparisons: int = 0
	for world_z in range(-1, 13):
		for world_x in range(11, 13):
			comparisons += 1
			if int(h_a[_cache_index(world_x, world_z, horizontal_a)]) != int(h_b[_cache_index(world_x, world_z, horizontal_b)]):
				_fail("Stage 11 horizontal hydrology-expression seam mismatch")
	for world_z in range(11, 13):
		for world_x in range(-1, 13):
			comparisons += 1
			if int(v_a[_cache_index(world_x, world_z, vertical_a)]) != int(v_b[_cache_index(world_x, world_z, vertical_b)]):
				_fail("Stage 11 vertical hydrology-expression seam mismatch")
	return {"hydrology_overlap_comparisons": comparisons}


func _validate_determinism(runtime, data) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(8, -5), Vector2i(-12, 9)]
	for coord: Vector2i in coords:
		var first: Dictionary = runtime._build_column_caches(coord)
		var second: Dictionary = runtime._build_column_caches(coord)
		if first.get("heights") != second.get("heights"):
			_fail("Stage 11 generation height cache is nondeterministic in %s" % coord)
		if STAGE11_CACHE.build_transition_codes(first, data) != STAGE11_CACHE.build_transition_codes(second, data):
			_fail("Stage 11 climate transition preparation is nondeterministic in %s" % coord)
		if STAGE11_CACHE.build_hydrology_codes(first, data) != STAGE11_CACHE.build_hydrology_codes(second, data):
			_fail("Stage 11 hydrology preparation is nondeterministic in %s" % coord)
	return {"chunks": coords.size()}


func _representative_caches(runtime) -> Array[Dictionary]:
	var caches: Array[Dictionary] = []
	for z in range(-2, 2):
		for x in range(-2, 2):
			caches.append(runtime._build_column_caches(Vector2i(x, z)))
	return caches


func _benchmark_generation(runtime) -> Dictionary:
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
				_fail("Impossible Stage 11 generation benchmark checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	return _benchmark_report(
		values,
		"16 padded chunks, 4 warmups, 20 repeats; unchanged 320-sample hard generation gate"
	)


func _benchmark_transition_preparation(runtime, data) -> Dictionary:
	var caches: Array[Dictionary] = _representative_caches(runtime)
	for _warmup in range(WARMUPS):
		for cache: Dictionary in caches:
			STAGE11_CACHE.build_transition_codes(cache, data)
	var values: Array[int] = []
	for _repeat in range(REPEATS):
		for cache: Dictionary in caches:
			var started: int = Time.get_ticks_usec()
			var codes: PackedByteArray = STAGE11_CACHE.build_transition_codes(cache, data)
			var checksum: int = int(codes[0]) + int(codes[codes.size() - 1]) if not codes.is_empty() else 0
			if checksum == -2147483648:
				_fail("Impossible Stage 11 transition benchmark checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	return _benchmark_report(values, "Stage 10 climate-transition preparation on 16 prepared caches")


func _benchmark_hydrology_preparation(runtime, data) -> Dictionary:
	var caches: Array[Dictionary] = _representative_caches(runtime)
	for _warmup in range(WARMUPS):
		for cache: Dictionary in caches:
			STAGE11_CACHE.build_hydrology_codes(cache, data)
	var values: Array[int] = []
	for _repeat in range(REPEATS):
		for cache: Dictionary in caches:
			var started: int = Time.get_ticks_usec()
			var codes: PackedByteArray = STAGE11_CACHE.build_hydrology_codes(cache, data)
			var checksum: int = int(codes[0]) + int(codes[codes.size() - 1]) if not codes.is_empty() else 0
			if checksum == -2147483648:
				_fail("Impossible Stage 11 hydrology benchmark checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	return _benchmark_report(values, "Stage 11 one-cell water-margin preparation on 16 prepared caches")


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
