extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage11_water_biome_data.gd")
const STAGE11_RUNTIME := preload("res://scripts/world/playable_world_stage11_generation_runtime.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const STAGE11_CACHE := preload("res://scripts/world/playable_world_stage11_cache_fast.gd")
const STAGE12_CACHE := preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const STAGE11_MESHER := preload("res://scripts/world/playable_world_stage11_mesher.gd")
const STAGE12_MESHER := preload("res://scripts/world/playable_world_stage12_mesher.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := 16
const P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20
const MESH_WARMUPS := 1
const MESH_REPEATS := 3
const MESH_REGRESSION_LIMIT := 1.10

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var runtime = RUNTIME.new()
	var stage11_runtime = STAGE11_RUNTIME.new()

	var contract := _validate_contract()
	var generation_equivalence := _validate_generation_equivalence(runtime, stage11_runtime)
	var expression_equivalence := _validate_expression_equivalence(runtime, data)
	var mesh_equivalence := _validate_mesh_equivalence(runtime, data)
	var generation_benchmark := _benchmark_generation(runtime)
	var old_hydrology_benchmark := _benchmark_hydrology(runtime, data, false)
	var new_hydrology_benchmark := _benchmark_hydrology(runtime, data, true)
	var old_expression_benchmark := _benchmark_expression_preparation(runtime, data, false)
	var new_expression_benchmark := _benchmark_expression_preparation(runtime, data, true)
	var mesh_benchmarks := _benchmark_meshers(runtime, data)

	if int(generation_benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail(
			"Stage 12 generation exceeded the unchanged 1.0 ms p95 gate: %d usec"
			% int(generation_benchmark["p95_usec"])
		)
	if int(new_hydrology_benchmark["p95_usec"]) >= int(old_hydrology_benchmark["p95_usec"]):
		_fail(
			"Stage 12 hydrology preparation did not improve p95: old=%d new=%d usec"
			% [
				int(old_hydrology_benchmark["p95_usec"]),
				int(new_hydrology_benchmark["p95_usec"]),
			]
		)
	if int(new_expression_benchmark["p95_usec"]) >= int(old_expression_benchmark["p95_usec"]):
		_fail(
			"Stage 12 combined expression preparation did not improve p95: old=%d new=%d usec"
			% [
				int(old_expression_benchmark["p95_usec"]),
				int(new_expression_benchmark["p95_usec"]),
			]
		)
	var old_mesh_mean: float = float(mesh_benchmarks["stage11"]["mean_usec"])
	var new_mesh_mean: float = float(mesh_benchmarks["stage12"]["mean_usec"])
	if new_mesh_mean > old_mesh_mean * MESH_REGRESSION_LIMIT:
		_fail(
			"Stage 12 equivalent mesher regressed mean time by more than 10%%: old=%.1f new=%.1f usec"
			% [old_mesh_mean, new_mesh_mean]
		)

	var report := {
		"contract": contract,
		"generation_equivalence": generation_equivalence,
		"expression_equivalence": expression_equivalence,
		"mesh_equivalence": mesh_equivalence,
		"generation_benchmark": generation_benchmark,
		"stage11_hydrology_benchmark": old_hydrology_benchmark,
		"stage12_hydrology_benchmark": new_hydrology_benchmark,
		"stage11_expression_benchmark": old_expression_benchmark,
		"stage12_expression_benchmark": new_expression_benchmark,
		"mesh_benchmarks": mesh_benchmarks,
		"generation_p95_limit_usec": P95_LIMIT_USEC,
		"mesh_mean_regression_limit": MESH_REGRESSION_LIMIT,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE12_JSON=%s" % JSON.stringify(report))
	runtime.free()
	stage11_runtime.free()
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE12_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _validate_contract() -> Dictionary:
	var runtime_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_generation_runtime.gd"
	)
	var stage11_runtime_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage11_generation_runtime.gd"
	)
	var stage12_cache_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage12_cache_fast.gd"
	)
	var stage12_mesher_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage12_mesher.gd"
	)
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 12 lost the 150-block legal world height")
	if stage12_cache_source.contains("get_noise_2d") or stage12_cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 12 expression cache added procedural noise sampling")
	if stage12_mesher_source.contains("get_noise_2d") or stage12_mesher_source.contains("FastNoiseLite.new"):
		_fail("Stage 12 mesher added procedural noise sampling")
	if not stage11_runtime_source.contains("SHIPPING_STAGE11_CACHE.build_hydrology_codes"):
		_fail("Frozen Stage 11 runtime no longer preserves the accepted Stage 11 path")
	if not runtime_source.contains("SHIPPING_STAGE10_GENERATION_CACHE.build"):
		_fail("Stage 12 changed the accepted Stage 10 generation cache")
	if not runtime_source.contains("SHIPPING_STAGE12_CACHE.build_expression_codes"):
		_fail("Shipping runtime is not using Stage 12 expression preparation")
	if not runtime_source.contains("SHIPPING_STAGE12_MESHER.build"):
		_fail("Shipping runtime is not using the Stage 12 equivalent mesher")
	return {
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"generation_base": "exact Stage 10 generation cache",
		"stage11_oracle": "frozen runtime + cache + mesher",
		"optimization_scope": "post-generation expression preparation and mesher bookkeeping",
		"new_noise_calls": 0,
	}


