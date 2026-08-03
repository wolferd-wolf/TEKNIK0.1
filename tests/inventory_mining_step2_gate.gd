extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/inventory-mining-step2.png"
const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_SAND := 4
const DIRT_TARGET := Vector3i(0, 20, 0)
const SAND_TARGET := Vector3i(4, 20, 0)
const FULL_TARGET := Vector3i(8, 20, 0)

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
	if not player.has_method("get_inventory"):
		_fail("Player does not expose the inventory data structure")
		_finish()
		return

	var inventory = player.get_inventory()
	if inventory == null:
		_fail("Player inventory is null")
		_finish()
		return
	if inventory.get_slot_count() != 24:
		_fail("Player inventory had %d slots instead of 24" % inventory.get_slot_count())
	if inventory.get_max_stack_size() != 64:
		_fail("Player inventory max stack was %d instead of 64" % inventory.get_max_stack_size())

	player.set_physics_process(false)
	player.set_process(true)
	manager.refresh_streaming(Vector3(4.5, 20.5, 0.5))
	await _wait_frames(12)

	if not manager.set_block_world(DIRT_TARGET, BLOCK_DIRT):
		_fail("Failed to create controlled dirt mining target")
	if not manager.set_block_world(SAND_TARGET, BLOCK_SAND):
		_fail("Failed to create controlled sand mining target")
	if not manager.set_block_world(FULL_TARGET, BLOCK_GRASS):
		_fail("Failed to create controlled full-inventory mining target")
	if not failures.is_empty():
		_finish()
		return
	await _wait_frames(8)

	if not inventory.add_item(BLOCK_DIRT, 63):
		_fail("Failed to prefill the matching dirt stack")
	await _aim_at_block(player, camera, DIRT_TARGET)
	await _press_mine_action()

	if manager.get_block_world(DIRT_TARGET) != BLOCK_AIR:
		_fail("Inventory-backed mining did not remove the dirt voxel")
	_assert_slot(inventory.get_slot(0), BLOCK_DIRT, 64, "matching dirt stack")
	_assert_slot(inventory.get_slot(1), BLOCK_AIR, 0, "slot after matching-stack fill")
	if inventory.get_item_count(BLOCK_DIRT) != 64:
		_fail("Dirt total was %d instead of 64 after mining" % inventory.get_item_count(BLOCK_DIRT))

	await _aim_at_block(player, camera, SAND_TARGET)
	await _press_mine_action()
	if manager.get_block_world(SAND_TARGET) != BLOCK_AIR:
		_fail("Inventory-backed mining did not remove the sand voxel")
	_assert_slot(inventory.get_slot(1), BLOCK_SAND, 1, "new sand slot")
	if inventory.get_item_count(BLOCK_SAND) != 1:
		_fail("Sand total was %d instead of 1 after mining" % inventory.get_item_count(BLOCK_SAND))

	if not inventory.add_item(BLOCK_SAND, 1471):
		_fail("Failed to fill the remaining 23 inventory slots")
	if not inventory.is_full():
		_fail("Inventory did not report full after filling all 24 slots")
	for slot_index in range(24):
		var expected_block := BLOCK_DIRT if slot_index == 0 else BLOCK_SAND
		_assert_slot(inventory.get_slot(slot_index), expected_block, 64, "full slot %d" % slot_index)

	var target_chunk_coord = manager.world_to_chunk_coord(Vector3(FULL_TARGET) + Vector3(0.5, 0.5, 0.5))
	var target_chunk = manager.get_chunk(target_chunk_coord)
	if target_chunk == null:
		_fail("Full-inventory target chunk is not loaded")
		_finish()
		return
	var mesh_before_blocked_mine = target_chunk.mesh_instance.mesh
	var collision_before_blocked_mine = target_chunk.collision_shape.shape
	var inventory_before_blocked_mine: Array[Dictionary] = inventory.get_slots()

	await _aim_at_block(player, camera, FULL_TARGET)
	await _press_mine_action()

	if manager.get_block_world(FULL_TARGET) != BLOCK_GRASS:
		_fail("Full-inventory mining removed the voxel instead of blocking mining")
	if inventory.get_slots() != inventory_before_blocked_mine:
		_fail("Full-inventory mining mutated inventory despite being blocked")
	if target_chunk.mesh_instance.mesh != mesh_before_blocked_mine:
		_fail("Full-inventory mining rebuilt the mesh despite being blocked")
	if target_chunk.collision_shape.shape != collision_before_blocked_mine:
		_fail("Full-inventory mining rebuilt collision despite being blocked")
	var blocked_target: Dictionary = player.get_block_target()
	if blocked_target.is_empty() or blocked_target.get("block_coord", Vector3i.ZERO) != FULL_TARGET:
		_fail("Blocked mining did not preserve the current voxel target")

	if not inventory.remove_from_slot(23, 64):
		_fail("Failed to free one complete inventory slot for retry")
	_assert_slot(inventory.get_slot(23), BLOCK_AIR, 0, "freed retry slot")
	await _aim_at_block(player, camera, FULL_TARGET)
	await _press_mine_action()

	if manager.get_block_world(FULL_TARGET) != BLOCK_AIR:
		_fail("Mining did not resume after inventory capacity was freed")
	_assert_slot(inventory.get_slot(23), BLOCK_GRASS, 1, "retried grass collection")
	if inventory.get_item_count(BLOCK_GRASS) != 1:
		_fail("Grass total was %d instead of 1 after retry" % inventory.get_item_count(BLOCK_GRASS))

	await _capture_screenshot()
	if failures.is_empty():
		print("INVENTORY_MINING_STEP_2_GATE_PASS")
		print("MINING_STACKING=DIRT 63+1 -> slot 0 count 64")
		print("MINING_NEW_SLOT=SAND -> slot 1 count 1")
		print("MINING_FULL_FALLBACK=BLOCKED; voxel, inventory, mesh, and collision unchanged")
		print("MINING_RETRY=freed slot 23 -> GRASS count 1")
	_finish()


func _aim_at_block(player, camera: Camera3D, block_coord: Vector3i) -> void:
	player.global_position = Vector3(block_coord.x + 0.5, block_coord.y + 3.0, block_coord.z + 0.5)
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.look_at(Vector3(block_coord) + Vector3.ONE * 0.5, Vector3.FORWARD)
	await _wait_frames(16)
	var target: Dictionary = player.get_block_target()
	if target.is_empty():
		_fail("Camera did not acquire controlled target %s" % block_coord)
	elif target.get("block_coord", Vector3i.ZERO) != block_coord:
		_fail("Target mismatch: expected %s, got %s" % [block_coord, target.get("block_coord")])


func _press_mine_action() -> void:
	Input.action_press("mine_block", 1.0)
	await process_frame
	Input.action_release("mine_block")
	await _wait_frames(8)


func _assert_slot(slot: Dictionary, expected_block_id: int, expected_count: int, context: String) -> void:
	if slot.is_empty():
		_fail("%s returned an empty slot dictionary" % context)
		return
	var actual_block_id := int(slot.get("block_id", -1))
	var actual_count := int(slot.get("count", -1))
	if actual_block_id != expected_block_id or actual_count != expected_count:
		_fail(
			"%s expected block/count %d/%d, got %d/%d"
			% [context, expected_block_id, expected_count, actual_block_id, actual_count]
		)


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Inventory mining screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Inventory mining screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Inventory mining screenshot save failed with error %d" % save_error)
		return
	print("INVENTORY_MINING_STEP_2_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("INVENTORY_MINING_STEP_2_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
