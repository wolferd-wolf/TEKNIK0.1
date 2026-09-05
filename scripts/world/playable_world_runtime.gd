extends Node3D

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const MECHANICAL_DATA := preload("res://scripts/world/mechanical_block_data.gd")

const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const COLLISION_RADIUS := 1
const UNLOAD_RADIUS := 4
const BUILD_BUDGET_USEC := 5500
const EDIT_DEBOUNCE_MSEC := 75
const MESH_CACHE_PADDING := 2
const MAX_ACTIVE_BUILD_TASKS := 2
const MAX_BUILD_APPLIES_PER_FRAME := 1
const WORKER_STALL_DIAGNOSTIC_USEC := 5000000

var target: Node3D
var target_physics_enabled := false
var spawn_prepared := false
var override_spawn_position: Variant = null
var center := Vector2i(2147483647, 2147483647)
var data = WORLD_DATA.new()
var mechanical_data := MECHANICAL_DATA.new()
var mechanical_dirty := false
var mechanical_save_delay := 0.0
const MECHANICAL_SAVE_DELAY_SEC := 1.5
var material := StandardMaterial3D.new()
var water: MeshInstance3D

var loaded: Dictionary = {}
var build_queue: Array[Vector2i] = []
var build_queued: Dictionary = {}
var collision_add_queue: Array[Vector2i] = []
var collision_add_queued: Dictionary = {}
var collision_remove_queue: Array[Vector2i] = []
var collision_remove_queued: Dictionary = {}
var pending_rebuilds: Dictionary = {}
var rebuild_deadlines: Dictionary = {}

var build_revisions: Dictionary = {}
var active_build_tasks: Dictionary = {}
var build_apply_queue: Array[Dictionary] = []
var completed_worker_results: Dictionary = {}
var worker_result_mutex := Mutex.new()

var last_build_usec := 0
var last_apply_usec := 0
var last_collision_usec := 0
var last_face_count := 0
var atomic_swaps := 0
var atomic_failures := 0
var coalesced_edits := 0
var build_tasks_started := 0
var build_results_applied := 0
var stale_results_discarded := 0
var worker_submit_failures := 0
var worker_wait_failures := 0
var worker_missing_results := 0
var worker_stall_warnings := 0
var max_background_compute_usec := 0
var max_pump_usec := 0


func configure(streaming_target: Node3D) -> void:
	target = streaming_target
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_create_water()
	load_mechanical_blocks()
	if is_instance_valid(target):
		target_physics_enabled = target.is_physics_processing()
		target.set_physics_process(false)
		set_center(world_to_chunk(target.global_position))
	else:
		set_center(Vector2i.ZERO)


func tick(delta: float) -> void:
	_promote_rebuilds()
	if is_instance_valid(target):
		var next_center := world_to_chunk(target.global_position)
		if next_center != center:
			set_center(next_center)
		if is_instance_valid(water):
			water.position.x = target.global_position.x
			water.position.z = target.global_position.z
	_pump_builds()
	_refresh_collisions()
	_pump_collisions()
	_prepare_spawn()
	data.tick_save(delta)
	_tick_mechanical_save(delta)


func shutdown() -> void:
	for task_value: Variant in active_build_tasks.values():
		var task_data: Dictionary = task_value
		var task_id := int(task_data.get("task_id", -1))
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
	active_build_tasks.clear()
	build_apply_queue.clear()
	worker_result_mutex.lock()
	completed_worker_results.clear()
	worker_result_mutex.unlock()
	if data.dirty:
		data.save_world()
	if mechanical_dirty:
		save_mechanical_blocks()


func world_to_chunk(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / float(CHUNK_SIZE)),
		floori(position.z / float(CHUNK_SIZE))
	)


func cell_to_chunk(cell: Vector3i) -> Vector2i:
	return Vector2i(
		floori(cell.x / float(CHUNK_SIZE)),
		floori(cell.z / float(CHUNK_SIZE))
	)


