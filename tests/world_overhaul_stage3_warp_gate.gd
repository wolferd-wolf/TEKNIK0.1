extends SceneTree

const DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")

const CHUNK_SIZE := 12
const CACHE_PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + CACHE_PADDING * 2
const FIELD_STRIDE := 6
const FIELD_TERRAIN_STRUCTURE := 1
const GENERATION_P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var runtime = RUNTIME.new()
	var contract := _validate_contract(data)
	var warp := _validate_warp_field(data)
	var lattice := _validate_runtime_lattice(runtime, data)
	var terrain := _validate_terrain_effect(data)
	var halo := _validate_halo(runtime)
	var deterministic := _validate_determinism(runtime)
	var benchmark := _benchmark(runtime)
	if int(benchmark["p95_usec"]) >= GENERATION_P95_LIMIT_USEC:
		_fail(
			"Stage 3 generation exceeded the 1.0 ms p95 threshold: %d usec"
			% int(benchmark["p95_usec"])
		)
	runtime.free()

	var report := {
		"world_height_limit": DATA.OVERHAUL_WORLD_HEIGHT,
		"safe_terrain_top": DATA.STAGE2_SAFE_TERRAIN_TOP,
		"contract": contract,
		"warp": warp,
		"lattice": lattice,
		"terrain_effect": terrain,
		"halo": halo,
		"determinism": deterministic,
		"benchmark": benchmark,
		"generation_p95_limit_usec": GENERATION_P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE3_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE3_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_contract(data) -> Dictionary:
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 3 lost the 150-block world-height contract")
	if DATA.STAGE3_FIELD_LATTICE_SPACING != 4:
		_fail("Stage 3 terrain structure is not using the planned 4-block lattice")
	if DATA.STAGE3_WARP_LATTICE_SPACING < 32:
		_fail("Stage 3 macro warp lattice is too fine to remain a macro feature")
	if DATA.STAGE3_WARP_AMPLITUDE <= 0.0:
		_fail("Stage 3 macro warp amplitude is disabled")

	var source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_generation_data.gd"
	)
	if source.contains("FastNoiseLite.new"):
		_fail("Stage 3 added a new FastNoiseLite stack instead of reusing existing fields")
	for required in [
		"stage3_macro_warp_offset",
		"stage3_sample_structure_node",
		"stage3_terrain_structure",
	]:
		if not source.contains(required):
			_fail("Stage 3 data source is missing %s" % required)

	var runtime_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage3_generation_runtime.gd"
	)
	for required in [
		"_stage3_build_column_caches_for_sampler",
		"structure_nodes",
		"STAGE3_FIELD_LATTICE_SPACING",
	]:
		if not runtime_source.contains(required):
			_fail("Stage 3 runtime source is missing %s" % required)

	var unchanged_field_checks := 0
	for point in [
		Vector2i.ZERO,
		Vector2i(31, -47),
		Vector2i(-96, 73),
		Vector2i(257, -199),
	]:
		var fields: Vector4 = data.sample_world_fields(point.x, point.y)
		var world_x := float(point.x)
		var world_z := float(point.y)
		if not is_equal_approx(
			fields.x,
			data.continentalness_noise.get_noise_2d(world_x, world_z)
		):
			_fail("Stage 3 warped continentalness at %s" % point)
		if not is_equal_approx(
			fields.z,
			data.temperature_noise.get_noise_2d(world_x, world_z)
		):
			_fail("Stage 3 warped terrain temperature at %s" % point)
		if not is_equal_approx(
			fields.w,
			data.moisture_noise.get_noise_2d(world_x, world_z)
		):
			_fail("Stage 3 warped terrain moisture at %s" % point)
		unchanged_field_checks += 3
	return {"unchanged_non_structure_field_checks": unchanged_field_checks}


