extends "res://scripts/world/playable_world_generation_runtime.gd"

const OPT_DATA := preload("res://scripts/world/playable_world_carpathian_data.gd")
const OPT_GENERATION_CACHE := preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const OPT_STAGE12_CACHE := preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const OPT_STAGE12_MESHER := preload("res://scripts/world/playable_world_stage12_mesher.gd")
const OPT_STAGE11_RUNTIME := preload("res://scripts/world/playable_world_stage11_generation_runtime.gd")
const OPT_STAGE2_RUNTIME := preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

const OPT_COLLISION_FACES_KEY := "_collision_faces"
const STREAM_WORKER_LIMIT := 1
const FRAME_HITCH_THRESHOLD_USEC := 20000
const FRAME_HITCH_LOG_COOLDOWN_USEC := 500000
const STREAM_REPORT_INTERVAL_USEC := 2000000

var _stream_thread := Thread.new()
var _stream_semaphore := Semaphore.new()
var _stream_mutex := Mutex.new()
var _stream_state: Dictionary = {
	"exit": false,
	"busy": false,
	"job": {},
	"result": {},
	"sampler_setup_usec": 0,
	"ready": false,
}
var _stream_thread_started := false

var _override_buckets: Dictionary = {}
var _override_index_entries := 0
var _last_snapshot_count := 0
var _max_snapshot_usec := 0

var _last_tick_started_usec := 0
var _last_tick_summary: Dictionary = {}
var _current_tick_summary: Dictionary = {}
var _frame_hitch_count := 0
var _max_frame_gap_usec := 0
var _last_hitch_log_usec := 0

var _stream_report_started_usec := 0
var _stream_report_chunks := 0
var _stream_report_max_apply_usec := 0
var _stream_report_max_background_usec := 0
var _stream_report_max_snapshot_usec := 0


func _init() -> void:
	super._init()
	_rebuild_override_index()


func configure(streaming_target: Node3D) -> void:
	_start_stream_thread()
	super.configure(streaming_target)
	_stream_report_started_usec = Time.get_ticks_usec()
	_record_stream_event(
		"STREAM_RUNTIME_START",
		"worker=dedicated-low-priority worker_limit=%d renderer=%s driver=%s api=%s overrides=%d"
		% [
			STREAM_WORKER_LIMIT,
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name(),
			RenderingServer.get_video_adapter_api_version(),
			_override_index_entries,
		]
	)


func shutdown() -> void:
	_stop_stream_thread()
	active_build_tasks.clear()
	super.shutdown()


func tick(delta: float) -> void:
	var tick_started_usec := Time.get_ticks_usec()
	var frame_gap_usec := 0
	if _last_tick_started_usec > 0:
		frame_gap_usec = tick_started_usec - _last_tick_started_usec
		_max_frame_gap_usec = maxi(_max_frame_gap_usec, frame_gap_usec)
	_last_tick_started_usec = tick_started_usec

	if frame_gap_usec >= FRAME_HITCH_THRESHOLD_USEC:
		_frame_hitch_count += 1
		var now_usec := tick_started_usec
		if now_usec - _last_hitch_log_usec >= FRAME_HITCH_LOG_COOLDOWN_USEC:
			_last_hitch_log_usec = now_usec
			_record_frame_hitch(frame_gap_usec, _last_tick_summary)

	_current_tick_summary = {}
	var phase_started_usec := Time.get_ticks_usec()
	_promote_rebuilds()
	_current_tick_summary["rebuild_usec"] = Time.get_ticks_usec() - phase_started_usec

	phase_started_usec = Time.get_ticks_usec()
	if is_instance_valid(target):
		var next_center := world_to_chunk(target.global_position)
		if next_center != center:
			set_center(next_center)
		if is_instance_valid(water):
			water.position.x = target.global_position.x
			water.position.z = target.global_position.z
	_current_tick_summary["center_usec"] = Time.get_ticks_usec() - phase_started_usec

	phase_started_usec = Time.get_ticks_usec()
	_pump_builds()
	_current_tick_summary["pump_usec"] = Time.get_ticks_usec() - phase_started_usec

	phase_started_usec = Time.get_ticks_usec()
	_refresh_collisions()
	_current_tick_summary["collision_refresh_usec"] = Time.get_ticks_usec() - phase_started_usec

	phase_started_usec = Time.get_ticks_usec()
	_pump_collisions()
	_current_tick_summary["collision_pump_usec"] = Time.get_ticks_usec() - phase_started_usec

	phase_started_usec = Time.get_ticks_usec()
	_prepare_spawn()
	_current_tick_summary["spawn_usec"] = Time.get_ticks_usec() - phase_started_usec

	phase_started_usec = Time.get_ticks_usec()
	data.tick_save(delta)
	_current_tick_summary["save_usec"] = Time.get_ticks_usec() - phase_started_usec
	_current_tick_summary["tick_usec"] = Time.get_ticks_usec() - tick_started_usec
	_current_tick_summary["active"] = active_build_tasks.size()
	_current_tick_summary["build_queue"] = build_queue.size()
	_current_tick_summary["apply_queue"] = build_apply_queue.size()
	_current_tick_summary["collision_queue"] = collision_add_queue.size()
	_last_tick_summary = _current_tick_summary.duplicate()


