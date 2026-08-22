extends "res://scripts/world/playable_world_stage11_generation_runtime.gd"

const SHIPPING_DATA := preload("res://scripts/world/playable_world_carpathian_data.gd")
const WORKER_DATA := preload("res://scripts/world/playable_world_worker_carpathian_data.gd")
const OVERRIDE_SPATIAL_INDEX := preload("res://scripts/world/playable_world_override_spatial_index.gd")
const SHIPPING_GENERATION_CACHE := preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const SHIPPING_STAGE12_CACHE := preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const SHIPPING_STAGE12_MESHER := preload("res://scripts/world/playable_world_stage12_mesher.gd")
const FROZEN_STAGE11_RUNTIME := preload("res://scripts/world/playable_world_stage11_generation_runtime.gd")
const STAGE12_STAGE2_RUNTIME_BASE := preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

const COLLISION_FACES_KEY := "_collision_faces"
const FRAME_HITCH_THRESHOLD_USEC := 20000
const FRAME_HITCH_REPORT_COOLDOWN_MSEC := 250

var _stream_apply_happened_this_frame := false
var _override_index = OVERRIDE_SPATIAL_INDEX.new()

# One persistent generation thread replaces the previous two continuously busy
# WorkerThreadPool jobs. This deliberately reduces CPU contention and lets us
# reuse generation/noise/native sampler state across chunks. Godot 4.3 accepts
# a PRIORITY_LOW request here, but its POSIX backend does not expose a platform
# priority callback, so Android smoothness does not rely on that flag; the
# single-worker architecture is the actual scheduling control in this build.
var _chunk_worker_thread := Thread.new()
var _chunk_worker_mutex := Mutex.new()
var _chunk_worker_semaphore := Semaphore.new()
var _chunk_worker_jobs: Array[Dictionary] = []
var _chunk_worker_should_stop := false
var _dedicated_worker_available := false

# Android frame-hitch diagnostics. These stay in memory through the diagnostic
# capture service and are intentionally coarse; the diagnostic itself must not
# become a per-frame source of I/O.
var _last_override_snapshot_usec := 0
var _max_override_snapshot_usec := 0
var _last_render_resource_usec := 0
var _max_render_resource_usec := 0
var _last_center_change_usec := 0
var _max_center_change_usec := 0
var _last_unload_usec := 0
var _max_unload_usec := 0
var _max_frame_delta_usec := 0
var _last_hitch_report_msec := 0

# Public shipping runtime. The authoritative main-thread data object loads the
# save once. Background generation uses WORKER_DATA, which performs the same
# deterministic terrain/biome setup but intentionally skips persistent save I/O.
# Player edits are supplied as immutable, chunk-local snapshots.

func _init() -> void:
	data = SHIPPING_DATA.new()


func configure(streaming_target: Node3D) -> void:
	_override_index.rebuild(data.overrides, CHUNK_SIZE)
	_start_dedicated_chunk_worker()
	super.configure(streaming_target)


func shutdown() -> void:
	_stop_dedicated_chunk_worker()
	super.shutdown()


func tick(delta: float) -> void:
	var frame_delta_usec := roundi(delta * 1000000.0)
	_max_frame_delta_usec = maxi(_max_frame_delta_usec, frame_delta_usec)
	if frame_delta_usec >= FRAME_HITCH_THRESHOLD_USEC:
		_record_frame_hitch(frame_delta_usec)
	super.tick(delta)


func set_center(next_center: Vector2i) -> void:
	var started_usec := Time.get_ticks_usec()
	super.set_center(next_center)
	_last_center_change_usec = Time.get_ticks_usec() - started_usec
	_max_center_change_usec = maxi(_max_center_change_usec, _last_center_change_usec)


func set_block(cell: Vector3i, block_id: int) -> bool:
	var changed := super.set_block(cell, block_id)
	if changed:
		_override_index.set_override(cell, block_id)
	return changed


func diagnostics() -> Dictionary:
	var result: Dictionary = super.diagnostics()
	result["chunk_worker_mode"] = "dedicated_single_worker" if _dedicated_worker_available else "worker_pool_fallback"
	result["max_override_snapshot_ms"] = _max_override_snapshot_usec / 1000.0
	result["max_render_resource_ms"] = _max_render_resource_usec / 1000.0
	result["max_center_change_ms"] = _max_center_change_usec / 1000.0
	result["max_unload_ms"] = _max_unload_usec / 1000.0
	result["max_frame_delta_ms"] = _max_frame_delta_usec / 1000.0
	return result


