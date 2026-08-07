extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage6_generation_data.gd")
const STAGE5 := preload("res://scripts/world/playable_world_stage5_generation_data.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const WATER := preload("res://scripts/world/localized_water_bodies.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + PADDING * 2
const GENERATION_P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20

var failures: Array[String] = []


func _init() -> void:
	var data = DATA.new()
	var stage5 = STAGE5.new()
	var runtime = RUNTIME.new()
	var contract := _validate_contract(data)
	var discovery := _discover_features(data)
	var audit := _audit_features(data, stage5, discovery)
	var equivalence := _validate_cache_equivalence(runtime, data, discovery)
	var renderer := _validate_renderer(data, discovery)
	var deterministic := _validate_determinism(data, runtime, discovery)
	var benchmark := _benchmark(runtime, discovery)
	if int(benchmark["p95_usec"]) >= GENERATION_P95_LIMIT_USEC:
		_fail(
			"Stage 6 generation exceeded the 1.0 ms p95 threshold: %d usec"
			% int(benchmark["p95_usec"])
		)
	runtime.free()

	var report := {
		"contract": contract,
		"discovery": {
			"lake_count": (discovery["lakes"] as Array).size(),
			"pond_count": (discovery["ponds"] as Array).size(),
		},
		"audit": audit,
		"equivalence": equivalence,
		"renderer": renderer,
		"determinism": deterministic,
		"benchmark": benchmark,
		"generation_p95_limit_usec": GENERATION_P95_LIMIT_USEC,
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE6_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE6_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _validate_contract(data) -> Dictionary:
	if DATA.WATER_LAKE in [DATA.WATER_NONE, DATA.WATER_OCEAN, DATA.WATER_RIVER]:
		_fail("Lake water type is not distinct")
	if DATA.WATER_POND in [DATA.WATER_NONE, DATA.WATER_OCEAN, DATA.WATER_RIVER, DATA.WATER_LAKE]:
		_fail("Pond water type is not distinct")
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 6 lost the 150-block legal world height")
	if DATA.STAGE6_LAKE_JITTER + DATA.STAGE6_LAKE_RADIUS_MAX >= float(DATA.STAGE6_LAKE_CELL_HALF):
		_fail("Lake feature can escape its deterministic feature cell")
	if DATA.STAGE6_POND_JITTER + DATA.STAGE6_POND_RADIUS_MAX >= float(DATA.STAGE6_POND_CELL_HALF):
		_fail("Pond feature can escape its deterministic feature cell")
	var dry_chance := data._stage6_moisture_chance(-1.0, DATA.STAGE6_LAKE_BASE_CHANCE, DATA.STAGE6_LAKE_MOISTURE_BONUS)
	var wet_chance := data._stage6_moisture_chance(1.0, DATA.STAGE6_LAKE_BASE_CHANCE, DATA.STAGE6_LAKE_MOISTURE_BONUS)
	if wet_chance <= dry_chance or wet_chance >= 1.0:
		_fail("Moisture does not increase lake probability correctly")
	if int(data.water_type_at(6, 6)) != DATA.WATER_NONE:
		_fail("Stage 6 moved the default spawn into generated water")
	var data_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage6_generation_data.gd"
	)
	var cache_source := FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage6_cache_fast.gd"
	)
	if data_source.contains("FastNoiseLite.new") or cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 6 added a new FastNoiseLite stack")
	for required: String in [
		"stage6_lake_candidate",
		"stage6_pond_candidate",
		"stage6_shape_height_for_feature",
		"STAGE6_LAKE_HARD_RIM_RADIUS",
	]:
		if not data_source.contains(required):
			_fail("Stage 6 data source is missing %s" % required)
	if not cache_source.contains("STAGE5_CACHE.build"):
		_fail("Stage 6 cache no longer layers sparsely on the accepted Stage 5 cache")
	return {
		"lake_probability_dry": dry_chance,
		"lake_probability_wet": wet_chance,
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
	}


func _discover_features(data) -> Dictionary:
	var lakes: Array[Dictionary] = []
	var ponds: Array[Dictionary] = []
	for cell_z in range(-9, 10):
		for cell_x in range(-9, 10):
			var lake: Dictionary = data.stage6_lake_candidate(cell_x, cell_z)
			if not lake.is_empty():
				lakes.append(lake)
	for cell_z in range(-18, 19):
		for cell_x in range(-18, 19):
			var pond: Dictionary = data.stage6_pond_candidate(cell_x, cell_z)
			if not pond.is_empty():
				ponds.append(pond)
	if lakes.size() < 4:
		_fail("Stage 6 fixed-seed search produced too few lakes: %d" % lakes.size())
	if ponds.size() < 8:
		_fail("Stage 6 fixed-seed search produced too few ponds: %d" % ponds.size())
	return {"lakes": lakes, "ponds": ponds}


