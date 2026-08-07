extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage5_generation_data.gd")
const STAGE4_DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const WATER := preload("res://scripts/world/localized_water_bodies.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + PADDING * 2
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
	var contract_report := _validate_contract(data)
	var synthetic_report := _validate_synthetic_valley(data, stage4)
	var field_report := _validate_river_field(data)
	var audit_report := _audit_world(data, stage4)
	var river_chunk := Vector2i(
		int(audit_report.get("river_chunk_x", 0)),
		int(audit_report.get("river_chunk_z", 0))
	)
	var runtime_report := _validate_runtime(runtime, data, river_chunk)
	var renderer_report := _validate_renderer(data, river_chunk)
	var benchmark_report := _benchmark(runtime)
	if int(benchmark_report["p95_usec"]) >= GENERATION_P95_LIMIT_USEC:
		_fail(
			"Stage 5 generation exceeded the 1.0 ms p95 threshold: %d usec"
			% int(benchmark_report["p95_usec"])
		)
	runtime.free()
	var report := {
		"world_height_limit": DATA.OVERHAUL_WORLD_HEIGHT,
		"sea_level": DATA.SEA_LEVEL,
		"contract": contract_report,
		"synthetic_valley": synthetic_report,
		"river_field": field_report,
		"world_audit": audit_report,
		"runtime_equivalence": runtime_report,
		"water_renderer": renderer_report,
		"benchmark": benchmark_report,
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
		_fail("Stage 5 river lattice is too fine for coherent macro corridors")
	if not (
		DATA.STAGE5_CHANNEL_INNER < DATA.STAGE5_CHANNEL_OUTER
		and DATA.STAGE5_CHANNEL_OUTER < DATA.STAGE5_VALLEY_OUTER
		and DATA.STAGE5_VALLEY_INNER < DATA.STAGE5_VALLEY_OUTER
	):
		_fail("Stage 5 channel and valley bands are not ordered")
	if DATA.STAGE5_MAX_VALLEY_CARVE > 32:
		_fail("Stage 5 maximum valley carve is too aggressive")
	var source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage5_generation_data.gd"
	)
	var cache_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage5_cache_fast.gd"
	)
	if source.contains("FastNoiseLite.new") or cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 5 added a new FastNoiseLite stack")
	for required in [
		"stage5_river_signal",
		"stage5_river_strengths_from_signal",
		"stage5_shape_height_from_signal",
		"water_info_at",
		"is_river_column",
	]:
		if not source.contains(required):
			_fail("Stage 5 source is missing %s" % required)
	if not cache_source.contains("river_nodes") or not cache_source.contains("river_signal"):
		_fail("Stage 5 runtime cache does not cache the river field")
	if data.water_type_at(6, 6) != DATA.WATER_NONE:
		_fail("Stage 5 default spawn is inside water")
	return {
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
	var width_scale: float = data.stage5_river_width_scale(fields.x)
	var center_height: int = data.stage5_shape_height_from_signal(fields.x, stage4_height, 0.0)
	var shoulder_value := DATA.STAGE5_VALLEY_INNER * width_scale * 1.35
	var shoulder_height: int = data.stage5_shape_height_from_signal(
		fields.x,
		stage4_height,
		shoulder_value
	)
	var outside_value := DATA.STAGE5_VALLEY_OUTER * width_scale * 1.25
	var outside_height: int = data.stage5_shape_height_from_signal(
		fields.x,
		stage4_height,
		outside_value
	)
	var center_carve := stage4_height - center_height
	if outside_height != stage4_height:
		_fail("Stage 5 changes terrain outside the river valley band")
	if shoulder_height >= stage4_height or shoulder_height <= center_height:
		_fail("Stage 5 mountain crossing is a trench instead of a graded valley")
	if center_carve < 8:
		_fail("Stage 5 river has too little mountain valley influence")
	if center_carve > DATA.STAGE5_MAX_VALLEY_CARVE + DATA.STAGE5_CHANNEL_DEPTH:
		_fail("Stage 5 synthetic mountain crossing exceeds carve safety")
	return {
		"stage4_mountain_height": stage4_height,
		"river_center_height": center_height,
		"valley_shoulder_height": shoulder_height,
		"outside_height": outside_height,
		"center_carve": center_carve,
	}


func _validate_river_field(data) -> Dictionary:
	var sample_count := 0
	var channel_samples := 0
	var valley_samples := 0
	var maximum_neighbor_delta := 0.0
	var maximum_width_delta := 0.0
	for z in range(-384, 385, 8):
		for x in range(-384, 385, 8):
			var river_value: float = data.stage5_river_signal(x, z)
			var east_value: float = data.stage5_river_signal(x + 1, z)
			var south_value: float = data.stage5_river_signal(x, z + 1)
			maximum_neighbor_delta = maxf(
				maximum_neighbor_delta,
				maxf(absf(east_value - river_value), absf(south_value - river_value))
			)
			var c: float = data.continentalness_noise.get_noise_2d(float(x), float(z))
			var strengths: Vector2 = data.stage5_river_strengths_from_signal(c, river_value)
			if strengths.x >= DATA.STAGE5_CHANNEL_WATER_CUTOFF:
				channel_samples += 1
			if strengths.y > 0.10:
				valley_samples += 1
			var east_c: float = data.continentalness_noise.get_noise_2d(float(x + 1), float(z))
			maximum_width_delta = maxf(
				maximum_width_delta,
				absf(data.stage5_river_width_scale(east_c) - data.stage5_river_width_scale(c))
			)
			sample_count += 1
	if maximum_neighbor_delta > 0.08:
		_fail("Stage 5 river field changes too abruptly between adjacent blocks")
	if channel_samples < 40:
		_fail("Stage 5 fixed field audit found too little river channel")
	if valley_samples < channel_samples * 2:
		_fail("Stage 5 valley influence is not broader than the water channel")
	if maximum_width_delta > 0.04:
		_fail("Stage 5 river width changes too abruptly")
	return {
		"sample_count": sample_count,
		"channel_samples": channel_samples,
		"valley_samples": valley_samples,
		"maximum_neighbor_value_delta": maximum_neighbor_delta,
		"maximum_neighbor_width_delta": maximum_width_delta,
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
	var mountain_carve_total := 0
	var maximum_carve := 0
	var river_ocean_joins := 0
	var river_surface_min := 999999
	var river_surface_max := -999999
	var river_chunk := Vector2i.ZERO
	var found_river_chunk := false
	var grid_z := 0
	for z in range(AUDIT_START, AUDIT_FINISH + 1, AUDIT_SPACING):
		var grid_x := 0
		for x in range(AUDIT_START, AUDIT_FINISH + 1, AUDIT_SPACING):
			var fields: Vector4 = data.sample_world_fields(x, z)
			var provisional: int = data.build_provisional_terrain(fields)
			var stage4_height: int = stage4.finalize_height(
				stage4.apply_water_topology(fields, provisional, x, z)
			)
			var is_ocean := stage4.water_type_from_fields(fields, stage4_height) == DATA.WATER_OCEAN
			var river_value: float = data.stage5_river_signal(x, z)
			var strengths: Vector2 = data.stage5_river_strengths_from_signal(fields.x, river_value)
			var stage5_height: int = data.finalize_height(
				data.stage5_shape_height_from_signal(fields.x, stage4_height, river_value)
			)
			var is_river := not is_ocean and strengths.x >= DATA.STAGE5_CHANNEL_WATER_CUTOFF
			var grid_index := grid_z * AUDIT_WIDTH + grid_x
			if is_ocean:
				ocean_grid[grid_index] = 1
				ocean_columns += 1
			elif is_river:
				river_grid[grid_index] = 1
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
					mountain_carve_total += carve
				if fields.x < DATA.STAGE4_COAST_INLAND_END:
					for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						if stage4.is_ocean_column(x + offset.x, z + offset.y):
							river_ocean_joins += 1
							break
			sampled += 1
			grid_x += 1
		grid_z += 1
	if river_columns < 128:
		_fail("Stage 5 fixed audit found too little river geography")
	if river_columns >= int(sampled * 0.20):
		_fail("Stage 5 river channels consume too much land")
	if mountain_river_columns < 8:
		_fail("Stage 5 fixed audit found too few mountain crossings")
	if mountain_river_columns > 0 and float(mountain_carve_total) / float(mountain_river_columns) < 4.0:
		_fail("Stage 5 mountain rivers do not create material valleys")
	if maximum_carve > DATA.STAGE5_MAX_VALLEY_CARVE + DATA.STAGE5_CHANNEL_DEPTH:
		_fail("Stage 5 fixed audit exceeded maximum carve safety")
	if river_ocean_joins < 4:
		_fail("Stage 5 fixed audit found too few river/ocean joins")
	if not found_river_chunk:
		_fail("Stage 5 fixed audit found no inland river above sea level")
	var component_report := _component_stats(river_grid, ocean_grid)
	if int(component_report["long_components"]) < 2:
		_fail("Stage 5 lacks multiple long coherent river corridors")
	if int(component_report["one_chunk_fragments"]) > 0:
		_fail("Stage 5 produced one-chunk river fragments")
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
		"component_count": component_report["component_count"],
		"long_components": component_report["long_components"],
		"one_chunk_fragments": component_report["one_chunk_fragments"],
		"maximum_component_span_blocks": component_report["maximum_component_span_blocks"],
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
			var cell_index: int = queue[cursor]
			cursor += 1
			var grid_x := cell_index % AUDIT_WIDTH
			var grid_z := int(cell_index / AUDIT_WIDTH)
			min_x = mini(min_x, grid_x)
			max_x = maxi(max_x, grid_x)
			min_z = mini(min_z, grid_z)
			max_z = maxi(max_z, grid_z)
			if grid_x == 0 or grid_z == 0 or grid_x == AUDIT_WIDTH - 1 or grid_z == AUDIT_WIDTH - 1:
				touches_boundary = true
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next_x := grid_x + offset.x
				var next_z := grid_z + offset.y
				if next_x < 0 or next_z < 0 or next_x >= AUDIT_WIDTH or next_z >= AUDIT_WIDTH:
					continue
				var neighbor := next_z * AUDIT_WIDTH + next_x
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


func _validate_runtime(runtime, data, river_chunk: Vector2i) -> Dictionary:
	var compared_columns := 0
	var river_columns := 0
	for coord in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-7, 5), river_chunk]:
		var first: Dictionary = runtime._build_column_caches(coord)
		var second: Dictionary = runtime._build_column_caches(coord)
		if first["heights"] != second["heights"] or first.get("river_signal") != second.get("river_signal"):
			_fail("Stage 5 cache is nondeterministic at %s" % coord)
		var heights: PackedInt32Array = first["heights"]
		var river_values: PackedFloat32Array = first.get("river_signal", PackedFloat32Array())
		if river_values.size() != CACHE_WIDTH * CACHE_WIDTH:
			_fail("Stage 5 cache is missing padded river values at %s" % coord)
			continue
		var origin_x := coord.x * CHUNK_SIZE
		var origin_z := coord.y * CHUNK_SIZE
		for local_z in range(-PADDING, CHUNK_SIZE + PADDING):
			for local_x in range(-PADDING, CHUNK_SIZE + PADDING):
				var cache_index := (local_z + PADDING) * CACHE_WIDTH + local_x + PADDING
				var world_x := origin_x + local_x
				var world_z := origin_z + local_z
				var expected_value: float = data.stage5_river_signal(world_x, world_z)
				if absf(river_values[cache_index] - expected_value) > 0.00002:
					_fail("Stage 5 cache/public river mismatch at (%d,%d)" % [world_x, world_z])
				if heights[cache_index] != data.terrain_height(world_x, world_z):
					_fail("Stage 5 cache/public height mismatch at (%d,%d)" % [world_x, world_z])
				if data.is_river_column(world_x, world_z):
					river_columns += 1
				compared_columns += 1
	if river_columns == 0:
		_fail("Stage 5 runtime equivalence set did not exercise river columns")
	return {"compared_columns": compared_columns, "river_columns": river_columns}


func _validate_renderer(data, river_chunk: Vector2i) -> Dictionary:
	var expected_cells := 0
	var river_cells := 0
	var above_sea_cells := 0
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
					above_sea_cells += 1
	var mesh: ArrayMesh = WATER.build_water_mesh(data, river_chunk, CHUNK_SIZE)
	if mesh == null or mesh.get_surface_count() != 1:
		_fail("Stage 5 inland river chunk did not produce water geometry")
		return {}
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != expected_cells * 4 or indices.size() != expected_cells * 6:
		_fail("Stage 5 water geometry does not match explicit water cells")
	var maximum_y := -999999.0
	for vertex in vertices:
		maximum_y = maxf(maximum_y, vertex.y)
	if river_cells == 0 or above_sea_cells == 0 or maximum_y <= float(DATA.SEA_LEVEL) + 0.5:
		_fail("Stage 5 river water is still flattened onto the ocean plane")
	return {
		"river_chunk": [river_chunk.x, river_chunk.y],
		"water_cells": expected_cells,
		"river_cells": river_cells,
		"above_sea_river_cells": above_sea_cells,
		"vertices": vertices.size(),
		"indices": indices.size(),
		"maximum_vertex_y": maximum_y,
	}


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
