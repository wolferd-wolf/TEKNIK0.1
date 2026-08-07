extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage5_generation_data.gd")
const STAGE4_DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const WATER := preload("res://scripts/world/localized_water_bodies.gd")

const CHUNK_SIZE := 12
const CACHE_PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + CACHE_PADDING * 2
const FIELD_STRIDE := 6
const GENERATION_P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20
const AUDIT_START := -512
const AUDIT_FINISH := 512
const AUDIT_SPACING := 4
const AUDIT_WIDTH := int((AUDIT_FINISH - AUDIT_START) / AUDIT_SPACING) + 1

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var stage4 = STAGE4_DATA.new()
	var runtime = RUNTIME.new()
	var contract := _validate_contract(data)
	var synthetic := _validate_synthetic_valley(data, stage4)
	var signal := _validate_signal(data)
	var audit := _audit_world(data, stage4)
	var river_chunk := Vector2i(int(audit.get("river_chunk_x", 0)), int(audit.get("river_chunk_z", 0)))
	var runtime_equivalence := _validate_runtime_equivalence(runtime, data, river_chunk)
	var renderer := _validate_water_renderer(data, river_chunk)
	var determinism := _validate_determinism(runtime, river_chunk)
	var benchmark := _benchmark(runtime)
	if int(benchmark["p95_usec"]) >= GENERATION_P95_LIMIT_USEC:
		_fail(
			"Stage 5 generation exceeded the 1.0 ms p95 threshold: %d usec"
			% int(benchmark["p95_usec"])
		)
	runtime.free()

	var report := {
		"world_height_limit": DATA.OVERHAUL_WORLD_HEIGHT,
		"sea_level": DATA.SEA_LEVEL,
		"contract": contract,
		"synthetic_valley": synthetic,
		"signal": signal,
		"world_audit": audit,
		"runtime_equivalence": runtime_equivalence,
		"water_renderer": renderer,
		"determinism": determinism,
		"benchmark": benchmark,
		"generation_p95_limit_usec": GENERATION_P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE5_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE5_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_contract(data) -> Dictionary:
	if DATA.WATER_RIVER == DATA.WATER_NONE or DATA.WATER_RIVER == DATA.WATER_OCEAN:
		_fail("Stage 5 river water type is not distinct")
	if DATA.STAGE5_RIVER_LATTICE_SPACING < 64:
		_fail("Stage 5 river lattice is too fine for long coherent corridors")
	if not (
		DATA.STAGE5_CHANNEL_INNER < DATA.STAGE5_CHANNEL_OUTER
		and DATA.STAGE5_CHANNEL_OUTER < DATA.STAGE5_VALLEY_OUTER
		and DATA.STAGE5_VALLEY_INNER < DATA.STAGE5_VALLEY_OUTER
	):
		_fail("Stage 5 channel/valley bands are not ordered correctly")
	if DATA.STAGE5_MAX_VALLEY_CARVE > 32:
		_fail("Stage 5 mountain carve can become a giant trench")

	var data_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage5_generation_data.gd"
	)
	if data_source.contains("FastNoiseLite.new"):
		_fail("Stage 5 added a new FastNoiseLite stack")
	for required in [
		"stage5_river_signal",
		"stage5_river_strengths_from_signal",
		"stage5_shape_height_from_signal",
		"water_info_at",
		"is_river_column",
	]:
		if not data_source.contains(required):
			_fail("Stage 5 generation source is missing %s" % required)

	var cache_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage5_cache_fast.gd"
	)
	if not cache_source.contains("river_nodes") or not cache_source.contains("river_signal"):
		_fail("Stage 5 shipping cache is not caching the river field")
	if cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 5 cache added a new FastNoiseLite stack")

	var runtime_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_generation_runtime.gd"
	)
	if not runtime_source.contains("playable_world_stage5_generation_data.gd"):
		_fail("Shipping runtime is not using Stage 5 generation data")
	if not runtime_source.contains("playable_world_stage5_cache_fast.gd"):
		_fail("Shipping runtime is not using the Stage 5 cache")

	if data.water_type_at(6, 6) != DATA.WATER_NONE:
		_fail("Stage 5 default player spawn is inside generated water")

	return {
		"water_none": DATA.WATER_NONE,
		"water_ocean": DATA.WATER_OCEAN,
		"water_river": DATA.WATER_RIVER,
		"river_lattice_spacing": DATA.STAGE5_RIVER_LATTICE_SPACING,
		"river_warp_scale": DATA.STAGE5_RIVER_WARP_SCALE,
		"channel_inner": DATA.STAGE5_CHANNEL_INNER,
		"channel_outer": DATA.STAGE5_CHANNEL_OUTER,
		"valley_inner": DATA.STAGE5_VALLEY_INNER,
		"valley_outer": DATA.STAGE5_VALLEY_OUTER,
		"maximum_valley_carve": DATA.STAGE5_MAX_VALLEY_CARVE,
	}


