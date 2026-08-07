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
	# Broad terrain structure uses a 4-block lattice. Terrain-only climate is
	# slower-changing and uses an 8-block lattice. Both node sets are shared by
	# every padded column; biome climate remains full-resolution so this Stage 3
	# optimization does not alter accepted biome identity or transitions.
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

	var structure_spacing: int = sampler.STAGE3_FIELD_LATTICE_SPACING
	var structure_reciprocal: float = sampler.STAGE3_FIELD_LATTICE_RECIPROCAL
	var structure_min_x := floori(float(min_world_x) * structure_reciprocal) * structure_spacing
	var structure_min_z := floori(float(min_world_z) * structure_reciprocal) * structure_spacing
	var structure_max_x := (
		floori(float(max_world_x) * structure_reciprocal) + 1
	) * structure_spacing
	var structure_max_z := (
		floori(float(max_world_z) * structure_reciprocal) + 1
	) * structure_spacing
	var structure_width := int((structure_max_x - structure_min_x) / structure_spacing) + 1
	var structure_height := int((structure_max_z - structure_min_z) / structure_spacing) + 1
	var structure_nodes := PackedFloat32Array()
	structure_nodes.resize(structure_width * structure_height)
	for node_z_index in range(structure_height):
		var node_world_z := structure_min_z + node_z_index * structure_spacing
		for node_x_index in range(structure_width):
			var node_world_x := structure_min_x + node_x_index * structure_spacing
			structure_nodes[node_z_index * structure_width + node_x_index] = (
				sampler.stage3_sample_structure_node(node_world_x, node_world_z)
			)

	var climate_spacing: int = sampler.STAGE3_TERRAIN_CLIMATE_LATTICE_SPACING
	var climate_reciprocal: float = sampler.STAGE3_TERRAIN_CLIMATE_LATTICE_RECIPROCAL
	var climate_min_x := floori(float(min_world_x) * climate_reciprocal) * climate_spacing
	var climate_min_z := floori(float(min_world_z) * climate_reciprocal) * climate_spacing
	var climate_max_x := (
		floori(float(max_world_x) * climate_reciprocal) + 1
	) * climate_spacing
	var climate_max_z := (
		floori(float(max_world_z) * climate_reciprocal) + 1
	) * climate_spacing
	var climate_width := int((climate_max_x - climate_min_x) / climate_spacing) + 1
	var climate_height := int((climate_max_z - climate_min_z) / climate_spacing) + 1
	var temperature_nodes := PackedFloat32Array()
	var moisture_nodes := PackedFloat32Array()
	temperature_nodes.resize(climate_width * climate_height)
	moisture_nodes.resize(climate_width * climate_height)
	for node_z_index in range(climate_height):
		var node_world_z := climate_min_z + node_z_index * climate_spacing
		for node_x_index in range(climate_width):
			var node_world_x := climate_min_x + node_x_index * climate_spacing
			var climate: Vector2 = sampler.stage3_sample_terrain_climate_node(
				node_world_x,
				node_world_z
			)
			var node_index := node_z_index * climate_width + node_x_index
			temperature_nodes[node_index] = climate.x
			moisture_nodes[node_index] = climate.y

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

			var structure_x_index := floori(
				float(world_x - structure_min_x) * structure_reciprocal
			)
			var structure_z_index := floori(
				float(world_z - structure_min_z) * structure_reciprocal
			)
			var structure_origin_x := structure_min_x + structure_x_index * structure_spacing
			var structure_origin_z := structure_min_z + structure_z_index * structure_spacing
			var structure_tx := _stage3_smooth01(
				float(world_x - structure_origin_x) * structure_reciprocal
			)
			var structure_tz := _stage3_smooth01(
				float(world_z - structure_origin_z) * structure_reciprocal
			)
			var structure_nw := structure_nodes[
				structure_z_index * structure_width + structure_x_index
			]
			var structure_ne := structure_nodes[
				structure_z_index * structure_width + structure_x_index + 1
			]
			var structure_sw := structure_nodes[
				(structure_z_index + 1) * structure_width + structure_x_index
			]
			var structure_se := structure_nodes[
				(structure_z_index + 1) * structure_width + structure_x_index + 1
			]
			var structure := lerpf(
				lerpf(structure_nw, structure_ne, structure_tx),
				lerpf(structure_sw, structure_se, structure_tx),
				structure_tz
			)

			var climate_x_index := floori(float(world_x - climate_min_x) * climate_reciprocal)
			var climate_z_index := floori(float(world_z - climate_min_z) * climate_reciprocal)
			var climate_origin_x := climate_min_x + climate_x_index * climate_spacing
			var climate_origin_z := climate_min_z + climate_z_index * climate_spacing
			var climate_tx := _stage3_smooth01(
				float(world_x - climate_origin_x) * climate_reciprocal
			)
			var climate_tz := _stage3_smooth01(
				float(world_z - climate_origin_z) * climate_reciprocal
			)
			var climate_nw := climate_z_index * climate_width + climate_x_index
			var climate_ne := climate_nw + 1
			var climate_sw := (climate_z_index + 1) * climate_width + climate_x_index
			var climate_se := climate_sw + 1
			var terrain_temperature := lerpf(
				lerpf(temperature_nodes[climate_nw], temperature_nodes[climate_ne], climate_tx),
				lerpf(temperature_nodes[climate_sw], temperature_nodes[climate_se], climate_tx),
				climate_tz
			)
			var terrain_moisture := lerpf(
				lerpf(moisture_nodes[climate_nw], moisture_nodes[climate_ne], climate_tx),
				lerpf(moisture_nodes[climate_sw], moisture_nodes[climate_se], climate_tx),
				climate_tz
			)

			var world_xf := float(world_x)
			var world_zf := float(world_z)
			var continentalness: float = sampler.continentalness_noise.get_noise_2d(world_xf, world_zf)
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