func _representative_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for z in range(-2, 2):
		for x in range(-2, 2):
			coords.append(Vector2i(x, z))
	return coords


func _representative_caches(runtime) -> Array[Dictionary]:
	var caches: Array[Dictionary] = []
	for coord in _representative_coords():
		caches.append(runtime._build_column_caches(coord))
	return caches


func _validate_generation_equivalence(runtime, stage11_runtime) -> Dictionary:
	var coords: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(4, -3),
		Vector2i(-7, 8),
		Vector2i(13, -11),
	]
	var array_contracts: int = 0
	for coord in coords:
		var current: Dictionary = runtime._build_column_caches(coord)
		var frozen: Dictionary = stage11_runtime._build_column_caches(coord)
		for key in [
			"world_fields",
			"heights",
			"biomes",
			"stage7_water_types",
			"stage9_terrain_modifiers",
		]:
			if current.get(key) != frozen.get(key):
				_fail("Stage 12 changed frozen Stage 11 generation array '%s' in %s" % [key, coord])
			else:
				array_contracts += 1
	return {"chunks": coords.size(), "array_contracts": array_contracts}


func _validate_expression_equivalence(runtime, data) -> Dictionary:
	var transition_arrays: int = 0
	var hydrology_arrays: int = 0
	var hydrology_columns: int = 0
	for coord in _representative_coords():
		var cache: Dictionary = runtime._build_column_caches(coord)
		var old_transition: PackedByteArray = STAGE11_CACHE.build_transition_codes(cache, data)
		var new_transition: PackedByteArray = STAGE12_CACHE.build_transition_codes(cache, data)
		if old_transition != new_transition:
			_fail("Stage 12 changed Stage 11 transition codes in %s" % coord)
		else:
			transition_arrays += 1
		var old_hydrology: PackedByteArray = STAGE11_CACHE.build_hydrology_codes(cache, data)
		var new_hydrology: PackedByteArray = STAGE12_CACHE.build_hydrology_codes(cache, data)
		if old_hydrology != new_hydrology:
			_fail("Stage 12 changed Stage 11 hydrology codes in %s" % coord)
		else:
			hydrology_arrays += 1
			hydrology_columns += new_hydrology.size()
	return {
		"chunks": _representative_coords().size(),
		"transition_arrays": transition_arrays,
		"hydrology_arrays": hydrology_arrays,
		"hydrology_columns": hydrology_columns,
	}


func _mesh_height(heights: PackedInt32Array) -> int:
	var highest: int = 1
	for value in heights:
		highest = maxi(highest, int(value) + 8)
	return mini(DATA.OVERHAUL_WORLD_HEIGHT, highest)


