extends SceneTree

const LEGACY_DATA := preload("res://scripts/world/playable_world_data.gd")
const LEGACY_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")
const PIPELINE_DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const PIPELINE_RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

const CHUNK_SIZE := 12
const CACHE_PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + CACHE_PADDING * 2
const FIELD_STRIDE := 6
const WARMUPS := 4
const REPEATS := 20
const GENERATION_P95_LIMIT_USEC := 1000

var failures: Array[String] = []


func _init() -> void:
	var legacy_data = LEGACY_DATA.new()
	var pipeline_data = PIPELINE_DATA.new()
	var legacy_runtime = LEGACY_RUNTIME.new()
	var pipeline_runtime = PIPELINE_RUNTIME.new()

	_validate_source_contract()
	_validate_height_limit(pipeline_data, pipeline_runtime)
	var equivalence := _validate_equivalence(
		legacy_data,
		pipeline_data,
		pipeline_runtime
	)
	var halo := _validate_halo_continuity(pipeline_runtime)
	var mesh_equivalence := _validate_mesh_equivalence(
		legacy_data,
		pipeline_runtime
	)
	var benchmark := _benchmark_generation(legacy_runtime, pipeline_runtime)

	legacy_runtime.free()
	pipeline_runtime.free()

	var pipeline_p95 := int(benchmark["pipeline"]["p95_usec"])
	if pipeline_p95 >= GENERATION_P95_LIMIT_USEC:
		_fail(
			"Stage 1 generation exceeded the existing 1.0 ms p95 threshold: %d usec"
			% pipeline_p95
		)

	var report := {
		"world_height_limit": PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT,
		"cache_padding": CACHE_PADDING,
		"cache_width": CACHE_WIDTH,
		"field_stride": FIELD_STRIDE,
		"equivalence": equivalence,
		"halo": halo,
		"mesh_equivalence": mesh_equivalence,
		"benchmark": benchmark,
		"generation_p95_limit_usec": GENERATION_P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE1_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE1_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_source_contract() -> void:
	var data_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_generation_data.gd"
	)
	for required in [
		"func sample_world_fields",
		"func build_provisional_terrain",
		"func apply_water_topology",
		"func finalize_height",
		"func classify_biome",
		"func decorate_surface",
		"OVERHAUL_WORLD_HEIGHT := 150",
	]:
		if not data_source.contains(required):
			_fail("Stage 1 generation-data pipeline is missing %s" % required)

	var runtime_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_generation_runtime.gd"
	)
	for required in [
		"_sample_world_fields",
		"_build_provisional_terrain",
		"_apply_water_topology",
		"_finalize_height",
		"_classify_biomes",
		"_decorate_surface",
		"_effective_mesh_height",
		"FIELD_STRIDE := 6",
	]:
		if not runtime_source.contains(required):
			_fail("Stage 1 generation runtime is missing %s" % required)


func _validate_height_limit(pipeline_data, pipeline_runtime) -> void:
	if PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail(
			"Overhaul world-height limit must be 150, got %d"
			% PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT
		)

	var high_cell := Vector3i(0, PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT - 1, 0)
	if pipeline_data.get_block(high_cell) != PIPELINE_DATA.BLOCK_AIR:
		_fail("Fresh generated world unexpectedly occupies the top legal block")
	if not pipeline_data.set_block(high_cell, PIPELINE_DATA.BLOCK_STONE):
		_fail("Stage 1 rejected a legal placement at y=149")
	if pipeline_data.get_block(high_cell) != PIPELINE_DATA.BLOCK_STONE:
		_fail("Stage 1 did not preserve a legal placement at y=149")
	if pipeline_data.set_block(
		Vector3i(0, PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT, 0),
		PIPELINE_DATA.BLOCK_STONE
	):
		_fail("Stage 1 accepted an illegal placement at y=150")

	var empty_heights := PackedInt32Array()
	empty_heights.resize(CACHE_WIDTH * CACHE_WIDTH)
	for index in range(empty_heights.size()):
		empty_heights[index] = 10
	var high_override := {
		"0,%d,0" % (PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT - 1): PIPELINE_DATA.BLOCK_STONE,
	}
	var mesh_height := pipeline_runtime._effective_mesh_height(
		Vector2i.ZERO,
		empty_heights,
		high_override
	)
	if mesh_height != PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT:
		_fail(
			"High override did not expand mesh ceiling to 150: %d"
			% mesh_height
		)