func reset_diagnostics() -> bool:
	if not super.reset_diagnostics():
		return false
	_last_override_snapshot_usec = 0
	_max_override_snapshot_usec = 0
	_last_render_resource_usec = 0
	_max_render_resource_usec = 0
	_last_center_change_usec = 0
	_max_center_change_usec = 0
	_last_unload_usec = 0
	_max_unload_usec = 0
	_max_frame_delta_usec = 0
	_last_hitch_report_msec = 0
	return true


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return SHIPPING_GENERATION_CACHE.build(coord, data)


static func _collision_faces_from_mesh_data(mesh_data: Dictionary) -> PackedVector3Array:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	if vertices.is_empty() or indices.is_empty() or indices.size() % 3 != 0:
		return PackedVector3Array()
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for index_position in range(indices.size()):
		var vertex_index := int(indices[index_position])
		if vertex_index < 0 or vertex_index >= vertices.size():
			return PackedVector3Array()
		faces[index_position] = vertices[vertex_index]
	return faces


static func _build_chunk_result_with_sampler(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	sampler,
	sampler_init_usec: int = 0
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var cache_started_usec := Time.get_ticks_usec()
	var caches: Dictionary = SHIPPING_GENERATION_CACHE.build(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
	var terrain_modifiers: PackedByteArray = caches.get("stage9_terrain_modifiers", PackedByteArray())
	var mesh_height := mini(
		SHIPPING_DATA.OVERHAUL_WORLD_HEIGHT,
		STAGE12_STAGE2_RUNTIME_BASE._effective_mesh_height(coord, heights, overrides_snapshot) + 2
	)
	var mesh_started_usec := Time.get_ticks_usec()
	var expression_codes: Dictionary = SHIPPING_STAGE12_CACHE.build_expression_codes(caches, sampler)
	var transition_codes: PackedByteArray = expression_codes.get("transition_codes", PackedByteArray())
	var hydrology_codes: PackedByteArray = expression_codes.get("hydrology_codes", PackedByteArray())
	# Cave carving (steps 8-9): pure world-coordinate field, evaluated once per
	# chunk build. Player edits win: the snapshot overlays the carve map.
	var combined_overrides := overrides_snapshot
	var cave_blocked := PackedInt32Array()
	if sampler.has_method("cave_data_for_chunk"):
		var cave_info: Dictionary = sampler.cave_data_for_chunk(coord, caches, mesh_height)
		cave_blocked = cave_info.get("blocked_columns", PackedInt32Array())
		var cave_overrides: Dictionary = cave_info.get("overrides", {})
		if not cave_overrides.is_empty():
			combined_overrides = {}
			for cave_key in cave_overrides:
				combined_overrides[cave_key] = cave_overrides[cave_key]
			for edit_key in overrides_snapshot:
				combined_overrides[edit_key] = overrides_snapshot[edit_key]
	var blocked_tree_columns: PackedInt32Array = FROZEN_STAGE11_RUNTIME._stage6_blocked_tree_columns(
		coord, caches, sampler
	)
	blocked_tree_columns.append_array(cave_blocked)
	var mesh_data: Dictionary = SHIPPING_STAGE12_MESHER.build(
		coord,
		heights,
		combined_overrides,
		12,
		mesh_height,
		SHIPPING_DATA.SEA_LEVEL,
		biomes,
		water_types,
		terrain_modifiers,
		transition_codes,
		hydrology_codes,
		sampler,
		blocked_tree_columns
	)
	var mesh_usec := Time.get_ticks_usec() - mesh_started_usec
	var collision_data_started_usec := Time.get_ticks_usec()
	mesh_data[COLLISION_FACES_KEY] = _collision_faces_from_mesh_data(mesh_data)
	var collision_data_usec := Time.get_ticks_usec() - collision_data_started_usec
	return {
		"coord": coord,
		"revision": revision,
		"mesh_data": mesh_data,
		"cache_usec": cache_usec,
		"mesh_usec": mesh_usec,
		"collision_data_usec": collision_data_usec,
		"sampler_init_usec": sampler_init_usec,
		"mesh_height": mesh_height,
		"compute_usec": Time.get_ticks_usec() - started_usec,
	}


# Compatibility entry point retained for existing CI/equivalence tests and for
# the fallback WorkerThreadPool path. It uses the generation-only sampler, so
# even fallback tasks never load the world save.
static func _stage3_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var sampler_started_usec := Time.get_ticks_usec()
	var sampler = WORKER_DATA.new()
	var sampler_init_usec := Time.get_ticks_usec() - sampler_started_usec
	var result := _build_chunk_result_with_sampler(
		coord,
		overrides_snapshot,
		revision,
		sampler,
		sampler_init_usec
	)
	result_mutex.lock()
	result_sink[result_key] = result
	result_mutex.unlock()


func _start_dedicated_chunk_worker() -> void:
	if _chunk_worker_thread.is_started():
		_dedicated_worker_available = true
		return
	_chunk_worker_should_stop = false
	var start_error := _chunk_worker_thread.start(
		Callable(self, "_chunk_worker_loop"),
		Thread.PRIORITY_LOW
	)
	_dedicated_worker_available = start_error == OK
	if not _dedicated_worker_available:
		push_warning(
			"TEKNIK dedicated chunk thread unavailable; falling back to WorkerThreadPool error=%d"
			% start_error
		)


func _stop_dedicated_chunk_worker() -> void:
	if not _chunk_worker_thread.is_started():
		_dedicated_worker_available = false
		return
	_chunk_worker_mutex.lock()
	_chunk_worker_should_stop = true
	_chunk_worker_jobs.clear()
	_chunk_worker_mutex.unlock()
	_chunk_worker_semaphore.post()
	_chunk_worker_thread.wait_to_finish()
	_dedicated_worker_available = false


func _chunk_worker_loop() -> void:
	var sampler_started_usec := Time.get_ticks_usec()
	var sampler = WORKER_DATA.new()
	var first_sampler_init_usec := Time.get_ticks_usec() - sampler_started_usec
	var first_job := true
	while true:
		_chunk_worker_semaphore.wait()
		_chunk_worker_mutex.lock()
		var should_stop := _chunk_worker_should_stop
		var job: Dictionary = {}
		if not should_stop and not _chunk_worker_jobs.is_empty():
			job = _chunk_worker_jobs.pop_front()
		_chunk_worker_mutex.unlock()
		if should_stop:
			break
		if job.is_empty():
			continue
		var result := _build_chunk_result_with_sampler(
			job.get("coord", Vector2i.ZERO),
			job.get("overrides_snapshot", {}),
			int(job.get("revision", 0)),
			sampler,
			first_sampler_init_usec if first_job else 0
		)
		first_job = false
		worker_result_mutex.lock()
		completed_worker_results[String(job.get("result_key", ""))] = result
		worker_result_mutex.unlock()


func _start_build_task(coord: Vector2i, revision: int, replacing: bool) -> void:
	var dispatch_started_usec := Time.get_ticks_usec()
	var result_key := _result_key(coord, revision)
	var snapshot_started_usec := Time.get_ticks_usec()
	var overrides_snapshot: Dictionary = _override_index.snapshot_for_chunk(
		coord,
		CHUNK_SIZE,
		MESH_CACHE_PADDING
	)
	_last_override_snapshot_usec = Time.get_ticks_usec() - snapshot_started_usec
	_max_override_snapshot_usec = maxi(
		_max_override_snapshot_usec,
		_last_override_snapshot_usec
	)

	if _dedicated_worker_available:
		_chunk_worker_mutex.lock()
		_chunk_worker_jobs.append({
			"coord": coord,
			"overrides_snapshot": overrides_snapshot,
			"revision": revision,
			"result_key": result_key,
		})
		_chunk_worker_mutex.unlock()
		_chunk_worker_semaphore.post()
		active_build_tasks[coord] = {
			"revision": revision,
			"result_key": result_key,
			"replacing": replacing,
			"queued_at_usec": dispatch_started_usec,
			"snapshot_usec": _last_override_snapshot_usec,
			"stall_reported": false,
		}
	else:
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
			"TEKNIK shipping chunk %s r%d" % [coord, revision]
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
			"queued_at_usec": dispatch_started_usec,
			"snapshot_usec": _last_override_snapshot_usec,
			"stall_reported": false,
		}

	build_tasks_started += 1
	last_build_usec = maxi(last_build_usec, Time.get_ticks_usec() - dispatch_started_usec)


func _collect_completed_build_tasks() -> void:
	if not _dedicated_worker_available:
		super._collect_completed_build_tasks()
		return
	for coord_value: Variant in active_build_tasks.keys():
		var coord: Vector2i = coord_value
		var task_data: Dictionary = active_build_tasks.get(coord, {})
		var result_key := String(task_data.get("result_key", ""))
		if not _worker_result_ready(result_key):
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
					-1,
					"dedicated worker still incomplete after %.3f s"
					% (task_age_usec / 1000000.0)
				)
			continue

		var result := _take_worker_result(result_key)
		var completed_revision := int(task_data.get("revision", 0))
		var latest_revision := int(build_revisions.get(coord, 0))
		var replacing := bool(task_data.get("replacing", false))
		active_build_tasks.erase(coord)
		result["snapshot_usec"] = int(task_data.get("snapshot_usec", 0))
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
				-1,
				"dedicated worker completed without published result; result_key=%s"
				% result_key
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


