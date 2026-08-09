extends SceneTree

const DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const WATER := preload("res://scripts/world/localized_water_bodies.gd")

const CHUNK_SIZE := 12
const CACHE_PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + CACHE_PADDING * 2
const GENERATION_P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var runtime = RUNTIME.new()
	var contract := _validate_contract(data)
	var profile := _validate_synthetic_coast_profile(data)
	var world_audit := _audit_world(data)
	var runtime_equivalence := _validate_runtime_equivalence(runtime, data)
	var water_mesh := _validate_water_renderer(data)
	var determinism := _validate_determinism(runtime)
	var benchmark := _benchmark(runtime)
	if int(benchmark["p95_usec"]) >= GENERATION_P95_LIMIT_USEC:
		_fail(
			"Stage 4 generation exceeded the 1.0 ms p95 threshold: %d usec"
			% int(benchmark["p95_usec"])
		)
	runtime.free()

	var report := {
		"world_height_limit": DATA.OVERHAUL_WORLD_HEIGHT,
		"sea_level": DATA.SEA_LEVEL,
		"contract": contract,
		"synthetic_coast_profile": profile,
		"world_audit": world_audit,
		"runtime_equivalence": runtime_equivalence,
		"water_renderer": water_mesh,
		"determinism": determinism,
		"benchmark": benchmark,
		"generation_p95_limit_usec": GENERATION_P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE4_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE4_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_contract(data) -> Dictionary:
	if DATA.WATER_NONE != 0 or DATA.WATER_OCEAN == DATA.WATER_NONE:
		_fail("Stage 4 water-type contract is invalid")
	if not (
		DATA.STAGE4_OCEAN_BASIN_FULL < DATA.STAGE4_OCEAN_WATER_START
		and DATA.STAGE4_OCEAN_WATER_START < DATA.STAGE4_COAST_INLAND_END
	):
		_fail("Stage 4 continentalness thresholds are not ordered ocean -> coast -> inland")
	if DATA.STAGE4_OCEAN_EDGE_FLOOR >= DATA.SEA_LEVEL:
		_fail("Stage 4 ocean edge is not physically below sea level")
	if DATA.STAGE4_OCEAN_CORE_FLOOR > DATA.STAGE4_OCEAN_EDGE_FLOOR:
		_fail("Stage 4 ocean core is shallower than the continental shelf")

	var source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_generation_data.gd"
	)
	if source.contains("FastNoiseLite.new"):
		_fail("Stage 4 added a new FastNoiseLite stack instead of deriving water topology")
	for required in [
		"apply_water_topology",
		"water_type_from_fields",
		"water_type_at",
		"is_ocean_column",
		"is_coast_column",
	]:
		if not source.contains(required):
			_fail("Stage 4 generation source is missing %s" % required)

	var water_source := FileAccess.get_file_as_string(
		"res://scripts/world/localized_water_bodies.gd"
	)
	if not water_source.contains("is_ocean_column"):
		_fail("Shipping water rendering is not consuming explicit Stage 4 ocean topology")

	return {
		"water_none": DATA.WATER_NONE,
		"water_ocean": DATA.WATER_OCEAN,
		"ocean_water_start": DATA.STAGE4_OCEAN_WATER_START,
		"ocean_basin_full": DATA.STAGE4_OCEAN_BASIN_FULL,
		"coast_inland_end": DATA.STAGE4_COAST_INLAND_END,
		"ocean_edge_floor": DATA.STAGE4_OCEAN_EDGE_FLOOR,
		"ocean_core_floor": DATA.STAGE4_OCEAN_CORE_FLOOR,
	}


func _height_from_fields(data, fields: Vector4) -> int:
	var provisional: int = data.build_provisional_terrain(fields)
	return data.finalize_height(data.apply_water_topology(fields, provisional, 0, 0))