func _representative_coords() -> Array[Vector2i]:
	return [
		Vector2i(-4, -2), Vector2i(-2, 1), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(2, -1), Vector2i(4, 2), Vector2i(8, -4), Vector2i(11, -3),
		Vector2i(12, -2), Vector2i(13, -2), Vector2i(14, -1), Vector2i(15, 0),
		Vector2i(16, 1), Vector2i(18, -4), Vector2i(20, 2), Vector2i(-8, 5),
	]


func _validate_equivalence(legacy_data, pipeline_data, pipeline_runtime) -> Dictionary:
	var compared_columns := 0
	var height_checksum := 0
	var biome_checksum := 0
	for coord in _representative_coords():
		var legacy := _legacy_caches(legacy_data, coord)
		var pipeline: Dictionary = pipeline_runtime._build_column_caches(coord)
		var legacy_heights: PackedInt32Array = legacy["heights"]
		var legacy_biomes: PackedByteArray = legacy["biomes"]
		var heights: PackedInt32Array = pipeline.get("heights", PackedInt32Array())
		var biomes: PackedByteArray = pipeline.get("biomes", PackedByteArray())
		var fields: PackedFloat32Array = pipeline.get(
			"world_fields",
			PackedFloat32Array()
		)
		if heights != legacy_heights:
			_fail("Stage 1 height output differs from legacy at chunk %s" % coord)
		if biomes != legacy_biomes:
			_fail("Stage 1 biome output differs from legacy at chunk %s" % coord)
		if fields.size() != CACHE_WIDTH * CACHE_WIDTH * FIELD_STRIDE:
			_fail(
				"Stage 1 field-cache shape changed at %s: %d != %d"
				% [coord, fields.size(), CACHE_WIDTH * CACHE_WIDTH * FIELD_STRIDE]
			)
			continue

		var origin_x := coord.x * CHUNK_SIZE
		var origin_z := coord.y * CHUNK_SIZE
		for cache_z in range(CACHE_WIDTH):
			for cache_x in range(CACHE_WIDTH):
				var column_index := cache_z * CACHE_WIDTH + cache_x
				var world_x := origin_x + cache_x - CACHE_PADDING
				var world_z := origin_z + cache_z - CACHE_PADDING
				var legacy_fields: Vector4 = legacy_data.sample_column_noise(world_x, world_z)
				var legacy_climate: Vector2 = legacy_data.sample_biome_climate(world_x, world_z)
				var field_index := column_index * FIELD_STRIDE
				if not is_equal_approx(
					fields[field_index],
					legacy_fields.x
				):
					_fail("Continentalness cache mismatch at (%d,%d)" % [world_x, world_z])
				if not is_equal_approx(
					fields[field_index + 1],
					legacy_fields.y
				):
					_fail("Terrain-structure cache mismatch at (%d,%d)" % [world_x, world_z])
				if not is_equal_approx(
					fields[field_index + 2],
					legacy_fields.z
				):
					_fail("Terrain-temperature cache mismatch at (%d,%d)" % [world_x, world_z])
				if not is_equal_approx(
					fields[field_index + 3],
					legacy_fields.w
				):
					_fail("Terrain-moisture cache mismatch at (%d,%d)" % [world_x, world_z])
				if not is_equal_approx(
					fields[field_index + 4],
					legacy_climate.x
				):
					_fail("Biome-temperature cache mismatch at (%d,%d)" % [world_x, world_z])
				if not is_equal_approx(
					fields[field_index + 5],
					legacy_climate.y
				):
					_fail("Biome-moisture cache mismatch at (%d,%d)" % [world_x, world_z])
				compared_columns += 1
				height_checksum += int(heights[column_index])
				biome_checksum += int(biomes[column_index]) + 1

	# Direct public queries must also remain equivalent in the legacy vertical
	# range. The only intentional Stage 1 behavioral change is legal headroom.
	for z in range(-48, 49, 6):
		for x in range(-48, 49, 6):
			if pipeline_data.terrain_height(x, z) != legacy_data.terrain_height(x, z):
				_fail("Public terrain_height changed at (%d,%d)" % [x, z])
			if pipeline_data.biome_at(x, z) != legacy_data.biome_at(x, z):
				_fail("Public biome_at changed at (%d,%d)" % [x, z])

	return {
		"compared_columns": compared_columns,
		"height_checksum": height_checksum,
		"biome_checksum": biome_checksum,
	}


