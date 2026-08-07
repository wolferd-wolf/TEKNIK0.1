extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage5_generation_data.gd")
const STAGE4_DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const WATER := preload("res://scripts/world/localized_water_bodies.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const CACHE_WIDTH := 16
const LIMIT_USEC := 1000
const AUDIT_START := -512
const AUDIT_FINISH := 512
const AUDIT_STEP := 4
const AUDIT_WIDTH := 257

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var stage4 = STAGE4_DATA.new()
	var runtime = RUNTIME.new()
	var contract: Dictionary = _contract(data)
	var synthetic: Dictionary = _synthetic(data, stage4)
	var field_stats: Dictionary = _field_stats(data)
	var audit: Dictionary = _world_audit(data, stage4)
	var river_chunk := Vector2i(
		int(audit.get("river_chunk_x", 0)),
		int(audit.get("river_chunk_z", 0))
	)
	var runtime_stats: Dictionary = _runtime_equivalence(runtime, data, river_chunk)
	var renderer_stats: Dictionary = _renderer(data, river_chunk)
	var benchmark: Dictionary = _benchmark(runtime)
	if int(benchmark["p95_usec"]) >= LIMIT_USEC:
		_fail("Stage 5 generation exceeded 1.0 ms p95: %d usec" % int(benchmark["p95_usec"]))
	runtime.free()
	var report: Dictionary = {
		"world_height_limit": DATA.OVERHAUL_WORLD_HEIGHT,
		"sea_level": DATA.SEA_LEVEL,
		"contract": contract,
		"synthetic_valley": synthetic,
		"river_field": field_stats,
		"world_audit": audit,
		"runtime_equivalence": runtime_stats,
		"water_renderer": renderer_stats,
		"benchmark": benchmark,
		"generation_p95_limit_usec": LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE5_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE5_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _contract(data) -> Dictionary:
	if DATA.WATER_RIVER == DATA.WATER_NONE or DATA.WATER_RIVER == DATA.WATER_OCEAN:
		_fail("River water type is not distinct")
	if DATA.STAGE5_RIVER_LATTICE_SPACING < 64:
		_fail("River meander lattice is too fine")
	if DATA.STAGE5_MAX_VALLEY_CARVE > 32:
		_fail("River valley carve safety cap is too large")
	var source := FileAccess.get_file_as_string("res://scripts/world/playable_world_stage5_generation_data.gd")
	var cache_source := FileAccess.get_file_as_string("res://scripts/world/playable_world_stage5_cache_fast.gd")
	if source.contains("FastNoiseLite.new") or cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 5 added a FastNoiseLite stack")
	if not cache_source.contains("stage5_river_row_phase"):
		_fail("Shipping cache is not using the direct row-phase river field")
	if cache_source.contains("river_nodes") or cache_source.contains("river_signal.resize"):
		_fail("Shipping cache reintroduced redundant persistent river-field storage")
	if int(data.water_type_at(6, 6)) != DATA.WATER_NONE:
		_fail("Default spawn is inside Stage 5 water")
	return {
		"water_river": DATA.WATER_RIVER,
		"river_meander_lattice_spacing": DATA.STAGE5_RIVER_LATTICE_SPACING,
		"river_spacing": DATA.STAGE5_RIVER_SPACING,
		"channel_inner": DATA.STAGE5_CHANNEL_INNER,
		"channel_outer": DATA.STAGE5_CHANNEL_OUTER,
		"valley_inner": DATA.STAGE5_VALLEY_INNER,
		"valley_outer": DATA.STAGE5_VALLEY_OUTER,
		"maximum_valley_carve": DATA.STAGE5_MAX_VALLEY_CARVE,
		"persistent_river_cache": false,
	}


func _synthetic(data, stage4) -> Dictionary:
	var fields := Vector4(0.0, 0.82, 0.0, 0.0)
	var provisional := int(data.build_provisional_terrain(fields))
	var stage4_height := int(stage4.finalize_height(stage4.apply_water_topology(fields, provisional, 0, 0)))
	var scale := float(data.stage5_river_width_scale(fields.x))
	var center := int(data.stage5_shape_height_from_signal(fields.x, stage4_height, 0.0))
	var shoulder_value := DATA.STAGE5_VALLEY_INNER * scale * 1.35
	var outside_value := DATA.STAGE5_VALLEY_OUTER * scale * 1.25
	var shoulder := int(data.stage5_shape_height_from_signal(fields.x, stage4_height, shoulder_value))
	var outside := int(data.stage5_shape_height_from_signal(fields.x, stage4_height, outside_value))
	var carve := stage4_height - center
	if outside != stage4_height:
		_fail("River changes terrain outside valley band")
	if shoulder >= stage4_height or shoulder <= center:
		_fail("Mountain river crossing is not a graded valley")
	if carve < 8 or carve > DATA.STAGE5_MAX_VALLEY_CARVE + DATA.STAGE5_CHANNEL_DEPTH:
		_fail("Mountain river carve is outside safe/material range")
	return {"stage4_height": stage4_height, "center": center, "shoulder": shoulder, "outside": outside, "carve": carve}


func _field_stats(data) -> Dictionary:
	var samples := 0
	var channel_samples := 0
	var valley_samples := 0
	var max_neighbor_delta := 0.0
	var max_width_delta := 0.0
	for z: int in range(-384, 385, 8):
		for x: int in range(-384, 385, 8):
			var value := float(data.stage5_river_signal(x, z))
			var east := float(data.stage5_river_signal(x + 1, z))
			var south := float(data.stage5_river_signal(x, z + 1))
			max_neighbor_delta = maxf(max_neighbor_delta, maxf(absf(east - value), absf(south - value)))
			var c := data.continentalness_noise.get_noise_2d(float(x), float(z))
			var strengths: Vector2 = data.stage5_river_strengths_from_signal(c, value)
			if strengths.x >= DATA.STAGE5_CHANNEL_WATER_CUTOFF:
				channel_samples += 1
			if strengths.y > 0.10:
				valley_samples += 1
			var east_c := data.continentalness_noise.get_noise_2d(float(x + 1), float(z))
			max_width_delta = maxf(max_width_delta, absf(float(data.stage5_river_width_scale(east_c)) - float(data.stage5_river_width_scale(c))))
			samples += 1
	if max_neighbor_delta > 0.08:
		_fail("River field changes too abruptly between adjacent blocks")
	if channel_samples < 40:
		_fail("River field is too sparse")
	if valley_samples < channel_samples * 2:
		_fail("Valley band is not materially broader than channel")
	if max_width_delta > 0.04:
		_fail("River width changes too abruptly")
	return {"samples": samples, "channel_samples": channel_samples, "valley_samples": valley_samples, "max_neighbor_delta": max_neighbor_delta, "max_width_delta": max_width_delta}


func _world_audit(data, stage4) -> Dictionary:
	var river_grid := PackedByteArray()
	var ocean_grid := PackedByteArray()
	river_grid.resize(AUDIT_WIDTH * AUDIT_WIDTH)
	ocean_grid.resize(AUDIT_WIDTH * AUDIT_WIDTH)
	var sampled := 0
	var rivers := 0
	var oceans := 0
	var mountain_rivers := 0
	var mountain_carve_sum := 0
	var max_carve := 0
	var ocean_joins := 0
	var surface_min := 999999
	var surface_max := -999999
	var chosen_chunk := Vector2i.ZERO
	var found_chunk := false
	var gz := 0
	for z: int in range(AUDIT_START, AUDIT_FINISH + 1, AUDIT_STEP):
		var gx := 0
		for x: int in range(AUDIT_START, AUDIT_FINISH + 1, AUDIT_STEP):
			var fields: Vector4 = data.sample_world_fields(x, z)
			var provisional := int(data.build_provisional_terrain(fields))
			var stage4_height := int(stage4.finalize_height(stage4.apply_water_topology(fields, provisional, x, z)))
			var is_ocean := int(stage4.water_type_from_fields(fields, stage4_height)) == DATA.WATER_OCEAN
			var value := float(data.stage5_river_signal(x, z))
			var strengths: Vector2 = data.stage5_river_strengths_from_signal(fields.x, value)
			var stage5_height := int(data.finalize_height(data.stage5_shape_height_from_signal(fields.x, stage4_height, value)))
			var is_river := (not is_ocean) and strengths.x >= DATA.STAGE5_CHANNEL_WATER_CUTOFF
			var grid_index := gz * AUDIT_WIDTH + gx
			if is_ocean:
				ocean_grid[grid_index] = 1
				oceans += 1
			elif is_river:
				river_grid[grid_index] = 1
				rivers += 1
				var surface_y := stage5_height + 1
				surface_min = mini(surface_min, surface_y)
				surface_max = maxi(surface_max, surface_y)
				if not found_chunk and fields.x >= DATA.STAGE4_COAST_INLAND_END and surface_y > DATA.SEA_LEVEL + 1:
					chosen_chunk = Vector2i(floori(float(x) / float(CHUNK_SIZE)), floori(float(z) / float(CHUNK_SIZE)))
					found_chunk = true
				var carve := stage4_height - stage5_height
				max_carve = maxi(max_carve, carve)
				if provisional >= 48:
					mountain_rivers += 1
					mountain_carve_sum += carve
				if fields.x < DATA.STAGE4_COAST_INLAND_END:
					for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						if bool(stage4.is_ocean_column(x + offset.x, z + offset.y)):
							ocean_joins += 1
							break
			sampled += 1
			gx += 1
		gz += 1
	var components := _component_stats(river_grid, ocean_grid)
	if rivers < 128 or rivers >= int(sampled * 0.20):
		_fail("River coverage is outside acceptance range")
	if mountain_rivers < 8:
		_fail("Too few mountain river crossings")
	if mountain_rivers > 0 and float(mountain_carve_sum) / float(mountain_rivers) < 4.0:
		_fail("Mountain rivers do not create material valleys")
	if max_carve > DATA.STAGE5_MAX_VALLEY_CARVE + DATA.STAGE5_CHANNEL_DEPTH:
		_fail("River carve exceeded safety limit")
	if ocean_joins < 4:
		_fail("Too few river/ocean joins")
	if not found_chunk:
		_fail("No inland river chunk above sea level")
	if int(components["long_components"]) < 2:
		_fail("River field lacks long coherent corridors")
	if int(components["short_fragments"]) > 0:
		_fail("River field contains isolated one-chunk fragments")
	return {"sampled": sampled, "river_columns": rivers, "river_ratio": float(rivers) / float(sampled), "ocean_columns": oceans, "mountain_river_columns": mountain_rivers, "maximum_carve": max_carve, "river_ocean_joins": ocean_joins, "river_surface_min": surface_min, "river_surface_max": surface_max, "components": components, "river_chunk_x": chosen_chunk.x, "river_chunk_z": chosen_chunk.y}


func _component_stats(rivers: PackedByteArray, oceans: PackedByteArray) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(rivers.size())
	var component_count := 0
	var long_components := 0
	var short_fragments := 0
	var max_span := 0
	for start: int in range(rivers.size()):
		if rivers[start] == 0 or visited[start] != 0:
			continue
		component_count += 1
		var queue: Array[int] = [start]
		visited[start] = 1
		var cursor := 0
		var min_x := AUDIT_WIDTH
		var max_x := -1
		var min_z := AUDIT_WIDTH
		var max_z := -1
		var touches_edge := false
		var touches_ocean := false
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			var gx := cell % AUDIT_WIDTH
			var gz := int(cell / AUDIT_WIDTH)
			min_x = mini(min_x, gx)
			max_x = maxi(max_x, gx)
			min_z = mini(min_z, gz)
			max_z = maxi(max_z, gz)
			if gx == 0 or gz == 0 or gx == AUDIT_WIDTH - 1 or gz == AUDIT_WIDTH - 1:
				touches_edge = true
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var nx := gx + offset.x
				var nz := gz + offset.y
				if nx < 0 or nz < 0 or nx >= AUDIT_WIDTH or nz >= AUDIT_WIDTH:
					continue
				var neighbor := nz * AUDIT_WIDTH + nx
				if oceans[neighbor] != 0:
					touches_ocean = true
				if rivers[neighbor] != 0 and visited[neighbor] == 0:
					visited[neighbor] = 1
					queue.append(neighbor)
		var span := maxi(max_x - min_x + 1, max_z - min_z + 1) * AUDIT_STEP
		max_span = maxi(max_span, span)
		if span >= 96:
			long_components += 1
		if span <= CHUNK_SIZE and not touches_edge and not touches_ocean:
			short_fragments += 1
	return {"component_count": component_count, "long_components": long_components, "short_fragments": short_fragments, "maximum_span_blocks": max_span}


func _runtime_equivalence(runtime, data, river_chunk: Vector2i) -> Dictionary:
	var compared := 0
	var river_columns := 0
	var signal_checksum := 0.0
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-7, 5), river_chunk]
	for coord: Vector2i in coords:
		var first: Dictionary = runtime._build_column_caches(coord)
		var second: Dictionary = runtime._build_column_caches(coord)
		if first["heights"] != second["heights"] or first["world_fields"] != second["world_fields"] or first["biomes"] != second["biomes"]:
			_fail("Stage 5 cache is nondeterministic at %s" % coord)
		if first.has("river_signal"):
			_fail("Stage 5 shipping cache persists a diagnostic river array")
		var heights: PackedInt32Array = first["heights"]
		var origin_x := coord.x * CHUNK_SIZE
		var origin_z := coord.y * CHUNK_SIZE
		for lz: int in range(-PADDING, CHUNK_SIZE + PADDING):
			for lx: int in range(-PADDING, CHUNK_SIZE + PADDING):
				var index := (lz + PADDING) * CACHE_WIDTH + lx + PADDING
				var wx := origin_x + lx
				var wz := origin_z + lz
				if heights[index] != int(data.terrain_height(wx, wz)):
					_fail("Stage 5 cache/public height mismatch at (%d,%d)" % [wx, wz])
				var direct_signal := float(data.stage5_river_signal(wx, wz))
				if direct_signal != float(data.stage5_river_signal(wx, wz)):
					_fail("Stage 5 direct river field is nondeterministic at (%d,%d)" % [wx, wz])
				signal_checksum += direct_signal
				if bool(data.is_river_column(wx, wz)):
					river_columns += 1
				compared += 1
	if river_columns == 0:
		_fail("Runtime equivalence did not exercise river columns")
	return {"compared_columns": compared, "river_columns": river_columns, "direct_signal_checksum": signal_checksum}