func _audit_features(data, stage5, discovery: Dictionary) -> Dictionary:
	var lakes: Array = discovery["lakes"]
	var ponds: Array = discovery["ponds"]
	var lake_cells := 0
	var pond_cells := 0
	var containment_edges := 0
	var stage5_overlap_failures := 0
	var above_sea_features := 0
	var cross_chunk_lakes := 0
	var cross_chunk_ponds := 0
	var maximum_lake_cells := 0
	var maximum_pond_cells := 0
	var minimum_lake_cells := 1 << 30
	var minimum_pond_cells := 1 << 30

	for index in range(mini(6, lakes.size())):
		var stats := _audit_one_feature(data, stage5, lakes[index])
		var wet_cells := int(stats["wet_cells"])
		lake_cells += wet_cells
		minimum_lake_cells = mini(minimum_lake_cells, wet_cells)
		maximum_lake_cells = maxi(maximum_lake_cells, wet_cells)
		containment_edges += int(stats["containment_edges"])
		stage5_overlap_failures += int(stats["stage5_overlaps"])
		if int(stats["water_level"]) > DATA.SEA_LEVEL:
			above_sea_features += 1
		if bool(stats["crosses_chunk"]):
			cross_chunk_lakes += 1

	for index in range(mini(10, ponds.size())):
		var stats := _audit_one_feature(data, stage5, ponds[index])
		var wet_cells := int(stats["wet_cells"])
		pond_cells += wet_cells
		minimum_pond_cells = mini(minimum_pond_cells, wet_cells)
		maximum_pond_cells = maxi(maximum_pond_cells, wet_cells)
		containment_edges += int(stats["containment_edges"])
		stage5_overlap_failures += int(stats["stage5_overlaps"])
		if int(stats["water_level"]) > DATA.SEA_LEVEL:
			above_sea_features += 1
		if bool(stats["crosses_chunk"]):
			cross_chunk_ponds += 1

	if minimum_lake_cells < 80:
		_fail("A generated lake is too small/noisy: %d wet cells" % minimum_lake_cells)
	if minimum_pond_cells < 8:
		_fail("A generated pond collapsed into single-block noise: %d wet cells" % minimum_pond_cells)
	if maximum_pond_cells >= minimum_lake_cells:
		_fail("Ponds are not meaningfully smaller than lakes")
	if containment_edges < 40:
		_fail("Stage 6 enclosure audit exercised too few water/rim edges")
	if stage5_overlap_failures > 0:
		_fail("Lake/pond water overlaps Stage 5 river/ocean topology")
	if cross_chunk_lakes == 0 or cross_chunk_ponds == 0:
		_fail("Fixed-seed basin set did not exercise both lake and pond chunk crossings")
	if above_sea_features < 4:
		_fail("Stage 6 local water levels are not clearly independent of ocean sea level")
	return {
		"audited_lake_cells": lake_cells,
		"audited_pond_cells": pond_cells,
		"minimum_lake_cells": minimum_lake_cells,
		"maximum_lake_cells": maximum_lake_cells,
		"minimum_pond_cells": minimum_pond_cells,
		"maximum_pond_cells": maximum_pond_cells,
		"containment_edges": containment_edges,
		"stage5_overlap_failures": stage5_overlap_failures,
		"above_sea_features": above_sea_features,
		"cross_chunk_lakes": cross_chunk_lakes,
		"cross_chunk_ponds": cross_chunk_ponds,
	}