func set_block(cell: Vector3i, block_id: int) -> bool:
	var changed := super.set_block(cell, block_id)
	if changed:
		_index_override_cell(cell, int(data.overrides.get(data.cell_key(cell), block_id)))
	return changed


func diagnostics() -> Dictionary:
	var result: Dictionary = super.diagnostics()
	result["stream_worker_limit"] = STREAM_WORKER_LIMIT
	result["stream_worker_low_priority"] = true
	result["stream_worker_ready"] = bool(_stream_state.get("ready", false))
	result["stream_sampler_setup_ms"] = int(_stream_state.get("sampler_setup_usec", 0)) / 1000.0
	result["override_index_entries"] = _override_index_entries
	result["last_override_snapshot_entries"] = _last_snapshot_count
	result["max_override_snapshot_ms"] = _max_snapshot_usec / 1000.0
	result["frame_hitches"] = _frame_hitch_count
	result["max_frame_gap_ms"] = _max_frame_gap_usec / 1000.0
	return result


func reset_diagnostics() -> bool:
	if not super.reset_diagnostics():
		return false
	_max_snapshot_usec = 0
	_frame_hitch_count = 0
	_max_frame_gap_usec = 0
	return true


func _start_stream_thread() -> void:
	if _stream_thread_started:
		return
	_stream_mutex.lock()
	_stream_state["exit"] = false
	_stream_state["busy"] = false
	_stream_state["job"] = {}
	_stream_state["result"] = {}
	_stream_state["ready"] = false
	_stream_state["sampler_setup_usec"] = 0
	_stream_mutex.unlock()
	var callable := Callable(get_script(), "_low_priority_worker_loop").bind(
		_stream_semaphore,
		_stream_mutex,
		_stream_state
	)
	var start_error := _stream_thread.start(callable, Thread.PRIORITY_LOW)
	if start_error != OK:
		_report_worker_failure(
			"WORKER_SUBMIT_FAILURE",
			center,
			0,
			-1,
			"dedicated low-priority Thread.start failed error=%d" % start_error
		)
		return
	_stream_thread_started = true


func _stop_stream_thread() -> void:
	if not _stream_thread_started:
		return
	_stream_mutex.lock()
	_stream_state["exit"] = true
	_stream_mutex.unlock()
	_stream_semaphore.post()
	_stream_thread.wait_to_finish()
	_stream_thread_started = false


static func _low_priority_worker_loop(
	semaphore: Semaphore,
	mutex: Mutex,
	state: Dictionary
) -> void:
	var sampler_started_usec := Time.get_ticks_usec()
	var sampler = OPT_DATA.new()
	# The worker sampler is generation-only. Its inherited constructor currently
	# loads the save once; discard that copy immediately and then reuse this sampler
	# for the lifetime of the dedicated thread instead of reloading once per chunk.
	sampler.overrides.clear()
	mutex.lock()
	state["sampler_setup_usec"] = Time.get_ticks_usec() - sampler_started_usec
	state["ready"] = true
	mutex.unlock()

	while true:
		semaphore.wait()
		mutex.lock()
		var should_exit := bool(state.get("exit", false))
		var job: Dictionary = state.get("job", {})
		if not job.is_empty():
			state["job"] = {}
		mutex.unlock()
		if should_exit:
			break
		if job.is_empty():
			continue

		var result := _build_chunk_with_sampler(
			job.get("coord", Vector2i.ZERO),
			job.get("overrides", {}),
			int(job.get("revision", 0)),
			sampler,
			int(job.get("snapshot_usec", 0))
		)
		mutex.lock()
		state["result"] = {
			"coord": job.get("coord", Vector2i.ZERO),
			"revision": int(job.get("revision", 0)),
			"result": result,
		}
		state["busy"] = false
		mutex.unlock()