func _worker_result_ready(result_key: String) -> bool:
	worker_result_mutex.lock()
	var ready := completed_worker_results.has(result_key)
	worker_result_mutex.unlock()
	return ready


func _pump_builds() -> void:
	var pump_start := Time.get_ticks_usec()
	_collect_completed_build_tasks()
	_stream_apply_happened_this_frame = false
	var applied_before := build_results_applied
	# A queued nearby collision gets the next frame before another visual chunk.
	# This avoids combining two independent engine-resource spikes without
	# starving collision while a burst of completed render chunks is waiting.
	var apply_budget := 0 if not collision_add_queue.is_empty() else MAX_BUILD_APPLIES_PER_FRAME
	_apply_completed_builds(apply_budget)
	_stream_apply_happened_this_frame = build_results_applied > applied_before
	_dispatch_build_tasks()
	max_pump_usec = maxi(max_pump_usec, Time.get_ticks_usec() - pump_start)


func _create_entry(coord: Vector2i, mesh_data: Dictionary, with_collision: bool) -> Dictionary:
	# Let the frozen base path create only the render resource. Collision uses the
	# worker-prepared triangle stream below, avoiding ArrayMesh.create_trimesh_shape().
	var render_started_usec := Time.get_ticks_usec()
	var entry: Dictionary = super._create_entry(coord, mesh_data, false)
	_last_render_resource_usec = Time.get_ticks_usec() - render_started_usec
	_max_render_resource_usec = maxi(_max_render_resource_usec, _last_render_resource_usec)
	if entry.is_empty():
		return {}
	var collision_faces: PackedVector3Array = mesh_data.get(
		COLLISION_FACES_KEY,
		PackedVector3Array()
	)
	entry["collision_faces"] = collision_faces
	if with_collision:
		var collision := _create_collision_from_faces(collision_faces)
		if collision == null:
			var root_to_free := entry.get("root") as Node3D
			if is_instance_valid(root_to_free):
				root_to_free.free()
			return {}
		var root_node := entry.get("root") as Node3D
		root_node.add_child(collision)
		entry["collision"] = collision
	return entry