func _validate_synthetic_valley(data, stage4) -> Dictionary:
	var fields := Vector4(0.0, 0.82, 0.0, 0.0)
	var provisional: int = data.build_provisional_terrain(fields)
	var stage4_height: int = stage4.finalize_height(
		stage4.apply_water_topology(fields, provisional, 0, 0)
	)
	var center: int = data.stage5_shape_height_from_signal(fields.x, stage4_height, 0.0)
	var shoulder_signal := DATA.STAGE5_VALLEY_INNER * data.stage5_river_width_scale(fields.x) * 1.35
	var shoulder: int = data.stage5_shape_height_from_signal(
		fields.x,
		stage4_height,
		shoulder_signal
	)
	var outside_signal := DATA.STAGE5_VALLEY_OUTER * data.stage5_river_width_scale(fields.x) * 1.25
	var outside: int = data.stage5_shape_height_from_signal(
		fields.x,
		stage4_height,
		outside_signal
	)
	var center_carve := stage4_height - center
	if outside != stage4_height:
		_fail("Stage 5 river changes terrain outside its valley band")
	if shoulder >= stage4_height or shoulder <= center:
		_fail("Stage 5 mountain crossing does not form a broad graded valley")
	if center_carve < 8:
		_fail("Stage 5 river has too little mountain-valley influence")
	if center_carve > DATA.STAGE5_MAX_VALLEY_CARVE + DATA.STAGE5_CHANNEL_DEPTH:
		_fail("Stage 5 synthetic mountain crossing exceeds the carve safety limit")
	return {
		"stage4_mountain_height": stage4_height,
		"river_center_height": center,
		"valley_shoulder_height": shoulder,
		"outside_height": outside,
		"center_carve": center_carve,
	}


func _validate_signal(data) -> Dictionary:
	var sample_count := 0
	var river_band_samples := 0
	var valley_band_samples := 0
	var maximum_neighbor_delta := 0.0
	var maximum_width_scale_delta := 0.0
	for z in range(-384, 385, 8):
		for x in range(-384, 385, 8):
			var signal: float = data.stage5_river_signal(x, z)
			var east_signal: float = data.stage5_river_signal(x + 1, z)
			var south_signal: float = data.stage5_river_signal(x, z + 1)
			maximum_neighbor_delta = maxf(
				maximum_neighbor_delta,
				maxf(absf(east_signal - signal), absf(south_signal - signal))
			)
			var c: float = data.continentalness_noise.get_noise_2d(float(x), float(z))
			var strengths: Vector2 = data.stage5_river_strengths_from_signal(c, signal)
			if strengths.x >= DATA.STAGE5_CHANNEL_WATER_CUTOFF:
				river_band_samples += 1
			if strengths.y > 0.10:
				valley_band_samples += 1
			var width_scale := data.stage5_river_width_scale(c)
			var east_c: float = data.continentalness_noise.get_noise_2d(float(x + 1), float(z))
			maximum_width_scale_delta = maxf(
				maximum_width_scale_delta,
				absf(data.stage5_river_width_scale(east_c) - width_scale)
			)
			sample_count += 1
	if maximum_neighbor_delta > 0.08:
		_fail("Stage 5 river field changes too abruptly between adjacent columns")
	if river_band_samples < 40:
		_fail("Stage 5 fixed signal audit found too little river-channel field")
	if valley_band_samples < river_band_samples * 2:
		_fail("Stage 5 valley influence is not materially broader than the water channel")
	if maximum_width_scale_delta > 0.04:
		_fail("Stage 5 river width changes too abruptly between adjacent columns")
	return {
		"sample_count": sample_count,
		"river_band_samples": river_band_samples,
		"valley_band_samples": valley_band_samples,
		"maximum_neighbor_signal_delta": maximum_neighbor_delta,
		"maximum_neighbor_width_scale_delta": maximum_width_scale_delta,
	}


