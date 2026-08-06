extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/placement-step3.png"
const BLOCK_AIR := 0
const BLOCK_STONE := 3
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


func _wait_for_atomic_swap(manager, previous_count: int, context: String) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if int(manager.get_remesh_diagnostics().get("atomic_swaps", 0)) > previous_count and manager.is_remesh_idle():
			return true
	_fail("Atomic playable-world rebuild did not complete during %s" % context)
	return false


func _run_gate() -> void:
	if not InputMap.has_action("place_block"):
		_fail("place_block InputMap action is missing")
	elif InputMap.action_get_events("place_block").is_empty():
		_fail("place_block InputMap action has no desktop/headless binding")

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
		_fail("Placement gate scene nodes are missing")
		_finish()
		return
	if not manager.is_playable_world_port_active():
		_fail("Placement gate did not receive the single playable-world implementation")
		_finish()
		return
	if not player.has_method("get_inventory") or not player.has_method("select_inventory_slot"):
		_fail("Player inventory placement API is missing")
		_finish()
		return

	var inventory = player.get_inventory()
	if not inventory.add_item(BLOCK_STONE, 2):
		_fail("Failed to seed two stone blocks")
	if not player.select_inventory_slot(0):
		_fail("Failed to select seeded stone slot")

	player.set_physics_process(false)
	player.set_process(true)
	manager.refresh_streaming(Vector3(2.5, 20.0, 2.5))
	if not await _wait_for_world_ready(manager, "initial placement fixture"):
		_finish()
		return

	var surface_y := _find_surface_y(manager, 2, 2)
	if surface_y == -2147483648:
		_fail("No playable-world surface was found for placement")
		_finish()
		return
	var base_coord := Vector3i(2, surface_y, 2)
	var placement_coord := base_coord + Vector3i.UP
	if manager.get_block_world(placement_coord) != BLOCK_AIR:
		var clear_swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
		if not manager.mine_block_world(placement_coord):
			_fail("Could not clear playable-world placement fixture")
			_finish()
			return
		if not await _wait_for_atomic_swap(manager, clear_swaps, "placement fixture clear"):
			_finish()
			return

	player.global_position = Vector3(7.5, surface_y + 3.0, 2.5)
	await _aim_at_block(player, camera, base_coord)
	var target: Dictionary = player.get_block_target()
	if target.get("block_coord", Vector3i(9999, 9999, 9999)) != base_coord:
		_fail("Placement target mismatch: expected %s, got %s" % [base_coord, target.get("block_coord")])
		_finish()
		return
	if target.get("hit_face", Vector3i.ZERO) != Vector3i.UP:
		_fail("Placement fixture was not targeted on its top face")
		_finish()
		return
	if not player.can_place_block_at(placement_coord):
		_fail("Valid playable-world placement candidate was rejected")
		_finish()
		return

	var entry_before: Dictionary = manager.get_playable_world_chunk_entry(Vector2i.ZERO)
	var root_before := entry_before.get("root") as Node3D
	var swaps_before := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	Input.action_press("place_block", 1.0)
	await process_frame
	Input.action_release("place_block")
	if manager.get_block_world(placement_coord) != BLOCK_STONE:
		_fail("place_block action did not write stone to the playable world")
	if not await _wait_for_atomic_swap(manager, swaps_before, "InputMap placement"):
		_finish()
		return
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 1, "inventory after placement")
	var entry_after: Dictionary = manager.get_playable_world_chunk_entry(Vector2i.ZERO)
	var root_after := entry_after.get("root") as Node3D
	if not is_instance_valid(root_after) or root_after == root_before:
		_fail("Placement did not atomically replace the playable-world chunk root")
	if not is_instance_valid(entry_after.get("collision")):
		_fail("Placement replacement lost nearby collision")
	_assert_collision_ray(player, placement_coord, true, "placed block")

	var inventory_before_occupied: Array[Dictionary] = inventory.get_slots()
	if player.place_block_at(placement_coord):
		_fail("Occupied placement coordinate accepted a second block")
	if inventory.get_slots() != inventory_before_occupied:
		_fail("Occupied-placement rejection consumed inventory")

	var overlap_coord := Vector3i(7, surface_y + 3, 2)
	if manager.get_block_world(overlap_coord) != BLOCK_AIR:
		manager.set_block_world(overlap_coord, BLOCK_AIR)
	player.global_position = Vector3(7.5, surface_y + 3.0, 2.5)
	var inventory_before_overlap: Array[Dictionary] = inventory.get_slots()
	if player.can_place_block_at(overlap_coord):
		_fail("Capsule-overlapping coordinate was reported placeable: %s" % overlap_coord)
	if player.place_block_at(overlap_coord):
		_fail("Capsule-overlapping placement returned true")
	if manager.get_block_world(overlap_coord) != BLOCK_AIR:
		_fail("Capsule-overlap rejection modified the world")
	if inventory.get_slots() != inventory_before_overlap:
		_fail("Capsule-overlap rejection consumed inventory")

	var unloaded_coord := Vector3i(2048, 20, 2048)
	if manager.place_block_world(unloaded_coord, BLOCK_STONE):
		_fail("Placement into an unloaded playable-world chunk returned true")

	camera.global_position = Vector3(placement_coord) + Vector3(5.0, 4.0, 5.0)
	camera.look_at(Vector3(placement_coord) + Vector3.ONE * 0.5, Vector3.UP)
	await _wait_frames(8)
	await _capture_screenshot()

	if failures.is_empty():
		print("PLACEMENT_STEP_3_GATE_PASS")
		print("PLACEMENT_WORLD=playable_world_port.gd")
		print("PLACED_BLOCK_COORD=%s" % placement_coord)
		print("PLAYER_OVERLAP_REJECTED=%s" % overlap_coord)
		print("UNLOADED_PLACEMENT_REJECTED=%s" % unloaded_coord)
	_finish()