static func _collision_faces_from_mesh_data_local(mesh_data: Dictionary) -> PackedVector3Array:
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


static func _build_chunk_with_sampler(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	sampler,
	snapshot_usec: int = 0
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var cache_started_usec := Time.get_ticks_usec()
	var caches: Dictionary = OPT_GENERATION_CACHE.build(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
	var terrain_modifiers: PackedByteArray = caches.get("stage9_terrain_modifiers", PackedByteArray())
	var mesh_height := mini(
		OPT_DATA.OVERHAUL_WORLD_HEIGHT,
		OPT_STAGE2_RUNTIME._effective_mesh_height(coord, heights, overrides_snapshot) + 2
	)
	var mesh_started_usec := Time.get_ticks_usec()
	var expression_codes: Dictionary = OPT_STAGE12_CACHE.build_expression_codes(caches, sampler)
	var transition_codes: PackedByteArray = expression_codes.get("transition_codes", PackedByteArray())
	var hydrology_codes: PackedByteArray = expression_codes.get("hydrology_codes", PackedByteArray())
	var blocked_tree_columns: PackedInt32Array = OPT_STAGE11_RUNTIME._stage6_blocked_tree_columns(
		coord,
		caches,
		sampler
	)
	var mesh_data: Dictionary = OPT_STAGE12_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		12,
		mesh_height,
		OPT_DATA.SEA_LEVEL,
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
	mesh_data[OPT_COLLISION_FACES_KEY] = _collision_faces_from_mesh_data_local(mesh_data)
	var collision_data_usec := Time.get_ticks_usec() - collision_data_started_usec
	return {
		"coord": coord,
		"revision": revision,
		"mesh_data": mesh_data,
		"cache_usec": cache_usec,
		"mesh_usec": mesh_usec,
		"collision_data_usec": collision_data_usec,
		"snapshot_usec": snapshot_usec,
		"mesh_height": mesh_height,
		"compute_usec": Time.get_ticks_usec() - started_usec,
	}


func _dispatch_build_tasks() -> void:
	if not _stream_thread_started:
		super._dispatch_build_tasks()
		return
	if active_build_tasks.size() >= STREAM_WORKER_LIMIT or build_queue.is_empty():
		return

	while not build_queue.is_empty():
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

		var dispatch_started_usec := Time.get_ticks_usec()
		var snapshot_started_usec := Time.get_ticks_usec()
		var overrides_snapshot := _local_override_snapshot(coord)
		var snapshot_usec := Time.get_ticks_usec() - snapshot_started_usec
		_max_snapshot_usec = maxi(_max_snapshot_usec, snapshot_usec)
		_last_snapshot_count = overrides_snapshot.size()

		_stream_mutex.lock()
		var worker_busy := bool(_stream_state.get("busy", false))
		var pending_result: Dictionary = _stream_state.get("result", {})
		if worker_busy or not pending_result.is_empty():
			_stream_mutex.unlock()
			_queue_latest_revision(coord, true)
			return
		_stream_state["busy"] = true
		_stream_state["job"] = {
			"coord": coord,
			"revision": revision,
			"overrides": overrides_snapshot,
			"snapshot_usec": snapshot_usec,
		}
		_stream_mutex.unlock()

		active_build_tasks[coord] = {
			"revision": revision,
			"replacing": replacing,
			"queued_at_usec": dispatch_started_usec,
			"stall_reported": false,
			"snapshot_usec": snapshot_usec,
		}
		build_tasks_started += 1
		last_build_usec = maxi(last_build_usec, Time.get_ticks_usec() - dispatch_started_usec)
		_stream_semaphore.post()
		break


func _collect_completed_build_tasks() -> void:
	if not _stream_thread_started:
		super._collect_completed_build_tasks()
		return

	_stream_mutex.lock()
	var packet: Dictionary = _stream_state.get("result", {})
	if not packet.is_empty():
		_stream_state["result"] = {}
	_stream_mutex.unlock()

	if packet.is_empty():
		for coord_value: Variant in active_build_tasks.keys():
			var coord: Vector2i = coord_value
			var task_data: Dictionary = active_build_tasks.get(coord, {})
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
					"dedicated low-priority worker still incomplete after %.3f s"
					% (task_age_usec / 1000000.0)
				)
		return

	var coord: Vector2i = packet.get("coord", Vector2i.ZERO)
	var task_data: Dictionary = active_build_tasks.get(coord, {})
	var result: Dictionary = packet.get("result", {})
	var completed_revision := int(packet.get("revision", task_data.get("revision", 0)))
	var latest_revision := int(build_revisions.get(coord, 0))
	var replacing := bool(task_data.get("replacing", false))
	active_build_tasks.erase(coord)
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
			"dedicated low-priority worker completed without a chunk result"
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
		return

	build_apply_queue.append({
		"coord": coord,
		"revision": completed_revision,
		"replacing": replacing,
		"queued_at_usec": int(task_data.get("queued_at_usec", 0)),
		"result": result,
	})


func _pump_builds() -> void:
	var pump_start := Time.get_ticks_usec()
	var phase_started_usec := Time.get_ticks_usec()
	_collect_completed_build_tasks()
	_current_tick_summary["collect_usec"] = Time.get_ticks_usec() - phase_started_usec
	_stream_apply_happened_this_frame = false
	var applied_before := build_results_applied
	var apply_budget := 0 if not collision_add_queue.is_empty() else MAX_BUILD_APPLIES_PER_FRAME
	phase_started_usec = Time.get_ticks_usec()
	_apply_completed_builds(apply_budget)
	_current_tick_summary["apply_usec"] = Time.get_ticks_usec() - phase_started_usec
	_stream_apply_happened_this_frame = build_results_applied > applied_before
	phase_started_usec = Time.get_ticks_usec()
	_dispatch_build_tasks()
	_current_tick_summary["dispatch_usec"] = Time.get_ticks_usec() - phase_started_usec
	max_pump_usec = maxi(max_pump_usec, Time.get_ticks_usec() - pump_start)


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
		var apply_usec := Time.get_ticks_usec() - apply_started_usec
		last_apply_usec = maxi(last_apply_usec, apply_usec)
		if not applied:
			if not replacing:
				_queue_latest_revision(coord, true)
			continue

		last_face_count = int(mesh_data.get("face_count", 0))
		build_results_applied += 1
		applies += 1
		_accumulate_stream_report(result, apply_usec)


func _accumulate_stream_report(result: Dictionary, apply_usec: int) -> void:
	_stream_report_chunks += 1
	_stream_report_max_apply_usec = maxi(_stream_report_max_apply_usec, apply_usec)
	_stream_report_max_background_usec = maxi(
		_stream_report_max_background_usec,
		int(result.get("compute_usec", 0))
	)
	_stream_report_max_snapshot_usec = maxi(
		_stream_report_max_snapshot_usec,
		int(result.get("snapshot_usec", 0))
	)
	var now_usec := Time.get_ticks_usec()
	if _stream_report_started_usec <= 0:
		_stream_report_started_usec = now_usec
	if now_usec - _stream_report_started_usec < STREAM_REPORT_INTERVAL_USEC:
		return
	_record_stream_event(
		"STREAM_SUMMARY",
		"chunks=%d max_snapshot_ms=%.3f max_background_ms=%.3f max_apply_ms=%.3f active=%d build_queue=%d apply_queue=%d collision_queue=%d frame_hitches=%d max_frame_gap_ms=%.3f"
		% [
			_stream_report_chunks,
			_stream_report_max_snapshot_usec / 1000.0,
			_stream_report_max_background_usec / 1000.0,
			_stream_report_max_apply_usec / 1000.0,
			active_build_tasks.size(),
			build_queue.size(),
			build_apply_queue.size(),
			collision_add_queue.size(),
			_frame_hitch_count,
			_max_frame_gap_usec / 1000.0,
		]
	)
	_stream_report_started_usec = now_usec
	_stream_report_chunks = 0
	_stream_report_max_apply_usec = 0
	_stream_report_max_background_usec = 0
	_stream_report_max_snapshot_usec = 0


func _sort_queue() -> void:
	var forward := Vector2.ZERO
	if target is CharacterBody3D:
		var body := target as CharacterBody3D
		var horizontal_velocity := Vector2(body.velocity.x, body.velocity.z)
		if horizontal_velocity.length_squared() > 0.04:
			forward = horizontal_velocity.normalized()
	build_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_collision := needs_collision(a)
		var b_collision := needs_collision(b)
		if a_collision != b_collision:
			return a_collision
		var a_delta := a - center
		var b_delta := b - center
		var a_distance := a_delta.length_squared()
		var b_distance := b_delta.length_squared()
		if a_distance != b_distance:
			return a_distance < b_distance
		if forward != Vector2.ZERO:
			var a_forward := Vector2(a_delta.x, a_delta.y).dot(forward)
			var b_forward := Vector2(b_delta.x, b_delta.y).dot(forward)
			if not is_equal_approx(a_forward, b_forward):
				return a_forward > b_forward
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)