func _audit_world(data, stage4) -> Dictionary:
	var river_grid := PackedByteArray()
	var ocean_grid := PackedByteArray()
	river_grid.resize(AUDIT_WIDTH * AUDIT_WIDTH)
	ocean_grid.resize(AUDIT_WIDTH * AUDIT_WIDTH)
	var sampled := 0
	var river_columns := 0
	var ocean_columns := 0
	var mountain_river_columns := 0
	var mountain_valley_carve_total := 0
	var maximum_carve := 0
	var river_ocean_joins := 0
	var river_surface_min := 999999
	var river_surface_max := -999999
	var river_chunk := Vector2i.ZERO
	var found_river_chunk := false

	var gz := 0
	for z in range(AUDIT_START, AUDIT_FINISH + 1, AUDIT_SPACING):
		var gx := 0
		for x in range(AUDIT_START, AUDIT_FINISH + 1, AUDIT_SPACING):
			var fields: Vector4 = data.sample_world_fields(x, z)
			var provisional: int = data.build_provisional_terrain(fields)
			var stage4_height: int = stage4.finalize_height(
				stage4.apply_water_topology(fields, provisional, x, z)
			)
			var ocean := stage4.water_type_from_fields(fields, stage4_height) == DATA.WATER_OCEAN
			var signal: float = data.stage5_river_signal(x, z)
			var strengths: Vector2 = data.stage5_river_strengths_from_signal(fields.x, signal)
			var stage5_height: int = data.finalize_height(
				data.stage5_shape_height_from_signal(fields.x, stage4_height, signal)
			)
			var river := (
				not ocean
				and strengths.x >= DATA.STAGE5_CHANNEL_WATER_CUTOFF
			)
			var index := gz * AUDIT_WIDTH + gx
			if ocean:
				ocean_grid[index] = 1
				ocean_columns += 1
			elif river:
				river_grid[index] = 1
				river_columns += 1
				var surface_y := stage5_height + 1
				river_surface_min = mini(river_surface_min, surface_y)
				river_surface_max = maxi(river_surface_max, surface_y)
				if not found_river_chunk and fields.x >= DATA.STAGE4_COAST_INLAND_END and surface_y > DATA.SEA_LEVEL + 1:
					river_chunk = Vector2i(
						floori(float(x) / float(CHUNK_SIZE)),
						floori(float(z) / float(CHUNK_SIZE))
					)
					found_river_chunk = true
				var carve := stage4_height - stage5_height
				maximum_carve = maxi(maximum_carve, carve)
				if provisional >= 48:
					mountain_river_columns += 1
					mountain_valley_carve_total += carve
				if fields.x < DATA.STAGE4_COAST_INLAND_END:
					for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						if stage4.is_ocean_column(x + offset.x, z + offset.y):
							river_ocean_joins += 1
							break
			sampled += 1
			gx += 1
		gz += 1

	if river_columns < 128:
		_fail("Stage 5 fixed audit found too little river geography")
	if river_columns >= int(sampled * 0.20):
		_fail("Stage 5 river channels consume too much of the fixed audit world")
	if mountain_river_columns < 8:
		_fail("Stage 5 fixed audit found too few mountain river crossings")
	if mountain_river_columns > 0:
		var mean_mountain_carve := float(mountain_valley_carve_total) / float(mountain_river_columns)
		if mean_mountain_carve < 4.0:
			_fail("Stage 5 mountain rivers are painted over peaks instead of shaping valleys")
	if maximum_carve > DATA.STAGE5_MAX_VALLEY_CARVE + DATA.STAGE5_CHANNEL_DEPTH:
		_fail("Stage 5 fixed audit exceeded the mountain carve safety limit")
	if river_ocean_joins < 4:
		_fail("Stage 5 fixed audit found too few clean river/ocean joins")
	if not found_river_chunk:
		_fail("Stage 5 fixed audit found no inland river chunk above sea level")

	var components := _component_stats(river_grid, ocean_grid)
	if int(components["long_components"]) < 2:
		_fail("Stage 5 river field lacks multiple long coherent corridors")
	if int(components["one_chunk_fragments"]) > 0:
		_fail("Stage 5 produced one-chunk river fragments away from ocean/audit edges")

	return {
		"sample_spacing_blocks": AUDIT_SPACING,
		"sampled_columns": sampled,
		"river_columns": river_columns,
		"river_ratio": float(river_columns) / float(sampled),
		"ocean_columns": ocean_columns,
		"mountain_river_columns": mountain_river_columns,
		"maximum_carve": maximum_carve,
		"river_ocean_joins": river_ocean_joins,
		"river_surface_min": river_surface_min,
		"river_surface_max": river_surface_max,
		"component_count": components["component_count"],
		"long_components": components["long_components"],
		"one_chunk_fragments": components["one_chunk_fragments"],
		"maximum_component_span_blocks": components["maximum_component_span_blocks"],
		"river_chunk_x": river_chunk.x,
		"river_chunk_z": river_chunk.y,
	}