func _validate_synthetic_coast_profile(data) -> Dictionary:
	var structure := -0.45
	var core_fields := Vector4(DATA.STAGE4_OCEAN_BASIN_FULL - 0.08, structure, 0.0, 0.0)
	var edge_fields := Vector4(DATA.STAGE4_OCEAN_WATER_START, structure, 0.0, 0.0)
	var shore_fields := Vector4(DATA.STAGE4_OCEAN_WATER_START + 0.01, structure, 0.0, 0.0)
	var mid_fields := Vector4(
		(DATA.STAGE4_OCEAN_WATER_START + DATA.STAGE4_COAST_INLAND_END) * 0.5,
		structure,
		0.0,
		0.0
	)
	var inland_fields := Vector4(DATA.STAGE4_COAST_INLAND_END, structure, 0.0, 0.0)

	var core_height := _height_from_fields(data, core_fields)
	var edge_height := _height_from_fields(data, edge_fields)
	var shore_height := _height_from_fields(data, shore_fields)
	var mid_height := _height_from_fields(data, mid_fields)
	var inland_provisional: int = data.build_provisional_terrain(inland_fields)
	var inland_height := _height_from_fields(data, inland_fields)

	if core_height > DATA.STAGE4_OCEAN_CORE_FLOOR:
		_fail("Stage 4 ocean core did not reach its intended deep floor")
	if edge_height >= DATA.SEA_LEVEL:
		_fail("Stage 4 continental shelf is not below sea level")
	if data.water_type_from_fields(edge_fields, edge_height) != DATA.WATER_OCEAN:
		_fail("Stage 4 ocean edge is not classified as ocean")
	if data.water_type_from_fields(shore_fields, shore_height) != DATA.WATER_NONE:
		_fail("Stage 4 dry shore is incorrectly classified as ocean")
	if shore_height < DATA.SEA_LEVEL:
		_fail("Stage 4 first dry coastal column fell below sea level")
	if mid_height < shore_height:
		_fail("Stage 4 coast descends while moving inland")
	if inland_height != inland_provisional:
		_fail("Stage 4 changed terrain after the coastal transition ended")
	return {
		"core_height": core_height,
		"edge_height": edge_height,
		"shore_height": shore_height,
		"mid_coast_height": mid_height,
		"inland_height": inland_height,
		"inland_provisional": inland_provisional,
	}


func _audit_world(data) -> Dictionary:
	var sampled := 0
	var ocean_columns := 0
	var coast_columns := 0
	var ocean_core_columns := 0
	var ocean_height_min := 999999
	var ocean_height_max := -999999
	var shoreline_adjacencies := 0
	var renderer_agreements := 0
	var inland_low_columns := 0

	for z in range(-512, 513, 4):
		for x in range(-512, 513, 4):
			var fields: Vector4 = data.sample_world_fields(x, z)
			var provisional: int = data.build_provisional_terrain(fields)
			var height: int = data.finalize_height(
				data.apply_water_topology(fields, provisional, x, z)
			)
			var water_type: int = data.water_type_from_fields(fields, height)
			var ocean := water_type == DATA.WATER_OCEAN
			if ocean:
				ocean_columns += 1
				ocean_height_min = mini(ocean_height_min, height)
				ocean_height_max = maxi(ocean_height_max, height)
				if height >= DATA.SEA_LEVEL:
					_fail("Stage 4 ocean column is not below sea level at (%d,%d)" % [x, z])
				if fields.x <= DATA.STAGE4_OCEAN_BASIN_FULL:
					ocean_core_columns += 1
				if shoreline_adjacencies < 256:
					for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						if not data.is_ocean_column(x + offset.x, z + offset.y):
							shoreline_adjacencies += 1
							break
			elif fields.x > DATA.STAGE4_OCEAN_WATER_START and fields.x < DATA.STAGE4_COAST_INLAND_END:
				coast_columns += 1
			if height < DATA.SEA_LEVEL and fields.x >= DATA.STAGE4_COAST_INLAND_END:
				inland_low_columns += 1
			if renderer_agreements < 512:
				if WATER.is_water_column(data, x, z) != ocean:
					_fail("Stage 4 renderer/topology disagreement at (%d,%d)" % [x, z])
				renderer_agreements += 1
			sampled += 1

	if ocean_columns < 64:
		_fail("Stage 4 fixed audit found too little ocean geography")
	if coast_columns < 128:
		_fail("Stage 4 fixed audit found too little coastal transition geography")
	if ocean_columns >= int(sampled * 0.50):
		_fail("Stage 4 ocean topology consumed at least half the fixed audit world")
	if shoreline_adjacencies < 8:
		_fail("Stage 4 fixed audit found no meaningful ocean/land shoreline")
	if ocean_height_min < 3 or ocean_height_max >= DATA.SEA_LEVEL:
		_fail("Stage 4 ocean floor escaped its legal vertical interval")
	if data.is_ocean_column(6, 6):
		_fail("Stage 4 default player spawn falls inside the ocean")

	return {
		"sample_spacing_blocks": 4,
		"sampled_columns": sampled,
		"ocean_columns": ocean_columns,
		"ocean_ratio": float(ocean_columns) / float(sampled),
		"coast_columns": coast_columns,
		"coast_ratio": float(coast_columns) / float(sampled),
		"ocean_core_columns": ocean_core_columns,
		"ocean_height_min": ocean_height_min,
		"ocean_height_max": ocean_height_max,
		"shoreline_adjacencies": shoreline_adjacencies,
		"renderer_agreements": renderer_agreements,
		"inland_low_columns_not_ocean": inland_low_columns,
		"spawn_is_ocean": data.is_ocean_column(6, 6),
	}


