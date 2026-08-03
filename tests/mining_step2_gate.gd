extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/mining-step2.png"

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
	if not InputMap.has_action("mine_block"):
		_fail("mine_block InputMap action is missing")
	elif InputMap.action_get_events("mine_block").is_empty():
		_fail("mine_block InputMap action has no desktop test binding")

	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(24)

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
	await _wait_frames(12)

	var surface_y := _find_surface_y(manager, 0, 0)
	if surface_y == -2147483648:
		_fail("No solid surface block was found for mining")
		_finish()
		return

	var target_coord := Vector3i(0, surface_y, 0)
	var original_block: int = manager.get_block_world(target_coord)
	if original_block == 0:
		_fail("Mining target unexpectedly contained air")
		_finish()
		return

	var target_chunk_coord = manager.world_to_chunk_coord(Vector3(target_coord) + Vector3(0.5, 0.5, 0.5))
	var target_chunk = manager.get_chunk(target_chunk_coord)
	var mesh_before = target_chunk.mesh_instance.mesh
	var collision_before = target_chunk.collision_shape.shape

	var target_center := Vector3(0.5, surface_y + 0.5, 0.5)
	player.global_position = Vector3(0.5, surface_y + 3.0, 0.5)
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.look_at(target_center, Vector3.FORWARD)
	await _wait_frames(20)

	var target: Dictionary = player.get_block_target()
	if target.is_empty():
		_fail("Camera did not acquire a block before mining")
	elif target.get("block_coord", Vector3i.ZERO) != target_coord:
		_fail("Mining target mismatch: expected %s, got %s" % [target_coord, target.get("block_coord")])

	Input.action_press("mine_block", 1.0)
	await process_frame
	Input.action_release("mine_block")
	await _wait_frames(12)

	if manager.get_block_world(target_coord) != 0:
		_fail("mine_block action did not set %s to air" % target_coord)
	if target_chunk.mesh_instance.mesh == null:
		_fail("Affected chunk mesh became null after mining")
	elif target_chunk.mesh_instance.mesh == mesh_before:
		_fail("Affected chunk mesh resource was not rebuilt after mining")
	if target_chunk.collision_shape.shape == null:
		_fail("Affected chunk collision became null after mining a surface block")
	elif target_chunk.collision_shape.shape == collision_before:
		_fail("Affected chunk collision resource was not rebuilt after mining")

	var next_target: Dictionary = player.get_block_target()
	if not next_target.is_empty() and next_target.get("block_coord", Vector3i.ZERO) == target_coord:
		_fail("Camera continued targeting the removed block")

	await _test_boundary_neighbor_remesh(manager)
	await _capture_screenshot()

	if failures.is_empty():
		print("MINING_STEP_2_GATE_PASS")
		print("MINED_BLOCK_COORD=%s" % target_coord)
		print("MINED_BLOCK_ORIGINAL_ID=%d" % original_block)
	_finish()


func _test_boundary_neighbor_remesh(manager) -> void:
	var boundary_y := _find_shared_boundary_y(manager, 15, 16, 0)
	if boundary_y == -2147483648:
		_fail("No shared solid boundary block was found at world x=15/16")
		return

	var boundary_coord := Vector3i(15, boundary_y, 0)
	var neighbor_coord := Vector3i(16, boundary_y, 0)
	var neighbor_chunk_coord = manager.world_to_chunk_coord(Vector3(neighbor_coord) + Vector3(0.5, 0.5, 0.5))
	var neighbor_chunk = manager.get_chunk(neighbor_chunk_coord)
	if neighbor_chunk == null:
		_fail("Neighbor chunk was not loaded for boundary mining test")
		return

	var neighbor_mesh_before = neighbor_chunk.mesh_instance.mesh
	if not manager.mine_block_world(boundary_coord):
		_fail("Boundary block mining returned false at %s" % boundary_coord)
		return
	await _wait_frames(6)

	if manager.get_block_world(boundary_coord) != 0:
		_fail("Boundary block remained solid after mining")
	if manager.get_block_world(neighbor_coord) == 0:
		_fail("Boundary test neighbor block was unexpectedly air")
	if neighbor_chunk.mesh_instance.mesh == neighbor_mesh_before:
		_fail("Adjacent chunk mesh was not rebuilt after boundary mining")
	else:
		print("BOUNDARY_NEIGHBOR_REMESH_PASS coord=%s neighbor=%s" % [boundary_coord, neighbor_coord])


func _find_surface_y(manager, world_x: int, world_z: int) -> int:
	for world_y in range(31, -17, -1):
		if manager.get_block_world(Vector3i(world_x, world_y, world_z)) != 0:
			return world_y
	return -2147483648


func _find_shared_boundary_y(manager, left_x: int, right_x: int, world_z: int) -> int:
	for world_y in range(31, -17, -1):
		if (
			manager.get_block_world(Vector3i(left_x, world_y, world_z)) != 0
			and manager.get_block_world(Vector3i(right_x, world_y, world_z)) != 0
		):
			return world_y
	return -2147483648


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Mining screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Mining screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Mining screenshot save failed with error %d" % save_error)
		return
	print("MINING_STEP_2_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("MINING_STEP_2_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