func _component_stats(river_grid: PackedByteArray, ocean_grid: PackedByteArray) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(river_grid.size())
	var component_count := 0
	var long_components := 0
	var one_chunk_fragments := 0
	var maximum_span := 0
	for start_index in range(river_grid.size()):
		if river_grid[start_index] == 0 or visited[start_index] != 0:
			continue
		component_count += 1
		var queue: Array[int] = [start_index]
		visited[start_index] = 1
		var cursor := 0
		var min_x := AUDIT_WIDTH
		var max_x := -1
		var min_z := AUDIT_WIDTH
		var max_z := -1
		var touches_boundary := false
		var touches_ocean := false
		while cursor < queue.size():
			var index: int = queue[cursor]
			cursor += 1
			var gx := index % AUDIT_WIDTH
			var gz := int(index / AUDIT_WIDTH)
			min_x = mini(min_x, gx)
			max_x = maxi(max_x, gx)
			min_z = mini(min_z, gz)
			max_z = maxi(max_z, gz)
			if gx == 0 or gz == 0 or gx == AUDIT_WIDTH - 1 or gz == AUDIT_WIDTH - 1:
				touches_boundary = true
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var nx := gx + offset.x
				var nz := gz + offset.y
				if nx < 0 or nz < 0 or nx >= AUDIT_WIDTH or nz >= AUDIT_WIDTH:
					continue
				var neighbor := nz * AUDIT_WIDTH + nx
				if ocean_grid[neighbor] != 0:
					touches_ocean = true
				if river_grid[neighbor] != 0 and visited[neighbor] == 0:
					visited[neighbor] = 1
					queue.append(neighbor)
		var span_blocks := maxi(max_x - min_x + 1, max_z - min_z + 1) * AUDIT_SPACING
		maximum_span = maxi(maximum_span, span_blocks)
		if span_blocks >= 96:
			long_components += 1
		if span_blocks <= CHUNK_SIZE and not touches_boundary and not touches_ocean:
			one_chunk_fragments += 1
	return {
		"component_count": component_count,
		"long_components": long_components,
		"one_chunk_fragments": one_chunk_fragments,
		"maximum_component_span_blocks": maximum_span,
	}