func set_center(next_center: Vector2i) -> void:
	center = next_center
	_prune_queue()
	_invalidate_outside_active_builds()
	for z in range(center.y - RENDER_RADIUS, center.y + RENDER_RADIUS + 1):
		for x in range(center.x - RENDER_RADIUS, center.x + RENDER_RADIUS + 1):
			var coord := Vector2i(x, z)
			if (
				not loaded.has(coord)
				and not build_queued.has(coord)
				and not active_build_tasks.has(coord)
			):
				_queue_initial_build(coord)
	_sort_queue()
	_unload_far_chunks()


func get_chunk_root(coord: Vector2i) -> Node3D:
	var entry: Dictionary = loaded.get(coord, {})
	return entry.get("root") as Node3D


func get_chunk_entry(coord: Vector2i) -> Dictionary:
	return loaded.get(coord, {})


func clear_world() -> void:
	for coord_value: Variant in active_build_tasks.keys():
		var coord: Vector2i = coord_value
		build_revisions[coord] = int(build_revisions.get(coord, 0)) + 1
	for entry_value: Variant in loaded.values():
		var entry: Dictionary = entry_value
		var root_node := entry.get("root") as Node3D
		if is_instance_valid(root_node):
			root_node.queue_free()
	loaded.clear()
	build_queue.clear()
	build_queued.clear()
	build_apply_queue.clear()
	collision_add_queue.clear()
	collision_remove_queue.clear()
	collision_add_queued.clear()
	collision_remove_queued.clear()
	pending_rebuilds.clear()
	rebuild_deadlines.clear()


func get_block(cell: Vector3i) -> int:
	return data.get_block(cell)


func mine_block(cell: Vector3i) -> bool:
	if cell.y <= 0 or data.get_block(cell) == WORLD_DATA.BLOCK_AIR:
		return false
	return set_block(cell, WORLD_DATA.BLOCK_AIR)


func place_block(cell: Vector3i, block_id: int) -> bool:
	if block_id < WORLD_DATA.BLOCK_GRASS or block_id > WORLD_DATA.BLOCK_SAND:
		return false
	if data.get_block(cell) != WORLD_DATA.BLOCK_AIR:
		return false
	return set_block(cell, block_id)


func set_block(cell: Vector3i, block_id: int) -> bool:
	if not data.set_block(cell, block_id):
		return false
	_schedule_affected_rebuilds(cell)
	return true


func place_mechanical_block(cell: Vector3i, type_id: int, axis: int) -> bool:
	if data.get_block(cell) != WORLD_DATA.BLOCK_AIR:
		return false
	if not mechanical_data.place_block(cell, type_id, axis):
		return false
	mechanical_dirty = true
	mechanical_save_delay = MECHANICAL_SAVE_DELAY_SEC
	return true


func remove_mechanical_block(cell: Vector3i) -> bool:
	if not mechanical_data.remove_block(cell):
		return false
	mechanical_dirty = true
	mechanical_save_delay = MECHANICAL_SAVE_DELAY_SEC
	return true


func get_mechanical_block(cell: Vector3i) -> Dictionary:
	return mechanical_data.get_block(cell)


func has_mechanical_block(cell: Vector3i) -> bool:
	return mechanical_data.has_block(cell)


func load_mechanical_blocks() -> void:
	mechanical_data.load_from_save_dict(SaveManager.get_saved_mechanical_blocks())


func save_mechanical_blocks() -> void:
	SaveManager.write_mechanical_blocks_state(mechanical_data.to_save_dict())
	mechanical_dirty = false


func _tick_mechanical_save(delta: float) -> void:
	if not mechanical_dirty:
		return
	mechanical_save_delay -= delta
	if mechanical_save_delay <= 0.0:
		save_mechanical_blocks()


func collision_ring_ready() -> bool:
	for z in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
		for x in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
			var coord := Vector2i(center.x + x, center.y + z)
			if not loaded.has(coord):
				return false
			var entry: Dictionary = loaded[coord]
			if not is_instance_valid(entry.get("collision")):
				return false
	return true


func remesh_idle() -> bool:
	return (
		build_queue.is_empty()
		and pending_rebuilds.is_empty()
		and rebuild_deadlines.is_empty()
		and active_build_tasks.is_empty()
		and build_apply_queue.is_empty()
	)


