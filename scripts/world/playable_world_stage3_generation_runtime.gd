extends "res://scripts/world/playable_world_stage2_generation_runtime.gd"

const STAGE3_DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const STAGE3_MESHER := preload("res://scripts/world/playable_world_mesher.gd")


func _init() -> void:
	data = STAGE3_DATA.new()


func _start_build_task(coord: Vector2i, revision: int, replacing: bool) -> void:
	var queue_start := Time.get_ticks_usec()
	var result_key := _result_key(coord, revision)
	var overrides_snapshot: Dictionary = data.overrides.duplicate(true)
	var task_callable := Callable(get_script(), "_stage3_worker_build_chunk").bind(
		coord,
		overrides_snapshot,
		revision,
		completed_worker_results,
		worker_result_mutex,
		result_key
	)
	var task_id := WorkerThreadPool.add_task(
		task_callable,
		false,
		"TEKNIK Stage 3 chunk %s r%d" % [coord, revision]
	)
	if task_id < 0:
		worker_submit_failures += 1
		_report_worker_failure(
			"WORKER_SUBMIT_FAILURE",
			coord,
			revision,
			task_id,
			"WorkerThreadPool.add_task returned an invalid task id"
		)
		_queue_latest_revision(coord, true)
		return
	active_build_tasks[coord] = {
		"task_id": task_id,
		"revision": revision,
		"result_key": result_key,
		"replacing": replacing,
		"queued_at_usec": Time.get_ticks_usec(),
		"stall_reported": false,
	}
	build_tasks_started += 1
	last_build_usec = maxi(last_build_usec, Time.get_ticks_usec() - queue_start)


static func _stage3_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var started_usec := Time.get_ticks_usec()
	var sampler = STAGE3_DATA.new()
	var cache_started_usec := Time.get_ticks_usec()
	var caches := _stage3_build_column_caches_for_sampler(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var mesh_height := _effective_mesh_height(coord, heights, overrides_snapshot)
	var mesh_started_usec := Time.get_ticks_usec()
	var mesh_data: Dictionary = STAGE3_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		CHUNK_SIZE,
		mesh_height,
		STAGE3_DATA.SEA_LEVEL,
		biomes
	)
	var mesh_usec := Time.get_ticks_usec() - mesh_started_usec
	var result := {
		"coord": coord,
		"revision": revision,
		"mesh_data": mesh_data,
		"cache_usec": cache_usec,
		"mesh_usec": mesh_usec,
		"mesh_height": mesh_height,
		"compute_usec": Time.get_ticks_usec() - started_usec,
	}
	result_mutex.lock()
	result_sink[result_key] = result
	result_mutex.unlock()