func _validate_runtime_equivalence(runtime, data, river_chunk: Vector2i) -> Dictionary:
	var compared_heights := 0
	var compared_signals := 0
	var river_affected_heights := 0
	var coords: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(3, -2),
		Vector2i(-7, 5),
		river_chunk,
	]
	for coord in coords:
		var cache: Dictionary = runtime._build_column_caches(coord)
		var heights: PackedInt32Array = cache["heights"]
		var signals: PackedFloat32Array = cache.get("river_signal", PackedFloat32Array())
		if signals.size() != CACHE_WIDTH * CACHE_WIDTH:
			_fail("Stage 5 runtime cache is missing its padded river field at %s" % coord)
			continue
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
				var expected_signal: float = data.stage5_river_signal(world_x, world_z)
				if absf(signals[index] - expected_signal) > 0.00002:
					_fail("Stage 5 runtime/public river signal mismatch at (%d,%d)" % [world_x, world_z])
				if heights[index] != data.terrain_height(world_x, world_z):
					_fail("Stage 5 runtime/public height mismatch at (%d,%d)" % [world_x, world_z])
				if data.is_river_column(world_x, world_z):
					river_affected_heights += 1
				compared_signals += 1
				compared_heights += 1
	if river_affected_heights == 0:
		_fail("Stage 5 runtime equivalence set did not exercise a river column")
	return {
		"compared_heights": compared_heights,
		"compared_river_signals": compared_signals,
		"river_columns_in_equivalence_chunks": river_affected_heights,
	}


func _validate_water_renderer(data, river_chunk: Vector2i) -> Dictionary:
	var expected_cells := 0
	var river_cells := 0
	var above_sea_river_cells := 0
	for local_z in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			var world_x := river_chunk.x * CHUNK_SIZE + local_x
			var world_z := river_chunk.y * CHUNK_SIZE + local_z
			var info: Vector2i = data.water_info_at(world_x, world_z)
			if info.x == DATA.WATER_NONE:
				continue
			expected_cells += 1
			if info.x == DATA.WATER_RIVER:
				river_cells += 1
				if info.y > DATA.SEA_LEVEL:
					above_sea_river_cells += 1
	var mesh: ArrayMesh = WATER.build_water_mesh(data, river_chunk, CHUNK_SIZE)
	if mesh == null or mesh.get_surface_count() != 1:
		_fail("Stage 5 inland river chunk did not produce a water mesh")
		return {}
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != expected_cells * 4 or indices.size() != expected_cells * 6:
		_fail("Stage 5 water mesh geometry does not match explicit water topology")
	if river_cells == 0 or above_sea_river_cells == 0:
		_fail("Stage 5 renderer audit did not exercise inland river water above sea level")
	var minimum_vertex_y := 999999.0
	var maximum_vertex_y := -999999.0
	for vertex in vertices:
		minimum_vertex_y = minf(minimum_vertex_y, vertex.y)
		maximum_vertex_y = maxf(maximum_vertex_y, vertex.y)
	if maximum_vertex_y <= float(DATA.SEA_LEVEL) + 0.5:
		_fail("Stage 5 river mesh is still forced onto the global ocean plane")
	return {
		"river_chunk": [river_chunk.x, river_chunk.y],
		"water_cells": expected_cells,
		"river_cells": river_cells,
		"above_sea_river_cells": above_sea_river_cells,
		"vertices": vertices.size(),
		"indices": indices.size(),
		"minimum_vertex_y": minimum_vertex_y,
		"maximum_vertex_y": maximum_vertex_y,
	}


func _validate_determinism(runtime, river_chunk: Vector2i) -> Dictionary:
	var compared_chunks := 0
	for coord in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-7, 5), river_chunk]:
		var first: Dictionary = runtime._build_column_caches(coord)
		var second: Dictionary = runtime._build_column_caches(coord)
		if first["world_fields"] != second["world_fields"]:
			_fail("Stage 5 field generation is nondeterministic at %s" % coord)
		if first["heights"] != second["heights"]:
			_fail("Stage 5 height generation is nondeterministic at %s" % coord)
		if first.get("river_signal") != second.get("river_signal"):
			_fail("Stage 5 river generation is nondeterministic at %s" % coord)
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