func _aim_at_block(player, camera: Camera3D, block_coord: Vector3i) -> void:
	var center := Vector3(block_coord) + Vector3.ONE * 0.5
	camera.global_position = center + Vector3(0.0, 3.5, 0.0)
	camera.look_at(center, Vector3.FORWARD)
	await _wait_frames(20)


func _assert_slot(slot: Dictionary, expected_block_id: int, expected_count: int, context: String) -> void:
	if int(slot.get("block_id", -1)) != expected_block_id or int(slot.get("count", -1)) != expected_count:
		_fail("%s expected %d/%d, got %s" % [context, expected_block_id, expected_count, slot])


func _assert_collision_ray(player, coord: Vector3i, expected_hit: bool, context: String) -> void:
	var world_3d: World3D = player.get_world_3d()
	if world_3d == null:
		_fail("World3D unavailable for %s" % context)
		return
	var center := Vector3(coord) + Vector3.ONE * 0.5
	var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 2.0, center - Vector3.UP * 2.0)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = world_3d.direct_space_state.intersect_ray(query)
	if expected_hit and hit.is_empty():
		_fail("Expected collision ray missed for %s" % context)
		return
	if not expected_hit and not hit.is_empty():
		_fail("Unexpected collision ray hit for %s" % context)
		return
	if hit.is_empty():
		return
	var inside := Vector3(hit["position"]) - Vector3(hit["normal"]) * 0.001
	var hit_coord := Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
	if hit_coord != coord:
		_fail("Collision ray for %s hit %s instead of %s" % [context, hit_coord, coord])


func _find_surface_y(manager, world_x: int, world_z: int) -> int:
	for world_y in range(29, -1, -1):
		if manager.get_block_world(Vector3i(world_x, world_y, world_z)) != BLOCK_AIR:
			return world_y
	return -2147483648


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Placement screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Placement screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if error != OK:
		_fail("Placement screenshot save failed with error %d" % error)
	else:
		print("PLACEMENT_STEP_3_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	Input.action_release("place_block")
	if failures.is_empty():
		quit(0)
	else:
		print("PLACEMENT_STEP_3_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