static func _stage3_smooth01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _stage3_build_column_caches_for_sampler(coord: Vector2i, sampler) -> Dictionary:
	var width := CHUNK_SIZE + MESH_CACHE_PADDING * 2
	var column_count := width * width
	var field_cache := PackedFloat32Array()
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	field_cache.resize(column_count * FIELD_STRIDE)
	heights.resize(column_count)
	biomes.resize(column_count)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	var min_world_x := origin_x - MESH_CACHE_PADDING
	var max_world_x := origin_x + CHUNK_SIZE + MESH_CACHE_PADDING - 1
	var min_world_z := origin_z - MESH_CACHE_PADDING
	var max_world_z := origin_z + CHUNK_SIZE + MESH_CACHE_PADDING - 1
	var spacing: int = sampler.STAGE3_FIELD_LATTICE_SPACING
	var reciprocal: float = sampler.STAGE3_FIELD_LATTICE_RECIPROCAL
	var node_min_x := floori(float(min_world_x) * reciprocal) * spacing
	var node_min_z := floori(float(min_world_z) * reciprocal) * spacing
	var node_max_x := (floori(float(max_world_x) * reciprocal) + 1) * spacing
	var node_max_z := (floori(float(max_world_z) * reciprocal) + 1) * spacing
	var node_width := int((node_max_x - node_min_x) / spacing) + 1
	var node_height := int((node_max_z - node_min_z) / spacing) + 1
	var structure_nodes := PackedFloat32Array()
	structure_nodes.resize(node_width * node_height)

	for node_z_index in range(node_height):
		var node_world_z := node_min_z + node_z_index * spacing
		for node_x_index in range(node_width):
			var node_world_x := node_min_x + node_x_index * spacing
			structure_nodes[node_z_index * node_width + node_x_index] = (
				sampler.stage3_sample_structure_node(node_world_x, node_world_z)
			)

	for local_z in range(-MESH_CACHE_PADDING, CHUNK_SIZE + MESH_CACHE_PADDING):
		for local_x in range(-MESH_CACHE_PADDING, CHUNK_SIZE + MESH_CACHE_PADDING):
			var column_index := (
				(local_z + MESH_CACHE_PADDING) * width
				+ local_x
				+ MESH_CACHE_PADDING
			)
			var field_index := column_index * FIELD_STRIDE
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var node_x_index := floori(float(world_x - node_min_x) * reciprocal)
			var node_z_index := floori(float(world_z - node_min_z) * reciprocal)
			var node_origin_x := node_min_x + node_x_index * spacing
			var node_origin_z := node_min_z + node_z_index * spacing
			var tx := _stage3_smooth01(float(world_x - node_origin_x) * reciprocal)
			var tz := _stage3_smooth01(float(world_z - node_origin_z) * reciprocal)
			var north_west := structure_nodes[node_z_index * node_width + node_x_index]
			var north_east := structure_nodes[node_z_index * node_width + node_x_index + 1]
			var south_west := structure_nodes[(node_z_index + 1) * node_width + node_x_index]
			var south_east := structure_nodes[(node_z_index + 1) * node_width + node_x_index + 1]
			var structure := lerpf(
				lerpf(north_west, north_east, tx),
				lerpf(south_west, south_east, tx),
				tz
			)
			var world_xf := float(world_x)
			var world_zf := float(world_z)
			var continentalness: float = sampler.continentalness_noise.get_noise_2d(world_xf, world_zf)
			var terrain_temperature: float = sampler.temperature_noise.get_noise_2d(world_xf, world_zf)
			var terrain_moisture: float = sampler.moisture_noise.get_noise_2d(world_xf, world_zf)
			var biome_temperature: float = sampler.biome_temperature_noise.get_noise_2d(world_xf, world_zf)
			var biome_moisture: float = sampler.biome_moisture_noise.get_noise_2d(world_xf, world_zf)
			var terrain_fields := Vector4(
				continentalness,
				structure,
				terrain_temperature,
				terrain_moisture
			)
			var biome_climate := Vector2(biome_temperature, biome_moisture)

			field_cache[field_index + FIELD_CONTINENTALNESS] = continentalness
			field_cache[field_index + FIELD_TERRAIN_STRUCTURE] = structure
			field_cache[field_index + FIELD_TERRAIN_TEMPERATURE] = terrain_temperature
			field_cache[field_index + FIELD_TERRAIN_MOISTURE] = terrain_moisture
			field_cache[field_index + FIELD_BIOME_TEMPERATURE] = biome_temperature
			field_cache[field_index + FIELD_BIOME_MOISTURE] = biome_moisture

			heights[column_index] = sampler.build_provisional_terrain(terrain_fields)
			biomes[column_index] = sampler.classify_biome(
				biome_climate,
				world_x,
				world_z
			)

	return _decorate_surface(field_cache, heights, biomes)


static func _stage2_build_column_caches_for_sampler(coord: Vector2i, sampler) -> Dictionary:
	return _stage3_build_column_caches_for_sampler(coord, sampler)


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return _stage3_build_column_caches_for_sampler(coord, data)
