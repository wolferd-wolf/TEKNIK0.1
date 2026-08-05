extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/minecraft-inventory-world-step5.png"
const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const MINE_TARGET := Vector3i(0, 20, 0)
const PLACE_BASE := Vector3i(4, 20, 0)
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


func _assert_slot(slot: Dictionary, block_id: int, count: int, context: String) -> void:
	var actual_block_id := int(slot.get("block_id", -1))
	var actual_count := int(slot.get("count", -1))
	if actual_block_id != block_id or actual_count != count:
		_fail("%s expected %d/%d, got %d/%d" % [context, block_id, count, actual_block_id, actual_count])


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load")
		_finish()
		return
	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(28)

	var manager := main.get_node_or_null("ChunkManager")
	var player := main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null or player == null or camera == null:
		_fail("World manager, player, or camera is missing")
		_finish()
		return
	if not player.has_method("get_inventory") or not player.has_method("select_inventory_slot"):
		_fail("Player inventory integration API is missing")
		_finish()
		return
	var inventory = player.get_inventory()
	if inventory == null or inventory.get_slot_count() != 36:
		_fail("Player does not use the 36-slot inventory")
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	player.global_position = Vector3(12.5, 20.0, 8.5)
	manager.refresh_streaming(Vector3(4.5, 20.5, 0.5))
	manager.set_process(false)
	await _wait_frames(14)

	await _create_controlled_block(manager, MINE_TARGET, BLOCK_DIRT)
	await _create_controlled_block(manager, PLACE_BASE, BLOCK_STONE)
	await _create_controlled_block(manager, PLACE_BASE + Vector3i.UP, BLOCK_AIR)
	await _create_controlled_block(manager, FULL_TARGET, BLOCK_GRASS)
	if not failures.is_empty():
		_finish()
		return

	await _aim_at_block(player, camera, MINE_TARGET)
	await _press_action("mine_block")
	if manager.get_block_world(MINE_TARGET) != BLOCK_AIR:
		_fail("Mining did not remove the controlled dirt block")
	_assert_slot(inventory.get_slot(0), BLOCK_DIRT, 1, "mined dirt pickup")
	if inventory.get_item_count(BLOCK_DIRT) != 1:
		_fail("Mining did not add exactly one dirt item")

	if not player.select_inventory_slot(0):
		_fail("Could not select mined dirt hotbar slot")
	await _aim_at_block(player, camera, PLACE_BASE)
	await _press_action("place_block")
	var placed_coord := PLACE_BASE + Vector3i.UP
	if manager.get_block_world(placed_coord) != BLOCK_DIRT:
		_fail("Placement did not use the selected mined dirt item")
	_assert_slot(inventory.get_slot(0), BLOCK_AIR, 0, "selected slot after placement")
	if inventory.get_item_count(BLOCK_DIRT) != 0:
		_fail("Placement did not consume exactly one selected item")

	if not inventory.add_item(BLOCK_STONE, 36 * 64):
		_fail("Could not fill all 36 inventory slots")
	if not inventory.is_full():
		_fail("36 full stacks did not report a full inventory")
	for slot_index in range(36):
		_assert_slot(inventory.get_slot(slot_index), BLOCK_STONE, 64, "full slot %d" % slot_index)
	var full_snapshot: Array[Dictionary] = inventory.get_slots()
	var target_chunk_coord = manager.world_to_chunk_coord(Vector3(FULL_TARGET) + Vector3.ONE * 0.5)
	var target_chunk = manager.get_chunk(target_chunk_coord)
	if target_chunk == null:
		_fail("Full-inventory target chunk is not loaded")
		_finish()
		return
	var mesh_before = target_chunk.mesh_instance.mesh
	var collision_before = target_chunk.collision_shape.shape

	await _aim_at_block(player, camera, FULL_TARGET)
	await _press_action("mine_block")
	if manager.get_block_world(FULL_TARGET) != BLOCK_GRASS:
		_fail("Full inventory did not block mining")
	if inventory.get_slots() != full_snapshot:
		_fail("Blocked mining mutated the full inventory")
	if target_chunk.mesh_instance.mesh != mesh_before:
		_fail("Blocked mining rebuilt the target mesh")
	if target_chunk.collision_shape.shape != collision_before:
		_fail("Blocked mining rebuilt target collision")

	if not inventory.remove_from_slot(35, 64):
		_fail("Could not free storage slot 35 for mining retry")
	await _aim_at_block(player, camera, FULL_TARGET)
	await _press_action("mine_block")
	if manager.get_block_world(FULL_TARGET) != BLOCK_AIR:
		_fail("Mining did not resume after storage capacity was freed")
	_assert_slot(inventory.get_slot(35), BLOCK_GRASS, 1, "retried grass pickup in final storage slot")

	var screen = player.get_inventory_screen()
	if screen != null:
		screen.open_inventory()
		await _wait_frames(3)
	await _capture_screenshot()
	if screen != null:
		screen.close_inventory()

	if failures.is_empty():
		print("MINECRAFT_INVENTORY_WORLD_STEP_5_GATE_PASS")
		print("MINING_PICKUP=DIRT block -> hotbar slot 0 count 1")
		print("PLACEMENT_CONSUMPTION=selected DIRT 1 -> air/0")
		print("FULL_INVENTORY=36x64; mining blocked atomically")
		print("MINING_RETRY=freed slot 35 -> GRASS count 1")
	_finish()


func _create_controlled_block(manager, coord: Vector3i, block_id: int) -> void:
	var existing: int = manager.get_block_world(coord)
	if existing != BLOCK_AIR:
		if not manager.mine_block_world(coord):
			_fail("Could not clear controlled coordinate %s" % coord)
			return
		await _wait_frames(5)
	if block_id == BLOCK_AIR:
		return
	if not manager.place_block_world(coord, block_id):
		_fail("Could not place controlled block %d at %s" % [block_id, coord])
		return
	await _wait_frames(6)


func _aim_at_block(player, camera: Camera3D, block_coord: Vector3i) -> void:
	var target_center := Vector3(block_coord) + Vector3.ONE * 0.5
	player.global_position = target_center + Vector3(0.0, 3.0, 0.0)
	player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.look_at(target_center, Vector3.FORWARD)
	await _wait_frames(16)
	var target: Dictionary = player.get_block_target()
	if target.is_empty():
		_fail("Camera did not acquire controlled target %s" % block_coord)
	elif target.get("block_coord", Vector3i.ZERO) != block_coord:
		_fail("Target mismatch: expected %s, got %s" % [block_coord, target.get("block_coord")])


func _press_action(action: StringName) -> void:
	Input.action_press(action, 1.0)
	await process_frame
	Input.action_release(action)
	await _wait_frames(9)


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("World-integration inventory screenshot was empty")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("World-integration screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("World-integration screenshot save failed with error %d" % save_error)
		return
	print("MINECRAFT_INVENTORY_WORLD_STEP_5_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("MINECRAFT_INVENTORY_WORLD_STEP_5_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