func diagnostics() -> Dictionary:
	return {
		"tasks_started": build_tasks_started,
		"results_applied": build_results_applied,
		"stale_results_discarded": stale_results_discarded,
		"worker_submit_failures": worker_submit_failures,
		"worker_wait_failures": worker_wait_failures,
		"worker_missing_results": worker_missing_results,
		"worker_stall_warnings": worker_stall_warnings,
		"coalesced_requests": coalesced_edits,
		"active_tasks": active_build_tasks.size(),
		"pending_applies": build_apply_queue.size() + build_queue.size() + pending_rebuilds.size(),
		"max_queue_ms": last_build_usec / 1000.0,
		"max_apply_ms": last_apply_usec / 1000.0,
		"max_background_compute_ms": max_background_compute_usec / 1000.0,
		"max_pump_ms": max_pump_usec / 1000.0,
		"max_collision_ms": last_collision_usec / 1000.0,
		"atomic_swaps": atomic_swaps,
		"atomic_swap_failures": atomic_failures,
	}


func reset_diagnostics() -> bool:
	if not remesh_idle():
		return false
	last_build_usec = 0
	last_apply_usec = 0
	last_collision_usec = 0
	atomic_swaps = 0
	atomic_failures = 0
	coalesced_edits = 0
	build_tasks_started = 0
	build_results_applied = 0
	stale_results_discarded = 0
	worker_submit_failures = 0
	worker_wait_failures = 0
	worker_missing_results = 0
	worker_stall_warnings = 0
	max_background_compute_usec = 0
	max_pump_usec = 0
	return true


func _queue_initial_build(coord: Vector2i) -> void:
	build_revisions[coord] = int(build_revisions.get(coord, 0)) + 1
	build_queue.append(coord)
	build_queued[coord] = true


func _queue_latest_revision(coord: Vector2i, front: bool) -> void:
	if build_queued.has(coord) or active_build_tasks.has(coord):
		return
	if front:
		build_queue.push_front(coord)
	else:
		build_queue.append(coord)
	build_queued[coord] = true


func _prune_queue() -> void:
	var kept: Array[Vector2i] = []
	build_queued.clear()
	for coord: Vector2i in build_queue:
		if distance(coord, center) <= RENDER_RADIUS:
			kept.append(coord)
			build_queued[coord] = true
	build_queue = kept


func _invalidate_outside_active_builds() -> void:
	for coord_value: Variant in active_build_tasks.keys():
		var coord: Vector2i = coord_value
		if distance(coord, center) > RENDER_RADIUS:
			build_revisions[coord] = int(build_revisions.get(coord, 0)) + 1


func _sort_queue() -> void:
	build_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_collision := needs_collision(a)
		var b_collision := needs_collision(b)
		if a_collision != b_collision:
			return a_collision
		return (a - center).length_squared() < (b - center).length_squared()
	)


func _pump_builds() -> void:
	var pump_start := Time.get_ticks_usec()
	_collect_completed_build_tasks()
	_apply_completed_builds(MAX_BUILD_APPLIES_PER_FRAME)
	_dispatch_build_tasks()
	max_pump_usec = maxi(max_pump_usec, Time.get_ticks_usec() - pump_start)


func _dispatch_build_tasks() -> void:
	var dispatch_start := Time.get_ticks_usec()
	while active_build_tasks.size() < MAX_ACTIVE_BUILD_TASKS and not build_queue.is_empty():
		var coord: Vector2i = build_queue.pop_front()
		build_queued.erase(coord)
		var replacing := pending_rebuilds.has(coord)
		if loaded.has(coord) and not replacing:
			continue
		if distance(coord, center) > RENDER_RADIUS:
			pending_rebuilds.erase(coord)
			continue
		if active_build_tasks.has(coord):
			continue
		var revision := int(build_revisions.get(coord, 0))
		if revision <= 0:
			revision = 1
			build_revisions[coord] = revision
		_start_build_task(coord, revision, replacing)
		if Time.get_ticks_usec() - dispatch_start >= BUILD_BUDGET_USEC:
			break


