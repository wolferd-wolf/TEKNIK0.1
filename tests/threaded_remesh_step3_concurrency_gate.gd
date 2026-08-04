extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")
const SCREENSHOT_PATH := "res://artifacts/threaded-remesh-step3-concurrency.png"
const CHUNK_SIZE := 16
const BLOCK_AIR := 0
const BLOCK_STONE := 3
const TARGET_LOCAL := Vector3i(8, 8, 8)
const TARGET_WORLD := Vector3i(8, 8, 8)
const FULL_CHUNK_VERTEX_COUNT := 9216
const CONFLICT_REQUEST_COUNT := 32
const IDLE_FRAME_LIMIT := 360

var failures: Array[String] = []


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
	await _wait_frames(20)

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
	if not await _wait_for_idle(manager, "initial scene streaming"):
		_finish()
		return

	manager.clear_chunks()
	if not await _wait_for_idle(manager, "initial chunk clear"):
		_finish()
		return

	var chunk := CHUNK_SCRIPT.new()
	chunk.configure(Vector3i.ZERO)
	for local_y in range(CHUNK_SIZE):
		for local_z in range(CHUNK_SIZE):
			for local_x in range(CHUNK_SIZE):
				chunk.set_block(Vector3i(local_x, local_y, local_z), BLOCK_STONE)
	if not manager.register_chunk(Vector3i.ZERO, chunk):
		_fail("Failed to register dense concurrency chunk")
		_finish()
		return

	chunk.rebuild_mesh(Callable(manager, "get_block_world"))
	if not is_instance_valid(chunk.mesh_instance) or chunk.mesh_instance.mesh == null:
		_fail("Initial dense chunk mesh was not created")
		_finish()
		return
	if _vertex_count(chunk.mesh_instance.mesh) != FULL_CHUNK_VERTEX_COUNT:
		_fail(
			"Initial dense chunk expected %d vertices, got %d"
			% [FULL_CHUNK_VERTEX_COUNT, _vertex_count(chunk.mesh_instance.mesh)]
		)
	if not is_instance_valid(chunk.collision_shape) or chunk.collision_shape.shape == null:
		_fail("Initial dense chunk collision was not created")
	if not failures.is_empty():
		_finish()
		return

	var initial_mesh_id := chunk.mesh_instance.mesh.get_instance_id()
	if not manager.reset_remesh_diagnostics():
		_fail("Could not reset remesh diagnostics before conflict test")
		_finish()
		return

	var first_call_started_usec := Time.get_ticks_usec()
	if not manager.mine_block_world(TARGET_WORLD):
		_fail("Initial conflicting mine request returned false")
		_finish()
		return
	var first_queue_call_ms := (Time.get_ticks_usec() - first_call_started_usec) / 1000.0
	if manager.is_remesh_idle():
		_fail("Initial mine request completed synchronously")

	for _cycle in range(15):
		if not manager.set_block_world(TARGET_WORLD, BLOCK_STONE):
			_fail("Conflicting place request returned false")
			break
		if not manager.mine_block_world(TARGET_WORLD):
			_fail("Conflicting mine request returned false")
			break
	if not manager.set_block_world(TARGET_WORLD, BLOCK_STONE):
		_fail("Final conflicting place request returned false")

	if manager.get_block_world(TARGET_WORLD) != BLOCK_STONE:
		_fail("Final live voxel state was not stone before worker completion")
	if not await _wait_for_idle(manager, "conflicting same-chunk requests"):
		_finish()
		return

	var diagnostics: Dictionary = manager.get_remesh_diagnostics()
	var tasks_started := int(diagnostics.get("tasks_started", -1))
	var results_applied := int(diagnostics.get("results_applied", -1))
	var stale_results := int(diagnostics.get("stale_results_discarded", -1))
	var coalesced_requests := int(diagnostics.get("coalesced_requests", -1))
	if tasks_started != 2:
		_fail("Conflict test started %d worker tasks instead of 2" % tasks_started)
	if results_applied != 1:
		_fail("Conflict test applied %d results instead of only the latest one" % results_applied)
	if stale_results != 1:
		_fail("Conflict test discarded %d stale results instead of 1" % stale_results)
	if coalesced_requests != CONFLICT_REQUEST_COUNT - 1:
		_fail(
			"Conflict test coalesced %d requests instead of %d"
			% [coalesced_requests, CONFLICT_REQUEST_COUNT - 1]
		)
	if int(diagnostics.get("active_tasks", -1)) != 0:
		_fail("Conflict test left an active worker task")
	if int(diagnostics.get("pending_applies", -1)) != 0:
		_fail("Conflict test left a pending main-thread apply")

	if manager.get_block_world(TARGET_WORLD) != BLOCK_STONE:
		_fail("Final voxel state was overwritten by a stale result")
	if chunk.get_block(TARGET_LOCAL) != BLOCK_STONE:
		_fail("Chunk-local final voxel state was not stone")
	if not is_instance_valid(chunk.mesh_instance) or chunk.mesh_instance.mesh == null:
		_fail("Final concurrency mesh is missing")
	else:
		var final_vertex_count := _vertex_count(chunk.mesh_instance.mesh)
		if final_vertex_count != FULL_CHUNK_VERTEX_COUNT:
			_fail(
				"Final stone-state mesh expected %d vertices, got %d"
				% [FULL_CHUNK_VERTEX_COUNT, final_vertex_count]
			)
		if chunk.mesh_instance.mesh.get_instance_id() == initial_mesh_id:
			_fail("Final latest-state mesh resource was not replaced")
	if not is_instance_valid(chunk.collision_shape) or chunk.collision_shape.shape == null:
		_fail("Final latest-state collision is missing")

	player.global_position = Vector3(24.0, 24.0, 24.0)
	camera.global_position = Vector3(24.0, 24.0, 24.0)
	camera.look_at(Vector3(8.0, 8.0, 8.0), Vector3.UP)
	await _wait_frames(6)
	await _capture_screenshot()

	if failures.is_empty():
		print("THREADED_REMESH_STEP_3_CONCURRENCY_GATE_PASS")
		print("CONFLICT_REQUESTS=%d" % CONFLICT_REQUEST_COUNT)
		print("COALESCED_REQUESTS=%d" % coalesced_requests)
		print("STALE_RESULTS_DISCARDED=%d" % stale_results)
		print("WORKER_TASKS_STARTED=%d" % tasks_started)
		print("LATEST_RESULTS_APPLIED=%d" % results_applied)
		print("FINAL_BLOCK_ID=%d" % manager.get_block_world(TARGET_WORLD))
		print("FINAL_VERTEX_COUNT=%d" % _vertex_count(chunk.mesh_instance.mesh))
		print("FIRST_QUEUE_CALL_MS=%.3f" % first_queue_call_ms)
	_finish()


func _wait_for_idle(manager, context: String) -> bool:
	for _frame in range(IDLE_FRAME_LIMIT):
		await process_frame
		if manager.is_remesh_idle():
			return true
	_fail("Remesh queue did not become idle during %s" % context)
	return false


func _vertex_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return vertices.size()


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Concurrency screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail(
			"Concurrency screenshot dimensions were %dx%d"
			% [image.get_width(), image.get_height()]
		)
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Concurrency screenshot save failed with error %d" % save_error)
		return
	print(
		"THREADED_REMESH_STEP_3_SCREENSHOT=%s"
		% ProjectSettings.globalize_path(SCREENSHOT_PATH)
	)


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("THREADED_REMESH_STEP_3_CONCURRENCY_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
