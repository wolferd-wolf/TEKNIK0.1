extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/mining-targeting-step1.png"
const WAIT_TIMEOUT_MSEC := 30000

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _wait_for_world_ready(manager, context: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		await process_frame
		if (
			manager.chunk_count() >= manager.expected_chunk_count()
			and manager.is_playable_world_collision_ring_ready()
			and manager.is_remesh_idle()
		):
			return true
	_fail("Playable world did not become ready during %s" % context)
	return false


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(2)

	var manager := main.get_node_or_null("ChunkManager")
	var player := main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null:
		_fail("ChunkManager node is missing")
	if player == null:
		_fail("Player node is missing")
	if camera == null:
		_fail("Player camera is missing")
	if not failures.is_empty():
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	var inspection_position := Vector3(0.5, 20.0, 0.5)
	manager.refresh_streaming(inspection_position)
	if not await _wait_for_world_ready(manager, "mining targeting fixture"):
		_finish()
		return

	var surface_y := _find_surface_y(manager, 0, 0)
	if surface_y == -2147483648:
		_fail("No solid surface block was found in the origin column")
		_finish()
		return

	var expected_coord := Vector3i(0, surface_y, 0)
	var target_center := Vector3(0.5, surface_y + 0.5, 0.5)
	player.global_position = Vector3(0.5, surface_y + 3.0, 0.5)
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.look_at(target_center, Vector3.FORWARD)
	await _wait_frames(20)

	var target: Dictionary = player.get_block_target()
	if target.is_empty():
		_fail("Camera ray did not return a solid voxel target")
	else:
		var actual_coord: Vector3i = target.get("block_coord", Vector3i.ZERO)
		var actual_face: Vector3i = target.get("hit_face", Vector3i.ZERO)
		if actual_coord != expected_coord:
			_fail("Target coordinate mismatch: expected %s, got %s" % [expected_coord, actual_coord])
		if actual_face != Vector3i.UP:
			_fail("Target face mismatch: expected %s, got %s" % [Vector3i.UP, actual_face])
		if manager.get_block_world(actual_coord) == 0:
			_fail("Targeting returned an air voxel at %s" % actual_coord)

	var highlight := player.get_target_highlight() as MeshInstance3D
	if highlight == null:
		_fail("Target highlight mesh was not created")
	elif not highlight.visible:
		_fail("Target highlight was not visible for a valid block target")
	else:
		var expected_highlight_position := Vector3(
			expected_coord.x + 0.5,
			expected_coord.y + 0.5,
			expected_coord.z + 0.5
		)
		if highlight.global_position.distance_to(expected_highlight_position) > 0.001:
			_fail(
				"Highlight position mismatch: expected %s, got %s"
				% [expected_highlight_position, highlight.global_position]
			)

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Targeting screenshot capture returned an empty image")
	else:
		var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
		if save_error != OK:
			_fail("Targeting screenshot save failed with error %d" % save_error)
		else:
			print("MINING_TARGETING_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))

	if failures.is_empty():
		print("MINING_TARGETING_STEP_1_PASS")
		print("TARGET_BLOCK_COORD=%s" % expected_coord)
		print("TARGET_HIT_FACE=%s" % Vector3i.UP)
	_finish()


func _find_surface_y(manager, world_x: int, world_z: int) -> int:
	for world_y in range(31, -17, -1):
		if manager.get_block_world(Vector3i(world_x, world_y, world_z)) != 0:
			return world_y
	return -2147483648


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("MINING_TARGETING_STEP_1_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)