func _start_build_task(coord: Vector2i, revision: int, replacing: bool) -> void:
	var queue_start := Time.get_ticks_usec()
	var result_key := _result_key(coord, revision)
	var overrides_snapshot: Dictionary = data.overrides.duplicate(true)
	var task_callable := Callable(get_script(), "_worker_build_chunk").bind(
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
		"TEKNIK initial chunk %s r%d" % [coord, revision]
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


static func _worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var started_usec := Time.get_ticks_usec()
	# Each task owns its sampler instance. Its loaded save data is intentionally
	# ignored; voxel overrides come only from the immutable main-thread snapshot.
	var sampler = WORLD_DATA.new()
	var cache_started_usec := Time.get_ticks_usec()
	var caches := _build_column_caches_for_sampler(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var mesh_started_usec := Time.get_ticks_usec()
	var mesh_data: Dictionary = WORLD_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		CHUNK_SIZE,
		WORLD_DATA.WORLD_HEIGHT,
		WORLD_DATA.SEA_LEVEL,
		biomes
	)
	var mesh_usec := Time.get_ticks_usec() - mesh_started_usec
	var result := {
		"coord": coord,
		"revision": revision,
		"mesh_data": mesh_data,
		"cache_usec": cache_usec,
		"mesh_usec": mesh_usec,
		"compute_usec": Time.get_ticks_usec() - started_usec,
	}
	result_mutex.lock()
	result_sink[result_key] = result
	result_mutex.unlock()


static func _build_column_caches_for_sampler(coord: Vector2i, sampler) -> Dictionary:
	var width := CHUNK_SIZE + MESH_CACHE_PADDING * 2
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	heights.resize(width * width)
	biomes.resize(width * width)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-MESH_CACHE_PADDING, CHUNK_SIZE + MESH_CACHE_PADDING):
		for local_x in range(-MESH_CACHE_PADDING, CHUNK_SIZE + MESH_CACHE_PADDING):
			var index := (local_z + MESH_CACHE_PADDING) * width + local_x + MESH_CACHE_PADDING
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var samples: Vector4 = sampler.sample_column_noise(world_x, world_z)
			heights[index] = sampler.terrain_height_from_samples(samples)
			biomes[index] = sampler.blended_biome_from_samples(samples, world_x, world_z)
	return {"heights": heights, "biomes": biomes}


func _collect_completed_build_tasks() -> void:
	for coord_value: Variant in active_build_tasks.keys():
		var coord: Vector2i = coord_value
		var task_data: Dictionary = active_build_tasks.get(coord, {})
		var task_id := int(task_data.get("task_id", -1))
		if task_id < 0:
			continue
		if not WorkerThreadPool.is_task_completed(task_id):
			var queued_at_usec := int(task_data.get("queued_at_usec", Time.get_ticks_usec()))
			var task_age_usec := Time.get_ticks_usec() - queued_at_usec
			if (
				task_age_usec >= WORKER_STALL_DIAGNOSTIC_USEC
				and not bool(task_data.get("stall_reported", false))
			):
				task_data["stall_reported"] = true
				active_build_tasks[coord] = task_data
				worker_stall_warnings += 1
				_report_worker_failure(
					"WORKER_TASK_STALL",
					coord,
					int(task_data.get("revision", 0)),
					task_id,
					"task still incomplete after %.3f s"
					% (task_age_usec / 1000000.0)
				)
			continue
		var wait_error := WorkerThreadPool.wait_for_task_completion(task_id)
		var result_key := String(task_data.get("result_key", ""))
		var result := _take_worker_result(result_key)
		var completed_revision := int(task_data.get("revision", 0))
		var latest_revision := int(build_revisions.get(coord, 0))
		var replacing := bool(task_data.get("replacing", false))
		active_build_tasks.erase(coord)
		if wait_error != OK:
			worker_wait_failures += 1
			_report_worker_failure(
				"WORKER_WAIT_FAILURE",
				coord,
				completed_revision,
				task_id,
				"wait_for_task_completion error=%d result_key=%s" % [wait_error, result_key]
			)
		max_background_compute_usec = maxi(
			max_background_compute_usec,
			int(result.get("compute_usec", 0))
		)
		var still_wanted := distance(coord, center) <= RENDER_RADIUS
		var target_state_valid := loaded.has(coord) if replacing else not loaded.has(coord)
		if result.is_empty():
			worker_missing_results += 1
			_report_worker_failure(
				"WORKER_RESULT_MISSING",
				coord,
				completed_revision,
				task_id,
				"task completed without published result; result_key=%s latest_revision=%d replacing=%s still_wanted=%s target_state_valid=%s"
				% [
					result_key,
					latest_revision,
					replacing,
					still_wanted,
					target_state_valid,
				]
			)
		if (
			result.is_empty()
			or completed_revision != latest_revision
			or not still_wanted
			or not target_state_valid
		):
			stale_results_discarded += 1
			if completed_revision != latest_revision and still_wanted:
				if pending_rebuilds.has(coord) or not loaded.has(coord):
					_queue_latest_revision(coord, true)
			continue
		build_apply_queue.append({
			"coord": coord,
			"revision": completed_revision,
			"replacing": replacing,
			"queued_at_usec": int(task_data.get("queued_at_usec", 0)),
			"result": result,
		})