func _validate_warp_field(data) -> Dictionary:
	var sample_count := 0
	var total_magnitude := 0.0
	var maximum_magnitude := 0.0
	var maximum_neighbor_delta := 0.0
	var long_range_changes := 0
	for z in range(-256, 257, 16):
		for x in range(-256, 257, 16):
			var offset: Vector2 = data.stage3_macro_warp_offset(x, z)
			var magnitude := offset.length()
			total_magnitude += magnitude
			maximum_magnitude = maxf(maximum_magnitude, magnitude)
			maximum_neighbor_delta = maxf(
				maximum_neighbor_delta,
				maxf(
					offset.distance_to(data.stage3_macro_warp_offset(x + 1, z)),
					offset.distance_to(data.stage3_macro_warp_offset(x, z + 1))
				)
			)
			if offset.distance_to(data.stage3_macro_warp_offset(x + 128, z)) > 6.0:
				long_range_changes += 1
			sample_count += 1
	var mean_magnitude := total_magnitude / float(sample_count)
	if mean_magnitude < 4.0:
		_fail("Stage 3 warp is too weak to materially deform macro terrain")
	if maximum_magnitude < 10.0:
		_fail("Stage 3 warp never reaches a useful macro displacement")
	if maximum_neighbor_delta > 3.0:
		_fail(
			"Stage 3 warp changes too abruptly between adjacent columns: %.3f"
			% maximum_neighbor_delta
		)
	if long_range_changes < int(sample_count * 0.35):
		_fail("Stage 3 warp lacks enough long-range variation")
	return {
		"sample_count": sample_count,
		"mean_magnitude": mean_magnitude,
		"maximum_magnitude": maximum_magnitude,
		"maximum_neighbor_delta": maximum_neighbor_delta,
		"long_range_changes": long_range_changes,
	}


func _validate_runtime_lattice(runtime, data) -> Dictionary:
	var compared_columns := 0
	var compared_heights := 0
	var maximum_structure_error := 0.0
	for coord in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-7, 5), Vector2i(11, 9)]:
		var cache: Dictionary = runtime._build_column_caches(coord)
		var fields: PackedFloat32Array = cache["world_fields"]
		var heights: PackedInt32Array = cache["heights"]
		var origin_x := coord.x * CHUNK_SIZE
		var origin_z := coord.y * CHUNK_SIZE
		for local_z in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
			for local_x in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
				var column_index := (
					(local_z + CACHE_PADDING) * CACHE_WIDTH
					+ local_x
					+ CACHE_PADDING
				)
				var field_index := column_index * FIELD_STRIDE
				var world_x := origin_x + local_x
				var world_z := origin_z + local_z
				var expected_structure: float = data.stage3_terrain_structure(world_x, world_z)
				var error := absf(fields[field_index + FIELD_TERRAIN_STRUCTURE] - expected_structure)
				maximum_structure_error = maxf(maximum_structure_error, error)
				if error > 0.00002:
					_fail(
						"Stage 3 runtime lattice differs from public structure at (%d,%d): %.8f"
						% [world_x, world_z, error]
					)
				if heights[column_index] != data.terrain_height(world_x, world_z):
					_fail("Stage 3 runtime/public height mismatch at (%d,%d)" % [world_x, world_z])
				compared_columns += 1
				compared_heights += 1
	return {
		"compared_structure_columns": compared_columns,
		"compared_heights": compared_heights,
		"maximum_structure_error": maximum_structure_error,
	}


func _validate_terrain_effect(data) -> Dictionary:
	var structure_changes := 0
	var height_changes := 0
	var mountain_height_changes := 0
	var minimum_height := 999999
	var maximum_height := -999999
	var sample_count := 0
	for z in range(-384, 385, 8):
		for x in range(-384, 385, 8):
			var fields: Vector4 = data.sample_world_fields(x, z)
			var unwarped_structure: float = data.stage3_unwarped_structure(x, z)
			var stage3_height: int = data.build_provisional_terrain(fields)
			var stage2_height: int = data.build_provisional_terrain(
				Vector4(fields.x, unwarped_structure, fields.z, fields.w)
			)
			minimum_height = mini(minimum_height, stage3_height)
			maximum_height = maxi(maximum_height, stage3_height)
			if absf(fields.y - unwarped_structure) > 0.01:
				structure_changes += 1
			if stage3_height != stage2_height:
				height_changes += 1
			if (
				stage3_height != stage2_height
				and maxf(fields.y, unwarped_structure) >= DATA.STAGE2_MOUNTAIN_START
			):
				mountain_height_changes += 1
			sample_count += 1
	var height_range := maximum_height - minimum_height
	if structure_changes < int(sample_count * 0.25):
		_fail("Stage 3 warp does not materially change the terrain-structure field")
	if height_changes < int(sample_count * 0.05):
		_fail("Stage 3 warp does not materially deform final terrain height")
	if mountain_height_changes < 25:
		_fail("Stage 3 warp does not materially reshape mountain-capable terrain")
	if maximum_height < 55 or height_range < 35:
		_fail("Stage 3 lost the accepted Stage 2 terrain scale")
	if maximum_height > DATA.STAGE2_SAFE_TERRAIN_TOP:
		_fail("Stage 3 terrain exceeded the safe terrain top")
	return {
		"sample_count": sample_count,
		"structure_changes": structure_changes,
		"height_changes": height_changes,
		"mountain_height_changes": mountain_height_changes,
		"minimum_height": minimum_height,
		"maximum_height": maximum_height,
		"height_range": height_range,
	}


