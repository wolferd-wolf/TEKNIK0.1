extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")
const SCREENSHOT_PATH := "res://artifacts/threaded-remesh-step2.png"
const BLOCK_AIR := 0
const BLOCK_STONE := 3
const CHUNK_SIZE := 16
const IDLE_FRAME_LIMIT := 360
const MAX_QUEUE_CALL_MS := 20.0

var failures: Array[String] = []
var scenario_summaries: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(24)

	var manager = main.get_node_or_null("ChunkManager")
	var player = main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null or player == null or camera == null:
		_fail("Main scene is missing manager, player, or camera")
		_finish()
		return

	player.set_process(false)
	player.set_physics_process(false)
	manager.set_process(false)
	manager.clear_chunks()
	if not await _wait_for_idle(manager, "initial clear"):
		_finish()
		return

	var single_chunks := [Vector3i(0, 0, 0)]
	var two_chunks := [Vector3i(2, 0, 0), Vector3i(3, 0, 0)]
	var three_chunks := [Vector3i(5, 0, 0), Vector3i(6, 0, 0), Vector3i(5, 0, 1)]
	_create_dense_group(manager, single_chunks)
	_create_dense_group(manager, two_chunks)
	_create_dense_group(manager, three_chunks)
	_rebuild_group_synchronously(manager, single_chunks)
	_rebuild_group_synchronously(manager, two_chunks)
	_rebuild_group_synchronously(manager, three_chunks)
	await _wait_frames(4)

	await _measure_scenario(
		manager,
		"single_chunk",
		Vector3i(8, 8, 8),
		single_chunks,
		1
	)
	await _measure_scenario(
		manager,
		"two_chunk_boundary",
		Vector3i(2 * CHUNK_SIZE + 15, 8, 8),
		two_chunks,
		2
	)
	await _measure_scenario(
		manager,
		"three_chunk_corner",
		Vector3i(5 * CHUNK_SIZE + 15, 8, 15),
		three_chunks,
		3
	)

	player.global_position = Vector3(84.0, 12.0, -12.0)
	camera.global_position = Vector3(84.0, 12.0, -12.0)
	camera.look_at(Vector3(88.0, 8.0, 8.0), Vector3.UP)
	await _wait_frames(8)
	await _capture_screenshot()

	if failures.is_empty():
		print("THREADED_REMESH_STEP_2_GATE_PASS")
		for summary in scenario_summaries:
			print(summary)
	_finish()