func _take_worker_result(result_key: String) -> Dictionary:
	var result: Dictionary = {}
	worker_result_mutex.lock()
	if completed_worker_results.has(result_key):
		result = completed_worker_results[result_key]
		completed_worker_results.erase(result_key)
	worker_result_mutex.unlock()
	return result


func _report_worker_failure(
	marker: String,
	coord: Vector2i,
	revision: int,
	task_id: int,
	detail: String
) -> void:
	var message := (
		"%s coord=%s revision=%d task_id=%d center=%s active=%d build_queue=%d apply_queue=%d result_sink=%d detail=%s"
		% [
			marker,
			coord,
			revision,
			task_id,
			center,
			active_build_tasks.size(),
			build_queue.size(),
			build_apply_queue.size(),
			completed_worker_results.size(),
			detail,
		]
	)
	if marker == "WORKER_TASK_STALL":
		push_warning(message)
	else:
		push_error(message)
	var capture := get_node_or_null("/root/DiagnosticLogCapture")
	if capture != null and capture.has_method("record_event"):
		capture.record_event(marker, message)


func _apply_completed_builds(max_applies: int) -> void:
	var applies := 0
	while applies < max_applies and not build_apply_queue.is_empty():
		var apply_data: Dictionary = build_apply_queue.pop_front()
		var coord: Vector2i = apply_data.get("coord", Vector2i.ZERO)
		var revision := int(apply_data.get("revision", 0))
		var latest_revision := int(build_revisions.get(coord, 0))
		var replacing := bool(apply_data.get("replacing", false))
		var still_wanted := distance(coord, center) <= RENDER_RADIUS
		var target_state_valid := loaded.has(coord) if replacing else not loaded.has(coord)
		if revision != latest_revision or not still_wanted or not target_state_valid:
			stale_results_discarded += 1
			if revision != latest_revision and still_wanted:
				if pending_rebuilds.has(coord) or not loaded.has(coord):
					_queue_latest_revision(coord, true)
			continue
		var result: Dictionary = apply_data.get("result", {})
		var mesh_data: Dictionary = result.get("mesh_data", {})
		var apply_started_usec := Time.get_ticks_usec()
		var applied := false
		if replacing:
			if _swap_chunk(coord, mesh_data):
				pending_rebuilds.erase(coord)
				rebuild_deadlines.erase(coord)
				applied = true
			else:
				atomic_failures += 1
				rebuild_deadlines[coord] = Time.get_ticks_msec() + EDIT_DEBOUNCE_MSEC
		else:
			applied = _commit_chunk(coord, mesh_data, false)
		last_apply_usec = maxi(last_apply_usec, Time.get_ticks_usec() - apply_started_usec)
		if not applied:
			if not replacing:
				_queue_latest_revision(coord, true)
			continue
		last_face_count = int(mesh_data.get("face_count", 0))
		build_results_applied += 1
		applies += 1
		print(
			"THREADED_CHUNK_STREAM_COMPLETE coord=%s revision=%d cache_ms=%.3f mesh_ms=%.3f background_ms=%.3f apply_ms=%.3f latency_ms=%.3f"
			% [
				coord,
				revision,
				int(result.get("cache_usec", 0)) / 1000.0,
				int(result.get("mesh_usec", 0)) / 1000.0,
				int(result.get("compute_usec", 0)) / 1000.0,
				last_apply_usec / 1000.0,
				(Time.get_ticks_usec() - int(apply_data.get("queued_at_usec", 0))) / 1000.0,
			]
		)