func _rebuild_override_index() -> void:
	_override_buckets.clear()
	_override_index_entries = 0
	for key_value: Variant in data.overrides.keys():
		var key := String(key_value)
		var parts := key.split(",")
		if parts.size() != 3:
			continue
		var x := int(parts[0])
		var z := int(parts[2])
		var bucket := Vector2i(
			floori(float(x) / float(CHUNK_SIZE)),
			floori(float(z) / float(CHUNK_SIZE))
		)
		var entries: Dictionary = _override_buckets.get(bucket, {})
		entries[key] = int(data.overrides.get(key_value, 0))
		_override_buckets[bucket] = entries
		_override_index_entries += 1


func _index_override_cell(cell: Vector3i, block_id: int) -> void:
	var bucket := Vector2i(
		floori(float(cell.x) / float(CHUNK_SIZE)),
		floori(float(cell.z) / float(CHUNK_SIZE))
	)
	var entries: Dictionary = _override_buckets.get(bucket, {})
	var key := data.cell_key(cell)
	var was_new := not entries.has(key)
	entries[key] = block_id
	_override_buckets[bucket] = entries
	if was_new:
		_override_index_entries += 1


func _local_override_snapshot(coord: Vector2i) -> Dictionary:
	var snapshot: Dictionary = {}
	var min_x := coord.x * CHUNK_SIZE - MESH_CACHE_PADDING
	var max_x := coord.x * CHUNK_SIZE + CHUNK_SIZE + MESH_CACHE_PADDING - 1
	var min_z := coord.y * CHUNK_SIZE - MESH_CACHE_PADDING
	var max_z := coord.y * CHUNK_SIZE + CHUNK_SIZE + MESH_CACHE_PADDING - 1
	var min_bucket_x := floori(float(min_x) / float(CHUNK_SIZE))
	var max_bucket_x := floori(float(max_x) / float(CHUNK_SIZE))
	var min_bucket_z := floori(float(min_z) / float(CHUNK_SIZE))
	var max_bucket_z := floori(float(max_z) / float(CHUNK_SIZE))
	for bucket_z in range(min_bucket_z, max_bucket_z + 1):
		for bucket_x in range(min_bucket_x, max_bucket_x + 1):
			var entries: Dictionary = _override_buckets.get(Vector2i(bucket_x, bucket_z), {})
			for key_value: Variant in entries.keys():
				var key := String(key_value)
				var parts := key.split(",")
				if parts.size() != 3:
					continue
				var x := int(parts[0])
				var z := int(parts[2])
				if x < min_x or x > max_x or z < min_z or z > max_z:
					continue
				snapshot[key] = int(entries.get(key_value, 0))
	return snapshot