func _validate_halo(runtime) -> Dictionary:
	var compared_columns := 0
	for pair in [
		[Vector2i.ZERO, Vector2i(1, 0)],
		[Vector2i.ZERO, Vector2i(0, 1)],
		[Vector2i(-4, 3), Vector2i(-3, 3)],
	]:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var cache_a: Dictionary = runtime._build_column_caches(a)
		var cache_b: Dictionary = runtime._build_column_caches(b)
		var heights_a: PackedInt32Array = cache_a["heights"]
		var heights_b: PackedInt32Array = cache_b["heights"]
		var fields_a: PackedFloat32Array = cache_a["world_fields"]
		var fields_b: PackedFloat32Array = cache_b["world_fields"]
		var min_x := maxi(a.x * CHUNK_SIZE - CACHE_PADDING, b.x * CHUNK_SIZE - CACHE_PADDING)
		var max_x := mini(
			a.x * CHUNK_SIZE + CHUNK_SIZE + CACHE_PADDING - 1,
			b.x * CHUNK_SIZE + CHUNK_SIZE + CACHE_PADDING - 1
		)
		var min_z := maxi(a.y * CHUNK_SIZE - CACHE_PADDING, b.y * CHUNK_SIZE - CACHE_PADDING)
		var max_z := mini(
			a.y * CHUNK_SIZE + CHUNK_SIZE + CACHE_PADDING - 1,
			b.y * CHUNK_SIZE + CHUNK_SIZE + CACHE_PADDING - 1
		)
		for world_z in range(min_z, max_z + 1):
			for world_x in range(min_x, max_x + 1):
				var index_a := _cache_index(a, world_x, world_z)
				var index_b := _cache_index(b, world_x, world_z)
				if heights_a[index_a] != heights_b[index_b]:
					_fail("Stage 3 height halo seam at (%d,%d)" % [world_x, world_z])
				var structure_a := fields_a[index_a * FIELD_STRIDE + FIELD_TERRAIN_STRUCTURE]
				var structure_b := fields_b[index_b * FIELD_STRIDE + FIELD_TERRAIN_STRUCTURE]
				if not is_equal_approx(structure_a, structure_b):
					_fail("Stage 3 structure halo seam at (%d,%d)" % [world_x, world_z])
				compared_columns += 1
	return {"compared_overlap_columns": compared_columns}


func _cache_index(coord: Vector2i, world_x: int, world_z: int) -> int:
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	var cache_x := world_x - origin_x + CACHE_PADDING
	var cache_z := world_z - origin_z + CACHE_PADDING
	return cache_z * CACHE_WIDTH + cache_x


func _validate_determinism(runtime) -> Dictionary:
	var compared_chunks := 0
	for coord in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-7, 5), Vector2i(11, 9)]:
		var first: Dictionary = runtime._build_column_caches(coord)
		var second: Dictionary = runtime._build_column_caches(coord)
		if first["world_fields"] != second["world_fields"]:
			_fail("Stage 3 field generation is nondeterministic at %s" % coord)
		if first["heights"] != second["heights"]:
			_fail("Stage 3 height generation is nondeterministic at %s" % coord)
		if first["biomes"] != second["biomes"]:
			_fail("Stage 3 biome cache became nondeterministic at %s" % coord)
		compared_chunks += 1
	return {"compared_chunks": compared_chunks}


func _benchmark(runtime) -> Dictionary:
	var coords: Array[Vector2i] = [
		Vector2i(-4, -2), Vector2i(-2, 1), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(2, -1), Vector2i(4, 2), Vector2i(8, -4), Vector2i(11, -3),
		Vector2i(12, -2), Vector2i(13, -2), Vector2i(14, -1), Vector2i(15, 0),
		Vector2i(16, 1), Vector2i(18, -4), Vector2i(20, 2), Vector2i(-8, 5),
	]
	for _warmup in range(WARMUPS):
		for coord in coords:
			runtime._build_column_caches(coord)

	var times: Array[int] = []
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			var started := Time.get_ticks_usec()
			runtime._build_column_caches(coord)
			times.append(maxi(1, Time.get_ticks_usec() - started))

	times.sort()
	var total := 0
	for value in times:
		total += value
	var p95_index := clampi(ceili(float(times.size()) * 0.95) - 1, 0, times.size() - 1)
	return {
		"sample_count": times.size(),
		"minimum_usec": times[0],
		"maximum_usec": times[times.size() - 1],
		"mean_usec": float(total) / float(times.size()),
		"p95_usec": times[p95_index],
		"p95_ms": float(times[p95_index]) / 1000.0,
		"methodology": "same 16 representative padded chunks, 4 warmups, 20 repeats; generation/cache only",
	}


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