func _audit_one_feature(data, stage5, feature: Dictionary) -> Dictionary:
	var center_x := int(feature["center_x"])
	var center_z := int(feature["center_z"])
	var radius_x := float(feature["radius_x"])
	var radius_z := float(feature["radius_z"])
	var water_radius := float(feature["water_radius"])
	var water_radius_squared := water_radius * water_radius
	var water_type := int(feature["type"])
	var water_level := int(feature["water_level"])
	var min_x := floori(float(center_x) - radius_x * water_radius) - 1
	var max_x := ceili(float(center_x) + radius_x * water_radius) + 1
	var min_z := floori(float(center_z) - radius_z * water_radius) - 1
	var max_z := ceili(float(center_z) + radius_z * water_radius) + 1
	var wet_cells := 0
	var containment_edges := 0
	var stage5_overlaps := 0
	var crosses_chunk := false
	var first_chunk := Vector2i(2147483647, 2147483647)
	for z in range(min_z, max_z + 1):
		for x in range(min_x, max_x + 1):
			var distance_squared: float = data.stage6_feature_distance_squared(x, z, feature)
			if distance_squared > water_radius_squared:
				continue
			var info: Vector2i = data.water_info_at(x, z)
			if info.x != water_type or info.y != water_level:
				_fail("Stage 6 wet footprint disagrees with water_info_at at (%d,%d)" % [x, z])
				continue
			wet_cells += 1
			if data.terrain_height(x, z) >= water_level:
				_fail("Stage 6 water is not above its basin floor at (%d,%d)" % [x, z])
			if int(stage5.water_type_at(x, z)) != DATA.WATER_NONE:
				stage5_overlaps += 1
			if data.is_tree_origin(x, z):
				_fail("Tree origin generated inside Stage 6 water at (%d,%d)" % [x, z])
			var chunk := Vector2i(
				floori(float(x) / float(CHUNK_SIZE)),
				floori(float(z) / float(CHUNK_SIZE))
			)
			if first_chunk.x == 2147483647:
				first_chunk = chunk
			elif chunk != first_chunk:
				crosses_chunk = true
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor_x := x + offset.x
				var neighbor_z := z + offset.y
				var neighbor_distance: float = data.stage6_feature_distance_squared(
					neighbor_x,
					neighbor_z,
					feature
				)
				if neighbor_distance <= water_radius_squared:
					continue
				containment_edges += 1
				var neighbor_info: Vector2i = data.water_info_at(neighbor_x, neighbor_z)
				if neighbor_info.x != DATA.WATER_NONE:
					_fail("Stage 6 basin boundary touches unrelated generated water")
				if data.terrain_height(neighbor_x, neighbor_z) < water_level:
					_fail(
						"Stage 6 basin is not enclosed at (%d,%d) level %d"
						% [neighbor_x, neighbor_z, water_level]
					)
	return {
		"wet_cells": wet_cells,
		"containment_edges": containment_edges,
		"stage5_overlaps": stage5_overlaps,
		"water_level": water_level,
		"crosses_chunk": crosses_chunk,
	}


func _validate_cache_equivalence(runtime, data, discovery: Dictionary) -> Dictionary:
	var coords: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(3, -2),
		Vector2i(-7, 5),
	]
	for key: String in ["lakes", "ponds"]:
		var features: Array = discovery[key]
		for index in range(mini(2, features.size())):
			var feature: Dictionary = features[index]
			var center_chunk := Vector2i(
				floori(float(int(feature["center_x"])) / float(CHUNK_SIZE)),
				floori(float(int(feature["center_z"])) / float(CHUNK_SIZE))
			)
			if not coords.has(center_chunk):
				coords.append(center_chunk)
	var compared_columns := 0
	var changed_from_stage5 := 0
	for coord: Vector2i in coords:
		var cache: Dictionary = runtime._build_column_caches(coord)
		var heights: PackedInt32Array = cache["heights"]
		var origin_x := coord.x * CHUNK_SIZE
		var origin_z := coord.y * CHUNK_SIZE
		for local_z in range(-PADDING, CHUNK_SIZE + PADDING):
			for local_x in range(-PADDING, CHUNK_SIZE + PADDING):
				var index := (local_z + PADDING) * CACHE_WIDTH + local_x + PADDING
				var world_x := origin_x + local_x
				var world_z := origin_z + local_z
				var expected := int(data.terrain_height(world_x, world_z))
				if heights[index] != expected:
					_fail("Stage 6 cache/public height mismatch at (%d,%d)" % [world_x, world_z])
				if expected != int(data.stage6_stage5_height_at(world_x, world_z)):
					changed_from_stage5 += 1
				compared_columns += 1
	if changed_from_stage5 == 0:
		_fail("Stage 6 equivalence set did not exercise any basin-shaped columns")
	return {
		"compared_columns": compared_columns,
		"changed_from_stage5": changed_from_stage5,
		"chunk_count": coords.size(),
	}


