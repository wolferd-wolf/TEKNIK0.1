extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/mining-step2.png"
const CHUNK_SIZE := 12
const BLOCK_AIR := 0
const FRAME_LIMIT := 900

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
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if manager.is_playable_world_collision_ring_ready() and manager.is_remesh_idle():
			return true
	_fail("Playable world did not become ready during %s" % context)
	return false


func _wait_for_atomic_swaps(manager, previous_count: int, expected_delta: int, context: String) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		var current := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
		if current >= previous_count + expected_delta and manager.is_remesh_idle():
			return true
	_fail("Atomic playable-world rebuild did not complete during %s" % context)
	return false


func _run_gate() -> void:
	if not InputMap.has_action("mine_block"):
		_fail("mine_block InputMap action is missing")
	elif InputMap.action_get_events("mine_block").is_empty():
		_fail("mine_block InputMap action has no desktop/headless binding")

	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return
	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(2)

	var manager = main.get_node_or_null("ChunkManager")
	var player = main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null or player == null or camera == null:
		_fail("Mining gate scene nodes are missing")
		_finish()
		return
	if not manager.is_playable_world_port_active():
		_fail("Mining gate did not receive the single playable-world implementation")
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	manager.refresh_streaming(Vector3(0.5, 20.0, 0.5))
	if not await _wait_for_world_ready(manager, "initial mining fixture"):
		_finish()
		return

	var surface_y := _find_surface_y(manager, 0, 0)
	if surface_y == -2147483648:
		_fail("No playable-world surface block was found for mining")
		_finish()
		return
	var target_coord := Vector3i(0, surface_y, 0)
	var original_block := int(manager.get_block_world(target_coord))
	var target_chunk := Vector2i(0, 0)
	var entry_before: Dictionary = manager.get_playable_world_chunk_entry(target_chunk)
	var root_before := entry_before.get("root") as Node3D
	if not is_instance_valid(root_before) or not is_instance_valid(entry_before.get("collision")):
		_fail("Playable-world mining fixture lacked mesh root or collision")
		_finish()
		return

	await _aim_at_block(player, camera, target_coord)
	var acquired: Dictionary = player.get_block_target()
	if acquired.get("block_coord", Vector3i(9999, 9999, 9999)) != target_coord:
		_fail("Mining target mismatch: expected %s, got %s" % [target_coord, acquired.get("block_coord")])
		_finish()
		return

	var swaps_before := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	Input.action_press("mine_block", 1.0)
	await process_frame
	Input.action_release("mine_block")
	if manager.get_block_world(target_coord) != BLOCK_AIR:
		_fail("mine_block action did not update playable-world data immediately")
	if not await _wait_for_atomic_swaps(manager, swaps_before, 1, "input mining"):
		_finish()
		return
	var entry_after: Dictionary = manager.get_playable_world_chunk_entry(target_chunk)
	var root_after := entry_after.get("root") as Node3D
	if not is_instance_valid(root_after) or root_after == root_before:
		_fail("Input mining did not atomically replace the playable-world chunk root")
	if not is_instance_valid(entry_after.get("collision")):
		_fail("Input mining replacement lost nearby collision")
	_assert_removed_surface_collision(player, target_coord)
	var next_target: Dictionary = player.get_block_target()
	if next_target.get("block_coord", Vector3i(9999, 9999, 9999)) == target_coord:
		_fail("Camera continued targeting the removed playable-world block")

	await _test_boundary_neighbor_rebuild(manager)
	await _capture_screenshot()

	if failures.is_empty():
		print("MINING_STEP_2_GATE_PASS")
		print("MINING_WORLD=playable_world_port.gd")
		print("MINED_BLOCK_COORD=%s" % target_coord)
		print("MINED_BLOCK_ORIGINAL_ID=%d" % original_block)
	_finish()