func _result_key(coord: Vector2i, revision: int) -> String:
	return "%d:%d:%d" % [coord.x, coord.y, revision]


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return _build_column_caches_for_sampler(coord, data)


func _build_height_cache(coord: Vector2i) -> PackedInt32Array:
	var caches := _build_column_caches(coord)
	return caches.get("heights", PackedInt32Array())


func _build_biome_cache(coord: Vector2i) -> PackedByteArray:
	var caches := _build_column_caches(coord)
	return caches.get("biomes", PackedByteArray())


func _commit_chunk(coord: Vector2i, mesh_data: Dictionary, with_collision: bool) -> bool:
	var entry := _create_entry(coord, mesh_data, with_collision)
	if entry.is_empty():
		return false
	var root_node := entry.get("root") as Node3D
	add_child(root_node)
	loaded[coord] = entry
	return true


func _swap_chunk(coord: Vector2i, mesh_data: Dictionary) -> bool:
	var replacement := _create_entry(coord, mesh_data, needs_collision(coord))
	if replacement.is_empty():
		return false
	var previous: Dictionary = loaded.get(coord, {})
	var old_root := previous.get("root") as Node3D
	var new_root := replacement.get("root") as Node3D
	add_child(new_root)
	loaded[coord] = replacement
	collision_add_queue.erase(coord)
	collision_remove_queue.erase(coord)
	collision_add_queued.erase(coord)
	collision_remove_queued.erase(coord)
	if is_instance_valid(old_root):
		old_root.queue_free()
	atomic_swaps += 1
	return true


func _create_entry(coord: Vector2i, mesh_data: Dictionary, with_collision: bool) -> Dictionary:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	if vertices.is_empty():
		return {}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = mesh_data.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_INDEX] = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var root_node := Node3D.new()
	root_node.name = "Chunk_%d_%d" % [coord.x, coord.y]
	root_node.position = Vector3(coord.x * CHUNK_SIZE, 0, coord.y * CHUNK_SIZE)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	root_node.add_child(mesh_instance)
	var collision: StaticBody3D
	if with_collision:
		collision = _create_collision(mesh)
		if collision == null:
			return {}
		root_node.add_child(collision)
	return {"root": root_node, "mesh": mesh, "collision": collision}


func _create_collision(mesh: ArrayMesh) -> StaticBody3D:
	var shape: Shape3D = mesh.create_trimesh_shape()
	if shape == null:
		return null
	if shape is ConcavePolygonShape3D:
		shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	body.add_child(shape_node)
	return body


func _refresh_collisions() -> void:
	for coord_value: Variant in loaded.keys():
		var coord: Vector2i = coord_value
		var entry: Dictionary = loaded[coord]
		var has_collision := is_instance_valid(entry.get("collision"))
		if needs_collision(coord):
			if not has_collision and not collision_add_queued.has(coord):
				collision_add_queue.append(coord)
				collision_add_queued[coord] = true
		elif has_collision and not collision_remove_queued.has(coord):
			collision_remove_queue.append(coord)
			collision_remove_queued[coord] = true
	collision_add_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared()
	)


func _pump_collisions() -> void:
	if not collision_add_queue.is_empty():
		var coord: Vector2i = collision_add_queue.pop_front()
		collision_add_queued.erase(coord)
		if loaded.has(coord) and needs_collision(coord):
			var start := Time.get_ticks_usec()
			var entry: Dictionary = loaded[coord]
			var mesh := entry.get("mesh") as ArrayMesh
			var collision := _create_collision(mesh)
			if collision != null:
				var root_node := entry.get("root") as Node3D
				root_node.add_child(collision)
				entry["collision"] = collision
				loaded[coord] = entry
			last_collision_usec = maxi(last_collision_usec, Time.get_ticks_usec() - start)
	for _index in range(2):
		if collision_remove_queue.is_empty():
			break
		var coord: Vector2i = collision_remove_queue.pop_front()
		collision_remove_queued.erase(coord)
		if not loaded.has(coord) or needs_collision(coord):
			continue
		var entry: Dictionary = loaded[coord]
		var collision := entry.get("collision") as StaticBody3D
		if is_instance_valid(collision):
			collision.queue_free()
		entry["collision"] = null
		loaded[coord] = entry