func _renderer(data, river_chunk: Vector2i) -> Dictionary:
	var water_cells := 0
	var river_cells := 0
	var above_sea := 0
	for lz: int in range(CHUNK_SIZE):
		for lx: int in range(CHUNK_SIZE):
			var wx := river_chunk.x * CHUNK_SIZE + lx
			var wz := river_chunk.y * CHUNK_SIZE + lz
			var info: Vector2i = data.water_info_at(wx, wz)
			if info.x == DATA.WATER_NONE:
				continue
			water_cells += 1
			if info.x == DATA.WATER_RIVER:
				river_cells += 1
				if info.y > DATA.SEA_LEVEL:
					above_sea += 1
	var mesh: ArrayMesh = WATER.build_water_mesh(data, river_chunk, CHUNK_SIZE)
	if mesh == null or mesh.get_surface_count() != 1:
		_fail("Inland river chunk did not produce water mesh")
		return {}
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != water_cells * 4 or indices.size() != water_cells * 6:
		_fail("Water mesh does not match explicit water cells")
	var max_y := -999999.0
	for vertex: Vector3 in vertices:
		max_y = maxf(max_y, vertex.y)
	if river_cells == 0 or above_sea == 0 or max_y <= float(DATA.SEA_LEVEL) + 0.5:
		_fail("River water is still flattened onto ocean plane")
	return {"river_chunk": [river_chunk.x, river_chunk.y], "water_cells": water_cells, "river_cells": river_cells, "above_sea_cells": above_sea, "vertices": vertices.size(), "indices": indices.size(), "maximum_vertex_y": max_y}