func _mesh_data_equal(a: Dictionary, b: Dictionary) -> bool:
	return (
		a.get("face_count", -1) == b.get("face_count", -2)
		and a.get("vertices", PackedVector3Array()) == b.get("vertices", PackedVector3Array())
		and a.get("normals", PackedVector3Array()) == b.get("normals", PackedVector3Array())
		and a.get("colors", PackedColorArray()) == b.get("colors", PackedColorArray())
		and a.get("indices", PackedInt32Array()) == b.get("indices", PackedInt32Array())
	)


func _build_mesher_inputs(runtime, data, coord: Vector2i) -> Dictionary:
	var cache: Dictionary = runtime._build_column_caches(coord)
	var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
	var old_transition: PackedByteArray = STAGE11_CACHE.build_transition_codes(cache, data)
	var new_transition: PackedByteArray = STAGE12_CACHE.build_transition_codes(cache, data)
	var old_hydrology: PackedByteArray = STAGE11_CACHE.build_hydrology_codes(cache, data)
	var new_hydrology: PackedByteArray = STAGE12_CACHE.build_hydrology_codes(cache, data)
	var blocked: PackedInt32Array = STAGE11_RUNTIME._stage6_blocked_tree_columns(coord, cache, data)
	return {
		"cache": cache,
		"heights": heights,
		"biomes": cache.get("biomes", PackedByteArray()),
		"water_types": cache.get("stage7_water_types", PackedByteArray()),
		"terrain_modifiers": cache.get("stage9_terrain_modifiers", PackedByteArray()),
		"old_transition": old_transition,
		"new_transition": new_transition,
		"old_hydrology": old_hydrology,
		"new_hydrology": new_hydrology,
		"blocked": blocked,
		"mesh_height": _mesh_height(heights),
	}


func _build_stage11_mesh(coord: Vector2i, inputs: Dictionary, data) -> Dictionary:
	return STAGE11_MESHER.build(
		coord,
		inputs["heights"],
		{},
		CHUNK_SIZE,
		int(inputs["mesh_height"]),
		DATA.SEA_LEVEL,
		inputs["biomes"],
		inputs["water_types"],
		inputs["terrain_modifiers"],
		inputs["old_transition"],
		inputs["old_hydrology"],
		data,
		inputs["blocked"]
	)


func _build_stage12_mesh(coord: Vector2i, inputs: Dictionary, data) -> Dictionary:
	return STAGE12_MESHER.build(
		coord,
		inputs["heights"],
		{},
		CHUNK_SIZE,
		int(inputs["mesh_height"]),
		DATA.SEA_LEVEL,
		inputs["biomes"],
		inputs["water_types"],
		inputs["terrain_modifiers"],
		inputs["new_transition"],
		inputs["new_hydrology"],
		data,
		inputs["blocked"]
	)


func _validate_mesh_equivalence(runtime, data) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, -1), Vector2i(-2, 1), Vector2i(2, -2)]
	var exact_chunks: int = 0
	var total_faces: int = 0
	for coord in coords:
		var inputs := _build_mesher_inputs(runtime, data, coord)
		var old_mesh := _build_stage11_mesh(coord, inputs, data)
		var new_mesh := _build_stage12_mesh(coord, inputs, data)
		if not _mesh_data_equal(old_mesh, new_mesh):
			_fail("Stage 12 mesher changed exact Stage 11 mesh output in %s" % coord)
		else:
			exact_chunks += 1
			total_faces += int(new_mesh.get("face_count", 0))
	return {"chunks": coords.size(), "exact_chunks": exact_chunks, "total_faces": total_faces}