func _measure_scenario(
	manager,
	label: String,
	world_coord: Vector3i,
	affected_chunks: Array,
	expected_chunk_count: int
) -> void:
	if not manager.is_remesh_idle():
		_fail("%s started while remesh queue was not idle" % label)
		return
	if not manager.reset_remesh_diagnostics():
		_fail("%s could not reset diagnostics" % label)
		return

	var mesh_ids_before: Dictionary = {}
	for chunk_coord in affected_chunks:
		var chunk = manager.get_chunk(chunk_coord)
		if chunk == null or not is_instance_valid(chunk.mesh_instance):
			_fail("%s missing initial mesh for chunk %s" % [label, chunk_coord])
			return
		mesh_ids_before[chunk_coord] = chunk.mesh_instance.mesh.get_instance_id()

	var call_started_usec := Time.get_ticks_usec()
	if not manager.mine_block_world(world_coord):
		_fail("%s mine request returned false at %s" % [label, world_coord])
		return
	var queue_call_ms := (Time.get_ticks_usec() - call_started_usec) / 1000.0
	var was_asynchronous: bool = not manager.is_remesh_idle()
	var frame_result := await _wait_for_idle_with_frame_metrics(manager, label)
	if frame_result.is_empty():
		return

	if manager.get_block_world(world_coord) != BLOCK_AIR:
		_fail("%s target did not become air" % label)
	if not was_asynchronous:
		_fail("%s completed synchronously instead of leaving background work" % label)
	if queue_call_ms >= MAX_QUEUE_CALL_MS:
		_fail("%s queue call blocked for %.3f ms" % [label, queue_call_ms])

	for chunk_coord in affected_chunks:
		var chunk = manager.get_chunk(chunk_coord)
		if chunk == null or not is_instance_valid(chunk.mesh_instance):
			_fail("%s lost mesh instance for chunk %s" % [label, chunk_coord])
			continue
		if chunk.mesh_instance.mesh == null:
			_fail("%s produced null mesh for chunk %s" % [label, chunk_coord])
			continue
		if chunk.mesh_instance.mesh.get_instance_id() == mesh_ids_before[chunk_coord]:
			_fail("%s did not replace mesh for chunk %s" % [label, chunk_coord])
		if not is_instance_valid(chunk.collision_shape) or chunk.collision_shape.shape == null:
			_fail("%s lost collision for chunk %s" % [label, chunk_coord])

	var diagnostics: Dictionary = manager.get_remesh_diagnostics()
	var timing_samples: Array[Dictionary] = manager.get_remesh_timing_samples()
	if int(diagnostics.get("tasks_started", -1)) != expected_chunk_count:
		_fail(
			"%s started %d tasks instead of %d"
			% [label, int(diagnostics.get("tasks_started", -1)), expected_chunk_count]
		)
	if int(diagnostics.get("results_applied", -1)) != expected_chunk_count:
		_fail(
			"%s applied %d results instead of %d"
			% [label, int(diagnostics.get("results_applied", -1)), expected_chunk_count]
		)
	if timing_samples.is_empty():
		_fail("%s did not record queue timing" % label)
	elif int(timing_samples.back().get("rebuilt_chunk_count", -1)) != expected_chunk_count:
		_fail("%s timing sample reported wrong chunk count" % label)

	var max_frame_delta_ms := float(frame_result.get("max_frame_delta_ms", 0.0))
	var median_frame_delta_ms := float(frame_result.get("median_frame_delta_ms", 0.0))
	var max_background_ms := float(diagnostics.get("max_background_compute_ms", 0.0))
	var max_apply_ms := float(diagnostics.get("max_apply_ms", 0.0))
	var max_pump_ms := float(diagnostics.get("max_pump_ms", 0.0))
	if max_background_ms <= 0.0:
		_fail("%s did not report background compute time" % label)
	if max_pump_ms <= 0.0:
		_fail("%s did not report main-thread pump time" % label)

	scenario_summaries.append(
		"THREADED_SCENARIO=%s chunks=%d queue_call_ms=%.3f max_frame_delta_ms=%.3f median_frame_delta_ms=%.3f background_max_ms=%.3f apply_max_ms=%.3f pump_max_ms=%.3f"
		% [
			label,
			expected_chunk_count,
			queue_call_ms,
			max_frame_delta_ms,
			median_frame_delta_ms,
			max_background_ms,
			max_apply_ms,
			max_pump_ms,
		]
	)


func _wait_for_idle_with_frame_metrics(manager, label: String) -> Dictionary:
	var frame_deltas := PackedFloat64Array()
	var previous_usec := Time.get_ticks_usec()
	for _frame in range(IDLE_FRAME_LIMIT):
		await process_frame
		var now_usec := Time.get_ticks_usec()
		frame_deltas.append((now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		if manager.is_remesh_idle() and frame_deltas.size() >= 2:
			var sorted: Array = []
			var max_frame_delta_ms := 0.0
			for frame_delta in frame_deltas:
				sorted.append(frame_delta)
				max_frame_delta_ms = maxf(max_frame_delta_ms, frame_delta)
			sorted.sort()
			var median_index := floori(sorted.size() / 2.0)
			return {
				"max_frame_delta_ms": max_frame_delta_ms,
				"median_frame_delta_ms": float(sorted[median_index]),
				"frame_count": frame_deltas.size(),
			}
	_fail("%s remesh queue did not become idle" % label)
	return {}


func _wait_for_idle(manager, context: String) -> bool:
	for _frame in range(IDLE_FRAME_LIMIT):
		await process_frame
		if manager.is_remesh_idle():
			return true
	_fail("Remesh queue did not become idle during %s" % context)
	return false


func _create_dense_group(manager, chunk_coords: Array) -> void:
	for chunk_coord in chunk_coords:
		var chunk := CHUNK_SCRIPT.new()
		chunk.configure(chunk_coord)
		for local_y in range(CHUNK_SIZE):
			for local_z in range(CHUNK_SIZE):
				for local_x in range(CHUNK_SIZE):
					chunk.set_block(Vector3i(local_x, local_y, local_z), BLOCK_STONE)
		if not manager.register_chunk(chunk_coord, chunk):
			_fail("Failed to register dense timing chunk %s" % chunk_coord)


func _rebuild_group_synchronously(manager, chunk_coords: Array) -> void:
	for chunk_coord in chunk_coords:
		var chunk = manager.get_chunk(chunk_coord)
		chunk.rebuild_mesh(Callable(manager, "get_block_world"))


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Threaded remesh screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail(
			"Threaded remesh screenshot dimensions were %dx%d"
			% [image.get_width(), image.get_height()]
		)
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Threaded remesh screenshot save failed with error %d" % save_error)
		return
	print("THREADED_REMESH_STEP_2_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("THREADED_REMESH_STEP_2_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
