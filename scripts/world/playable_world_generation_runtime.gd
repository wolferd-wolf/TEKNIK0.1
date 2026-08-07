extends "res://scripts/world/playable_world_runtime.gd"

const PIPELINE_DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const PIPELINE_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

# Compact per-column field-cache layout. One packed buffer avoids allocating a
# Dictionary or RefCounted object for each of the padded chunk's 256 columns.
const FIELD_CONTINENTALNESS := 0
const FIELD_TERRAIN_STRUCTURE := 1
const FIELD_TERRAIN_TEMPERATURE := 2
const FIELD_TERRAIN_MOISTURE := 3
const FIELD_BIOME_TEMPERATURE := 4
const FIELD_BIOME_MOISTURE := 5
const FIELD_STRIDE := 6


func _init() -> void:
	# Replace only the generation-data facade. It inherits the accepted seed,
	# save format, noise configuration, terrain formula and biome rules, while
	# exposing the overhaul's 150-block legal vertical range.
	data = PIPELINE_DATA.new()


func _start_build_task(coord: Vector2i, revision: int, replacing: bool) -> void:
	# The stable streaming/runtime machinery is inherited unchanged. Only the
	# worker target changes so chunk generation passes through the Stage 1
	# pipeline before the existing mesher runs.
	var queue_start := Time.get_ticks_usec()
	var result_key := _result_key(coord, revision)
	var overrides_snapshot: Dictionary = data.overrides.duplicate(true)
	var task_callable := Callable(get_script(), "_stage1_worker_build_chunk").bind(
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
		"TEKNIK Stage 1 chunk %s r%d" % [coord, revision]
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


static func _stage1_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var started_usec := Time.get_ticks_usec()
	# Worker-local data remains mandatory: FastNoiseLite instances and save data
	# are never shared between concurrent workers.
	var sampler = PIPELINE_DATA.new()
	var cache_started_usec := Time.get_ticks_usec()
	var caches := _stage1_build_column_caches_for_sampler(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var mesh_height := _effective_mesh_height(coord, heights, overrides_snapshot)
	var mesh_started_usec := Time.get_ticks_usec()
	var mesh_data: Dictionary = PIPELINE_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		CHUNK_SIZE,
		mesh_height,
		PIPELINE_DATA.SEA_LEVEL,
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


static func _effective_mesh_height(
	coord: Vector2i,
	heights: PackedInt32Array,
	overrides_snapshot: Dictionary
) -> int:
	# The legal world is 150 blocks high, but generated/edited content normally
	# occupies only a fraction of that range. Meshing to the actual content top
	# prevents a permanent 2.5x vertical scan cost from the height-limit change.
	var highest_content_y := 0
	for height in heights:
		highest_content_y = maxi(
			highest_content_y,
			int(height) + PIPELINE_DATA.TREE_TRUNK_HEIGHT + 1
		)

	var min_x := coord.x * CHUNK_SIZE - MESH_CACHE_PADDING
	var max_x := coord.x * CHUNK_SIZE + CHUNK_SIZE + MESH_CACHE_PADDING - 1
	var min_z := coord.y * CHUNK_SIZE - MESH_CACHE_PADDING
	var max_z := coord.y * CHUNK_SIZE + CHUNK_SIZE + MESH_CACHE_PADDING - 1
	for key_value: Variant in overrides_snapshot.keys():
		if int(overrides_snapshot.get(key_value, PIPELINE_DATA.BLOCK_AIR)) == PIPELINE_DATA.BLOCK_AIR:
			continue
		var parts := String(key_value).split(",")
		if parts.size() != 3:
			continue
		var x := int(parts[0])
		var y := int(parts[1])
		var z := int(parts[2])
		if x < min_x or x > max_x or z < min_z or z > max_z:
			continue
		highest_content_y = maxi(highest_content_y, y)

	# WORLD_MESHER.build() takes an exclusive upper bound. +1 preserves a solid
	# override at y=149, while the clamp keeps the physical ceiling at 150.
	return clampi(highest_content_y + 1, 1, PIPELINE_DATA.OVERHAUL_WORLD_HEIGHT)


static func _stage1_build_column_caches_for_sampler(coord: Vector2i, sampler) -> Dictionary:
	# The first implementation kept sampling, height and biome classification as
	# three separate 256-column passes. That proved correct but measured 1.046 ms
	# p95. Stage boundaries remain explicit in the data facade; the shipping hot
	# path fuses their per-column work so the field cache costs only writes, not
	# repeated iteration and Vector reconstruction.
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
			var terrain_fields: Vector4 = sampler.sample_world_fields(world_x, world_z)
			var biome_climate: Vector2 = sampler.sample_biome_climate(world_x, world_z)

			field_cache[field_index + FIELD_CONTINENTALNESS] = terrain_fields.x
			field_cache[field_index + FIELD_TERRAIN_STRUCTURE] = terrain_fields.y
			field_cache[field_index + FIELD_TERRAIN_TEMPERATURE] = terrain_fields.z
			field_cache[field_index + FIELD_TERRAIN_MOISTURE] = terrain_fields.w
			field_cache[field_index + FIELD_BIOME_TEMPERATURE] = biome_climate.x
			field_cache[field_index + FIELD_BIOME_MOISTURE] = biome_climate.y

			# apply_water_topology() and finalize_height() are intentional Stage 1
			# identity boundaries. The accepted terrain formula is called directly
			# here to avoid one interpreted wrapper call per padded column.
			heights[column_index] = sampler.terrain_height_from_samples(terrain_fields)
			biomes[column_index] = sampler.classify_biome(
				biome_climate,
				world_x,
				world_z
			)

	return _decorate_surface(field_cache, heights, biomes)


# Reference stage helpers remain callable for diagnostics and later stages.
# Shipping Stage 1 uses the fused loop above after CI showed the split-pass
# version exceeded the fixed 1.0 ms p95 gate by 46 microseconds.
static func _sample_world_fields(coord: Vector2i, sampler) -> PackedFloat32Array:
	var width := CHUNK_SIZE + MESH_CACHE_PADDING * 2
	var field_cache := PackedFloat32Array()
	field_cache.resize(width * width * FIELD_STRIDE)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
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
			var terrain_fields: Vector4 = sampler.sample_world_fields(world_x, world_z)
			var biome_climate: Vector2 = sampler.sample_biome_climate(world_x, world_z)
			field_cache[field_index + FIELD_CONTINENTALNESS] = terrain_fields.x
			field_cache[field_index + FIELD_TERRAIN_STRUCTURE] = terrain_fields.y
			field_cache[field_index + FIELD_TERRAIN_TEMPERATURE] = terrain_fields.z
			field_cache[field_index + FIELD_TERRAIN_MOISTURE] = terrain_fields.w
			field_cache[field_index + FIELD_BIOME_TEMPERATURE] = biome_climate.x
			field_cache[field_index + FIELD_BIOME_MOISTURE] = biome_climate.y
	return field_cache


static func _build_provisional_terrain(
	field_cache: PackedFloat32Array,
	sampler
) -> PackedInt32Array:
	var column_count := int(field_cache.size() / FIELD_STRIDE)
	var provisional_heights := PackedInt32Array()
	provisional_heights.resize(column_count)
	for column_index in range(column_count):
		var field_index := column_index * FIELD_STRIDE
		var fields := Vector4(
			field_cache[field_index + FIELD_CONTINENTALNESS],
			field_cache[field_index + FIELD_TERRAIN_STRUCTURE],
			field_cache[field_index + FIELD_TERRAIN_TEMPERATURE],
			field_cache[field_index + FIELD_TERRAIN_MOISTURE]
		)
		provisional_heights[column_index] = sampler.build_provisional_terrain(fields)
	return provisional_heights


static func _apply_water_topology(
	_field_cache: PackedFloat32Array,
	provisional_heights: PackedInt32Array,
	_coord: Vector2i,
	_sampler
) -> PackedInt32Array:
	# Stage 1 boundary only. The accepted world has no terrain-integrated water
	# topology yet, so changing a height here would be a regression.
	return provisional_heights


static func _finalize_height(
	water_shaped_heights: PackedInt32Array,
	_coord: Vector2i,
	_sampler
) -> PackedInt32Array:
	# Stage 1 has no post-water height transform. Keeping this as a named stage
	# gives Stage 2-6 a stable insertion point without touching streaming code.
	return water_shaped_heights


static func _classify_biomes(
	field_cache: PackedFloat32Array,
	coord: Vector2i,
	sampler
) -> PackedByteArray:
	var width := CHUNK_SIZE + MESH_CACHE_PADDING * 2
	var column_count := int(field_cache.size() / FIELD_STRIDE)
	var biomes := PackedByteArray()
	biomes.resize(column_count)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for column_index in range(column_count):
		var cache_x := column_index % width
		var cache_z := int(column_index / width)
		var world_x := origin_x + cache_x - MESH_CACHE_PADDING
		var world_z := origin_z + cache_z - MESH_CACHE_PADDING
		var field_index := column_index * FIELD_STRIDE
		var climate := Vector2(
			field_cache[field_index + FIELD_BIOME_TEMPERATURE],
			field_cache[field_index + FIELD_BIOME_MOISTURE]
		)
		biomes[column_index] = sampler.classify_biome(climate, world_x, world_z)
	return biomes


static func _decorate_surface(
	field_cache: PackedFloat32Array,
	heights: PackedInt32Array,
	biomes: PackedByteArray
) -> Dictionary:
	# Bulk block material/tree decoration intentionally remains in the proven
	# mesher for Stage 1. This stage publishes the immutable column context the
	# mesher consumes; no visual rule is moved or changed yet.
	return {
		"world_fields": field_cache,
		"heights": heights,
		"biomes": biomes,
	}


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return _stage1_build_column_caches_for_sampler(coord, data)