func _validate_halo_continuity(pipeline_runtime) -> Dictionary:
	var left: Dictionary = pipeline_runtime._build_column_caches(Vector2i.ZERO)
	var right: Dictionary = pipeline_runtime._build_column_caches(Vector2i(1, 0))
	var left_heights: PackedInt32Array = left["heights"]
	var right_heights: PackedInt32Array = right["heights"]
	var left_biomes: PackedByteArray = left["biomes"]
	var right_biomes: PackedByteArray = right["biomes"]
	var left_fields: PackedFloat32Array = left["world_fields"]
	var right_fields: PackedFloat32Array = right["world_fields"]
	var compared_overlap_columns := 0

	# Chunk (0,0) covers world x=-2..13 and chunk (1,0) covers x=10..25.
	# Their four-column overlap must be byte/numerically identical.
	for world_z in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
		for world_x in range(CHUNK_SIZE - CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
			var left_index := _cache_index(Vector2i.ZERO, world_x, world_z)
			var right_index := _cache_index(Vector2i(1, 0), world_x, world_z)
			if left_heights[left_index] != right_heights[right_index]:
				_fail("Height halo seam at world (%d,%d)" % [world_x, world_z])
			if left_biomes[left_index] != right_biomes[right_index]:
				_fail("Biome halo seam at world (%d,%d)" % [world_x, world_z])
			for field_offset in range(FIELD_STRIDE):
				if not is_equal_approx(
					left_fields[left_index * FIELD_STRIDE + field_offset],
					right_fields[right_index * FIELD_STRIDE + field_offset]
				):
					_fail(
						"World-field halo seam at (%d,%d) field=%d"
						% [world_x, world_z, field_offset]
					)
			compared_overlap_columns += 1

	return {"compared_overlap_columns": compared_overlap_columns}


func _validate_mesh_equivalence(legacy_data, pipeline_runtime) -> Dictionary:
	var compared_chunks := 0
	var face_checksum := 0
	var active_height_max := 0
	for coord in [Vector2i.ZERO, Vector2i(8, -4), Vector2i(15, 0), Vector2i(-8, 5)]:
		var legacy := _legacy_caches(legacy_data, coord)
		var pipeline: Dictionary = pipeline_runtime._build_column_caches(coord)
		var heights: PackedInt32Array = pipeline["heights"]
		var biomes: PackedByteArray = pipeline["biomes"]
		var active_height := pipeline_runtime._effective_mesh_height(coord, heights, {})
		active_height_max = maxi(active_height_max, active_height)
		if active_height >= PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT:
			_fail("Fresh Stage 1 chunk unexpectedly scans the full 150-block height")
		var legacy_mesh: Dictionary = WORLD_MESHER.build(
			coord,
			legacy["heights"],
			{},
			CHUNK_SIZE,
			LEGACY_DATA.WORLD_HEIGHT,
			LEGACY_DATA.SEA_LEVEL,
			legacy["biomes"]
		)
		var pipeline_mesh: Dictionary = WORLD_MESHER.build(
			coord,
			heights,
			{},
			CHUNK_SIZE,
			active_height,
			PIPELINE_DATA.SEA_LEVEL,
			biomes
		)
		for key in ["vertices", "normals", "colors", "indices", "face_count"]:
			if legacy_mesh.get(key) != pipeline_mesh.get(key):
				_fail("Active-height meshing changed %s at chunk %s" % [key, coord])
		face_checksum += int(pipeline_mesh.get("face_count", 0))
		compared_chunks += 1
	return {
		"compared_chunks": compared_chunks,
		"face_checksum": face_checksum,
		"maximum_fresh_mesh_height": active_height_max,
	}


func _legacy_caches(data, coord: Vector2i) -> Dictionary:
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	heights.resize(CACHE_WIDTH * CACHE_WIDTH)
	biomes.resize(CACHE_WIDTH * CACHE_WIDTH)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
		for local_x in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var index := (
				(local_z + CACHE_PADDING) * CACHE_WIDTH
				+ local_x
				+ CACHE_PADDING
			)
			var samples: Vector4 = data.sample_column_noise(world_x, world_z)
			heights[index] = data.terrain_height_from_samples(samples)
			biomes[index] = data.blended_biome_from_samples(samples, world_x, world_z)
	return {"heights": heights, "biomes": biomes}


func _cache_index(coord: Vector2i, world_x: int, world_z: int) -> int:
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	var cache_x := world_x - origin_x + CACHE_PADDING
	var cache_z := world_z - origin_z + CACHE_PADDING
	return cache_z * CACHE_WIDTH + cache_x


func _benchmark_generation(legacy_runtime, pipeline_runtime) -> Dictionary:
	var coords := _representative_coords()
	for _warmup in range(WARMUPS):
		for coord in coords:
			_consume_caches(legacy_runtime._build_column_caches(coord))
			_consume_caches(pipeline_runtime._build_column_caches(coord))

	var legacy_times: Array[int] = []
	var pipeline_times: Array[int] = []
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			if (repetition + index) % 2 == 0:
				legacy_times.append(_measure_cache(legacy_runtime, coord))
				pipeline_times.append(_measure_cache(pipeline_runtime, coord))
			else:
				pipeline_times.append(_measure_cache(pipeline_runtime, coord))
				legacy_times.append(_measure_cache(legacy_runtime, coord))

	var legacy_stats := _stats(legacy_times)
	var pipeline_stats := _stats(pipeline_times)
	return {
		"methodology": {
			"warmups": WARMUPS,
			"repeats": REPEATS,
			"representative_chunks": coords.size(),
			"measured_chunks_per_path": coords.size() * REPEATS,
			"included_work": "padded chunk field sampling, field-cache writes, provisional terrain, water-stage boundary, final height, biome classification and output-cache writes",
			"excluded_work": ["meshing", "rendering", "collision", "scene-tree mutation", "file I/O"],
		},
		"legacy": legacy_stats,
		"pipeline": pipeline_stats,
		"pipeline_over_legacy_p95": float(pipeline_stats["p95_usec"]) / float(legacy_stats["p95_usec"]),
	}


func _measure_cache(runtime, coord: Vector2i) -> int:
	var started := Time.get_ticks_usec()
	_consume_caches(runtime._build_column_caches(coord))
	return maxi(1, Time.get_ticks_usec() - started)


func _consume_caches(caches: Dictionary) -> int:
	var checksum := 0
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	for height in heights:
		checksum += int(height)
	for biome in biomes:
		checksum += int(biome) + 1
	return checksum


func _stats(values: Array[int]) -> Dictionary:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted:
		total += value
	var count := sorted.size()
	var p95_index := clampi(ceili(float(count) * 0.95) - 1, 0, count - 1)
	return {
		"sample_count": count,
		"minimum_usec": sorted[0],
		"maximum_usec": sorted[count - 1],
		"mean_usec": float(total) / float(count),
		"p95_usec": sorted[p95_index],
		"p95_ms": float(sorted[p95_index]) / 1000.0,
	}


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