func _create_collision_from_faces(faces: PackedVector3Array) -> StaticBody3D:
	if faces.is_empty() or faces.size() % 3 != 0:
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	body.add_child(shape_node)
	return body


func _pump_collisions() -> void:
	# Never pay render-resource apply and concave collision construction in the
	# same frame. The queued nearby collision is handled on the following frame,
	# and _pump_builds() then withholds another visual apply until it is attached.
	if not _stream_apply_happened_this_frame and not collision_add_queue.is_empty():
		var coord: Vector2i = collision_add_queue.pop_front()
		collision_add_queued.erase(coord)
		if loaded.has(coord) and needs_collision(coord):
			var start := Time.get_ticks_usec()
			var entry: Dictionary = loaded[coord]
			var faces: PackedVector3Array = entry.get("collision_faces", PackedVector3Array())
			var collision := _create_collision_from_faces(faces)
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


func _unload_far_chunks() -> void:
	var started_usec := Time.get_ticks_usec()
	super._unload_far_chunks()
	_last_unload_usec = Time.get_ticks_usec() - started_usec
	_max_unload_usec = maxi(_max_unload_usec, _last_unload_usec)


func _record_frame_hitch(frame_delta_usec: int) -> void:
	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_hitch_report_msec < FRAME_HITCH_REPORT_COOLDOWN_MSEC:
		return
	_last_hitch_report_msec = now_msec
	var capture := get_node_or_null("/root/DiagnosticLogCapture")
	if capture == null or not capture.has_method("record_event"):
		return
	var worker_queue_size := 0
	_chunk_worker_mutex.lock()
	worker_queue_size = _chunk_worker_jobs.size()
	_chunk_worker_mutex.unlock()
	capture.record_event(
		"FRAME_HITCH",
		"frame_ms=%.3f center=%s active=%d worker_q=%d build_q=%d apply_q=%d collision_q=%d snapshot_ms=%.3f render_ms=%.3f collision_max_ms=%.3f center_change_ms=%.3f unload_ms=%.3f background_max_ms=%.3f pump_max_ms=%.3f"
		% [
			frame_delta_usec / 1000.0,
			center,
			active_build_tasks.size(),
			worker_queue_size,
			build_queue.size(),
			build_apply_queue.size(),
			collision_add_queue.size(),
			_last_override_snapshot_usec / 1000.0,
			_last_render_resource_usec / 1000.0,
			last_collision_usec / 1000.0,
			_last_center_change_usec / 1000.0,
			_last_unload_usec / 1000.0,
			max_background_compute_usec / 1000.0,
			max_pump_usec / 1000.0,
		]
	)