func _record_frame_hitch(frame_gap_usec: int, previous: Dictionary) -> void:
	_record_stream_event(
		"FRAME_HITCH",
		"frame_ms=%.3f prev_tick_ms=%.3f prev_center_ms=%.3f prev_collect_ms=%.3f prev_apply_ms=%.3f prev_dispatch_ms=%.3f prev_collision_ms=%.3f prev_save_ms=%.3f active=%d build_queue=%d apply_queue=%d collision_queue=%d"
		% [
			frame_gap_usec / 1000.0,
			int(previous.get("tick_usec", 0)) / 1000.0,
			int(previous.get("center_usec", 0)) / 1000.0,
			int(previous.get("collect_usec", 0)) / 1000.0,
			int(previous.get("apply_usec", 0)) / 1000.0,
			int(previous.get("dispatch_usec", 0)) / 1000.0,
			int(previous.get("collision_pump_usec", 0)) / 1000.0,
			int(previous.get("save_usec", 0)) / 1000.0,
			active_build_tasks.size(),
			build_queue.size(),
			build_apply_queue.size(),
			collision_add_queue.size(),
		]
	)


func _record_stream_event(category: String, message: String) -> void:
	var capture := get_node_or_null("/root/DiagnosticLogCapture")
	if capture != null and capture.has_method("record_event"):
		capture.record_event(category, message)


# Permanent-gate helpers. Production uses the same methods above.
func _test_rebuild_override_index() -> void:
	_rebuild_override_index()


func _test_local_override_snapshot(coord: Vector2i) -> Dictionary:
	return _local_override_snapshot(coord)


static func _test_build_chunk_with_sampler(coord: Vector2i, overrides_snapshot: Dictionary, sampler) -> Dictionary:
	return _build_chunk_with_sampler(coord, overrides_snapshot, 1, sampler, 0)


func _test_stream_worker_limit() -> int:
	return STREAM_WORKER_LIMIT