func _test_boundary_neighbor_rebuild(manager) -> void:
	var boundary_y := _find_shared_boundary_y(manager, CHUNK_SIZE - 1, CHUNK_SIZE, 0)
	if boundary_y == -2147483648:
		_fail("No shared playable-world boundary was found at x=%d/%d" % [CHUNK_SIZE - 1, CHUNK_SIZE])
		return
	var target := Vector3i(CHUNK_SIZE - 1, boundary_y, 0)
	var neighbor := Vector3i(CHUNK_SIZE, boundary_y, 0)
	var left_coord := Vector2i(0, 0)
	var right_coord := Vector2i(1, 0)
	var left_before := manager.get_playable_world_chunk_entry(left_coord).get("root") as Node3D
	var right_before := manager.get_playable_world_chunk_entry(right_coord).get("root") as Node3D
	if not is_instance_valid(left_before) or not is_instance_valid(right_before):
		_fail("Playable-world boundary chunk roots were unavailable")
		return
	var original_block := int(manager.get_block_world(target))
	var swaps_before := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.mine_block_world(target):
		_fail("Playable-world boundary mining returned false at %s" % target)
		return
	if not await _wait_for_atomic_swaps(manager, swaps_before, 2, "cross-chunk boundary mining"):
		return
	var left_after := manager.get_playable_world_chunk_entry(left_coord).get("root") as Node3D
	var right_after := manager.get_playable_world_chunk_entry(right_coord).get("root") as Node3D
	if left_after == left_before:
		_fail("Boundary mining did not rebuild the target playable-world chunk")
	if right_after == right_before:
		_fail("Boundary mining did not rebuild the adjacent playable-world chunk")
	if manager.get_block_world(target) != BLOCK_AIR:
		_fail("Boundary target remained solid after mining")
	if manager.get_block_world(neighbor) == BLOCK_AIR:
		_fail("Boundary neighbor was unexpectedly removed")
	if not manager.set_block_world(target, original_block):
		_fail("Could not restore boundary fixture after mining")
	else:
		var restore_before := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
		await _wait_for_atomic_swaps(manager, restore_before, 2, "boundary fixture restoration")
	if failures.is_empty():
		print("PLAYABLE_BOUNDARY_REBUILD_PASS target=%s neighbor=%s" % [target, neighbor])


func _aim_at_block(player, camera: Camera3D, block_coord: Vector3i) -> void:
	var center := Vector3(block_coord) + Vector3.ONE * 0.5
	player.global_position = center + Vector3(0.0, 3.0, 0.0)
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.look_at(center, Vector3.FORWARD)
	await _wait_frames(20)


func _assert_removed_surface_collision(player, removed_coord: Vector3i) -> void:
	var world_3d: World3D = player.get_world_3d()
	if world_3d == null:
		_fail("World3D was unavailable for mined collision validation")
		return
	var center := Vector3(removed_coord) + Vector3.ONE * 0.5
	var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 2.0, center - Vector3.UP * 3.0)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_fail("Mining removed all underlying terrain collision")
		return
	var inside := Vector3(hit["position"]) - Vector3(hit["normal"]) * 0.001
	var hit_coord := Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
	if hit_coord == removed_coord:
		_fail("Collision ray still hit the removed block at %s" % removed_coord)


func _find_surface_y(manager, world_x: int, world_z: int) -> int:
	for world_y in range(29, -1, -1):
		if manager.get_block_world(Vector3i(world_x, world_y, world_z)) != BLOCK_AIR:
			return world_y
	return -2147483648


func _find_shared_boundary_y(manager, left_x: int, right_x: int, world_z: int) -> int:
	for world_y in range(29, -1, -1):
		if (
			manager.get_block_world(Vector3i(left_x, world_y, world_z)) != BLOCK_AIR
			and manager.get_block_world(Vector3i(right_x, world_y, world_z)) != BLOCK_AIR
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
	var error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if error != OK:
		_fail("Mining screenshot save failed with error %d" % error)
	else:
		print("MINING_STEP_2_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	Input.action_release("mine_block")
	if failures.is_empty():
		quit(0)
	else:
		print("MINING_STEP_2_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