func _validate_runtime_equivalence(runtime, data) -> Dictionary:
	var compared_heights := 0
	var ocean_columns := 0
	for coord_value in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-7, 5), Vector2i(11, 9)]:
		var coord: Vector2i = coord_value
		var cache: Dictionary = runtime._build_column_caches(coord)
		var heights: PackedInt32Array = cache["heights"]
		var origin_x := coord.x * CHUNK_SIZE
		var origin_z := coord.y * CHUNK_SIZE
		for local_z in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
			for local_x in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
				var index := (
					(local_z + CACHE_PADDING) * CACHE_WIDTH
					+ local_x
					+ CACHE_PADDING
				)
				var world_x := origin_x + local_x
				var world_z := origin_z + local_z
				if heights[index] != data.terrain_height(world_x, world_z):
					_fail("Stage 4 runtime/public height mismatch at (%d,%d)" % [world_x, world_z])
				if data.is_ocean_column(world_x, world_z):
					ocean_columns += 1
				compared_heights += 1
	return {
		"compared_heights": compared_heights,
		"ocean_columns_in_equivalence_chunks": ocean_columns,
	}


func _validate_water_renderer(data) -> Dictionary:
	var ocean_chunk := Vector2i(2147483647, 2147483647)
	var ocean_cells := 0
	var dry_chunk := Vector2i(2147483647, 2147483647)
	for chunk_z in range(-32, 33):
		for chunk_x in range(-32, 33):
			var coord := Vector2i(chunk_x, chunk_z)
			var cells := 0
			for local_z in range(CHUNK_SIZE):
				for local_x in range(CHUNK_SIZE):
					if data.is_ocean_column(
						chunk_x * CHUNK_SIZE + local_x,
						chunk_z * CHUNK_SIZE + local_z
					):
						cells += 1
			if cells > 0 and ocean_chunk.x == 2147483647:
				ocean_chunk = coord
				ocean_cells = cells
			if cells == 0 and dry_chunk.x == 2147483647:
				dry_chunk = coord
			if ocean_chunk.x != 2147483647 and dry_chunk.x != 2147483647:
				break
		if ocean_chunk.x != 2147483647 and dry_chunk.x != 2147483647:
			break

	if ocean_chunk.x == 2147483647:
		_fail("Stage 4 renderer audit found no ocean chunk")
		return {}
	var ocean_mesh: ArrayMesh = WATER.build_water_mesh(data, ocean_chunk, CHUNK_SIZE)
	if ocean_mesh == null or ocean_mesh.get_surface_count() != 1:
		_fail("Stage 4 ocean chunk did not produce one water mesh")
		return {}
	var arrays: Array = ocean_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != ocean_cells * 4 or indices.size() != ocean_cells * 6:
		_fail("Stage 4 water mesh geometry does not exactly match explicit ocean cells")

	if dry_chunk.x == 2147483647:
		_fail("Stage 4 renderer audit found no dry chunk")
	elif WATER.build_water_mesh(data, dry_chunk, CHUNK_SIZE) != null:
		_fail("Stage 4 dry chunk unexpectedly produced ocean geometry")

	return {
		"ocean_chunk": [ocean_chunk.x, ocean_chunk.y],
		"ocean_cells": ocean_cells,
		"vertices": vertices.size(),
		"indices": indices.size(),
		"dry_chunk": [dry_chunk.x, dry_chunk.y],
	}


func _validate_determinism(runtime) -> Dictionary:
	var compared_chunks := 0
	for coord in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-7, 5), Vector2i(11, 9)]:
		var first: Dictionary = runtime._build_column_caches(coord)
		var second: Dictionary = runtime._build_column_caches(coord)
		if first["world_fields"] != second["world_fields"]:
			_fail("Stage 4 field generation is nondeterministic at %s" % coord)
		if first["heights"] != second["heights"]:
			_fail("Stage 4 height generation is nondeterministic at %s" % coord)
		if first["biomes"] != second["biomes"]:
			_fail("Stage 4 biome cache became nondeterministic at %s" % coord)
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