func _prepare_spawn() -> void:
	if spawn_prepared or not collision_ring_ready():
		return
	spawn_prepared = true
	if not is_instance_valid(target):
		return
	if override_spawn_position != null:
		target.global_position = override_spawn_position
	else:
		var spawn_x := int(CHUNK_SIZE * 0.5)
		var spawn_z := int(CHUNK_SIZE * 0.5)
		target.global_position = Vector3(
			spawn_x + 0.5,
			data.terrain_height(spawn_x, spawn_z) + 2.2,
			spawn_z + 0.5
		)
	if target_physics_enabled:
		target.set_physics_process(true)


func needs_collision(coord: Vector2i) -> bool:
	return distance(coord, center) <= COLLISION_RADIUS


func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _unload_far_chunks() -> void:
	for coord_value: Variant in loaded.keys():
		var coord: Vector2i = coord_value
		if distance(coord, center) <= UNLOAD_RADIUS:
			continue
		build_revisions[coord] = int(build_revisions.get(coord, 0)) + 1
		pending_rebuilds.erase(coord)
		rebuild_deadlines.erase(coord)
		collision_add_queue.erase(coord)
		collision_remove_queue.erase(coord)
		collision_add_queued.erase(coord)
		collision_remove_queued.erase(coord)
		var entry: Dictionary = loaded[coord]
		var root_node := entry.get("root") as Node3D
		if is_instance_valid(root_node):
			root_node.queue_free()
		loaded.erase(coord)


func _schedule_affected_rebuilds(cell: Vector3i) -> void:
	var chunk_coord := cell_to_chunk(cell)
	var chunk_x_values: Array[int] = [chunk_coord.x]
	var chunk_z_values: Array[int] = [chunk_coord.y]
	var local_x := posmod(cell.x, CHUNK_SIZE)
	var local_z := posmod(cell.z, CHUNK_SIZE)
	if local_x == 0:
		chunk_x_values.append(chunk_coord.x - 1)
	elif local_x == CHUNK_SIZE - 1:
		chunk_x_values.append(chunk_coord.x + 1)
	if local_z == 0:
		chunk_z_values.append(chunk_coord.y - 1)
	elif local_z == CHUNK_SIZE - 1:
		chunk_z_values.append(chunk_coord.y + 1)
	for chunk_z in chunk_z_values:
		for chunk_x in chunk_x_values:
			var coord := Vector2i(chunk_x, chunk_z)
			if not loaded.has(coord):
				continue
			if pending_rebuilds.has(coord):
				coalesced_edits += 1
			pending_rebuilds[coord] = true
			rebuild_deadlines[coord] = Time.get_ticks_msec() + EDIT_DEBOUNCE_MSEC


func _promote_rebuilds() -> void:
	var now := Time.get_ticks_msec()
	for coord_value: Variant in rebuild_deadlines.keys():
		var coord: Vector2i = coord_value
		if int(rebuild_deadlines[coord]) > now:
			continue
		rebuild_deadlines.erase(coord)
		if not loaded.has(coord):
			pending_rebuilds.erase(coord)
			continue
		build_revisions[coord] = int(build_revisions.get(coord, 0)) + 1
		if active_build_tasks.has(coord) or build_queued.has(coord):
			coalesced_edits += 1
			continue
		_queue_latest_revision(coord, true)


func _create_water() -> void:
	water = MeshInstance3D.new()
	water.name = "Water"
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(512.0, 512.0)
	var water_material := StandardMaterial3D.new()
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material.albedo_color = Color(0.18, 0.48, 0.68, 1.0)
	plane.material = water_material
	water.mesh = plane
	water.position.y = WORLD_DATA.SEA_LEVEL + 0.54
	add_child(water)