func _validate_renderer(data, discovery: Dictionary) -> Dictionary:
	var verified_features := 0
	var maximum_surface_y := -999999.0
	for key: String in ["lakes", "ponds"]:
		var features: Array = discovery[key]
		if features.is_empty():
			continue
		var feature: Dictionary = features[0]
		var coord := Vector2i(
			floori(float(int(feature["center_x"])) / float(CHUNK_SIZE)),
			floori(float(int(feature["center_z"])) / float(CHUNK_SIZE))
		)
		var mesh: ArrayMesh = WATER.build_water_mesh(data, coord, CHUNK_SIZE)
		if mesh == null:
			_fail("Stage 6 feature chunk produced no localized water mesh")
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var expected_y := float(int(feature["water_level"])) + WATER.WATER_SURFACE_OFFSET
		var found_level := false
		for vertex: Vector3 in vertices:
			maximum_surface_y = maxf(maximum_surface_y, vertex.y)
			if is_equal_approx(vertex.y, expected_y):
				found_level = true
		if not found_level:
			_fail("Localized water renderer did not use the Stage 6 local water level")
		verified_features += 1
	if verified_features < 2:
		_fail("Renderer gate did not exercise both a lake and a pond")
	if maximum_surface_y <= float(DATA.SEA_LEVEL) + WATER.WATER_SURFACE_OFFSET:
		_fail("Stage 6 water rendering is flattened to global sea level")
	return {
		"verified_features": verified_features,
		"maximum_surface_y": maximum_surface_y,
	}


func _validate_determinism(data, runtime, discovery: Dictionary) -> Dictionary:
	var candidate_checks := 0
	for cell: Vector2i in [Vector2i.ZERO, Vector2i(2, -3), Vector2i(-4, 5), Vector2i(7, 1)]:
		if data.stage6_lake_candidate(cell.x, cell.y) != data.stage6_lake_candidate(cell.x, cell.y):
			_fail("Stage 6 lake candidate is nondeterministic at %s" % cell)
		if data.stage6_pond_candidate(cell.x, cell.y) != data.stage6_pond_candidate(cell.x, cell.y):
			_fail("Stage 6 pond candidate is nondeterministic at %s" % cell)
		candidate_checks += 2
	var chunk_checks := 0
	var coords: Array[Vector2i] = [Vector2i.ZERO, Vector2i(3, -2)]
	var lakes: Array = discovery["lakes"]
	if not lakes.is_empty():
		var lake: Dictionary = lakes[0]
		coords.append(Vector2i(
			floori(float(int(lake["center_x"])) / float(CHUNK_SIZE)),
			floori(float(int(lake["center_z"])) / float(CHUNK_SIZE))
		))
	for coord: Vector2i in coords:
		var first: Dictionary = runtime._build_column_caches(coord)
		var second: Dictionary = runtime._build_column_caches(coord)
		if first["heights"] != second["heights"]:
			_fail("Stage 6 chunk cache is nondeterministic at %s" % coord)
		chunk_checks += 1
	return {"candidate_checks": candidate_checks, "chunk_checks": chunk_checks}


func _benchmark(runtime, discovery: Dictionary) -> Dictionary:
	var coords: Array[Vector2i] = [
		Vector2i(-4, -2), Vector2i(-2, 1), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(2, -1), Vector2i(4, 2), Vector2i(8, -4), Vector2i(11, -3),
		Vector2i(12, -2), Vector2i(13, -2), Vector2i(14, -1), Vector2i(15, 0),
	]
	for key: String in ["lakes", "ponds"]:
		var features: Array = discovery[key]
		for index in range(mini(2, features.size())):
			var feature: Dictionary = features[index]
			var coord := Vector2i(
				floori(float(int(feature["center_x"])) / float(CHUNK_SIZE)),
				floori(float(int(feature["center_z"])) / float(CHUNK_SIZE))
			)
			if not coords.has(coord):
				coords.append(coord)
	while coords.size() < 16:
		coords.append(Vector2i(18 + coords.size(), -4))
	if coords.size() > 16:
		coords.resize(16)
	for _warmup in range(WARMUPS):
		for coord: Vector2i in coords:
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
	for measurement: int in times:
		total += measurement
	var p95_index := clampi(ceili(float(times.size()) * 0.95) - 1, 0, times.size() - 1)
	return {
		"sample_count": times.size(),
		"mean_usec": float(total) / float(times.size()),
		"minimum_usec": times[0],
		"maximum_usec": times[-1],
		"p95_usec": times[p95_index],
		"p95_ms": float(times[p95_index]) / 1000.0,
		"methodology": "16 padded chunks including lake/pond chunks, 4 warmups, 20 repeats; generation/cache only",
	}


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