func _benchmark_generation(runtime) -> Dictionary:
	var coords := _representative_coords()
	for _warmup in range(WARMUPS):
		for coord in coords:
			runtime._build_column_caches(coord)
	var values: Array[int] = []
	for _repeat in range(REPEATS):
		for coord in coords:
			var started := Time.get_ticks_usec()
			var cache: Dictionary = runtime._build_column_caches(coord)
			var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
			var checksum: int = int(heights[0]) + int(heights[heights.size() - 1]) if not heights.is_empty() else 0
			if checksum == -2147483648:
				_fail("Impossible Stage 12 generation checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	return _benchmark_report(values, "16 padded chunks, 4 warmups, 20 repeats; unchanged 320-sample hard gate")


func _benchmark_hydrology(runtime, data, optimized: bool) -> Dictionary:
	var caches := _representative_caches(runtime)
	for _warmup in range(WARMUPS):
		for cache in caches:
			if optimized:
				STAGE12_CACHE.build_hydrology_codes(cache, data)
			else:
				STAGE11_CACHE.build_hydrology_codes(cache, data)
	var values: Array[int] = []
	for _repeat in range(REPEATS):
		for cache in caches:
			var started := Time.get_ticks_usec()
			var codes: PackedByteArray = (
				STAGE12_CACHE.build_hydrology_codes(cache, data)
				if optimized
				else STAGE11_CACHE.build_hydrology_codes(cache, data)
			)
			var checksum: int = int(codes[0]) + int(codes[codes.size() - 1]) if not codes.is_empty() else 0
			if checksum == -2147483648:
				_fail("Impossible Stage 12 hydrology checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	return _benchmark_report(values, "optimized Stage 12 hydrology" if optimized else "frozen Stage 11 hydrology")


func _benchmark_expression_preparation(runtime, data, optimized: bool) -> Dictionary:
	var caches := _representative_caches(runtime)
	for _warmup in range(WARMUPS):
		for cache in caches:
			if optimized:
				STAGE12_CACHE.build_expression_codes(cache, data)
			else:
				STAGE11_CACHE.build_transition_codes(cache, data)
				STAGE11_CACHE.build_hydrology_codes(cache, data)
	var values: Array[int] = []
	for _repeat in range(REPEATS):
		for cache in caches:
			var started := Time.get_ticks_usec()
			var checksum: int = 0
			if optimized:
				var result: Dictionary = STAGE12_CACHE.build_expression_codes(cache, data)
				var transition: PackedByteArray = result["transition_codes"]
				var hydrology: PackedByteArray = result["hydrology_codes"]
				checksum = int(transition[0]) + int(hydrology[hydrology.size() - 1])
			else:
				var transition := STAGE11_CACHE.build_transition_codes(cache, data)
				var hydrology := STAGE11_CACHE.build_hydrology_codes(cache, data)
				checksum = int(transition[0]) + int(hydrology[hydrology.size() - 1])
			if checksum == -2147483648:
				_fail("Impossible Stage 12 expression checksum")
			values.append(maxi(1, Time.get_ticks_usec() - started))
	return _benchmark_report(values, "optimized Stage 12 combined expression preparation" if optimized else "frozen Stage 11 transition + hydrology preparation")


func _benchmark_meshers(runtime, data) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, -1), Vector2i(-2, 1), Vector2i(2, -2)]
	var prepared: Array[Dictionary] = []
	for coord in coords:
		prepared.append(_build_mesher_inputs(runtime, data, coord))
	for _warmup in range(MESH_WARMUPS):
		for index in range(coords.size()):
			_build_stage11_mesh(coords[index], prepared[index], data)
			_build_stage12_mesh(coords[index], prepared[index], data)
	var old_values: Array[int] = []
	var new_values: Array[int] = []
	for _repeat in range(MESH_REPEATS):
		for index in range(coords.size()):
			var started := Time.get_ticks_usec()
			var old_mesh := _build_stage11_mesh(coords[index], prepared[index], data)
			old_values.append(maxi(1, Time.get_ticks_usec() - started))
			started = Time.get_ticks_usec()
			var new_mesh := _build_stage12_mesh(coords[index], prepared[index], data)
			new_values.append(maxi(1, Time.get_ticks_usec() - started))
			if int(old_mesh.get("face_count", -1)) != int(new_mesh.get("face_count", -2)):
				_fail("Stage 12 benchmark observed a mesh face-count mismatch")
	return {
		"stage11": _benchmark_report(old_values, "4 prepared chunks, 1 warmup, 3 repeats; frozen Stage 11 mesher"),
		"stage12": _benchmark_report(new_values, "4 prepared chunks, 1 warmup, 3 repeats; equivalent Stage 12 mesher"),
	}


func _benchmark_report(values: Array[int], methodology: String) -> Dictionary:
	values.sort()
	var total: int = 0
	for value in values:
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