func _benchmark(runtime) -> Dictionary:
	var coords: Array[Vector2i] = [Vector2i(-4,-2),Vector2i(-2,1),Vector2i(0,0),Vector2i(1,0),Vector2i(2,-1),Vector2i(4,2),Vector2i(8,-4),Vector2i(11,-3),Vector2i(12,-2),Vector2i(13,-2),Vector2i(14,-1),Vector2i(15,0),Vector2i(16,1),Vector2i(18,-4),Vector2i(20,2),Vector2i(-8,5)]
	for _warmup: int in range(4):
		for coord: Vector2i in coords:
			runtime._build_column_caches(coord)
	var times: Array[int] = []
	for repetition: int in range(20):
		for index: int in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			var started := Time.get_ticks_usec()
			runtime._build_column_caches(coord)
			times.append(maxi(1, Time.get_ticks_usec() - started))
	times.sort()
	var total := 0
	for value: int in times:
		total += value
	var p95_index := clampi(ceili(float(times.size()) * 0.95) - 1, 0, times.size() - 1)
	return {"sample_count": times.size(), "minimum_usec": times[0], "maximum_usec": times[times.size()-1], "mean_usec": float(total)/float(times.size()), "p95_usec": times[p95_index], "p95_ms": float(times[p95_index])/1000.0, "methodology": "16 padded chunks, 4 warmups, 20 repeats; generation/cache only"}


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
