extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const BLOCK_AIR := 0
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const FIRST_COLUMN := Vector2i(0, 0)
const SECOND_COLUMN := Vector2i(4, 0)
const EMPTY_COLUMN := Vector2i(8, 0)
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
		if (
			manager.chunk_count() >= manager.expected_chunk_count()
			and manager.is_playable_world_collision_ring_ready()
			and manager.is_remesh_idle()
		):
			return true
	_fail("Playable world did not become ready during %s" % context)
	return false


func _wait_for_atomic_swap(manager, previous_count: int, context: String) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if (
			int(manager.get_remesh_diagnostics().get("atomic_swaps", 0)) > previous_count
			and manager.is_remesh_idle()
		):
			return true
	_fail("Playable-world rebuild did not complete during %s" % context)
	return false


func _run_gate() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load")
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(2)

	var manager = main.get_node_or_null("ChunkManager")
	var player = main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null or player == null or camera == null:
		_fail("Placement integration scene nodes are missing")
		_finish()
		return
	if not manager.is_playable_world_port_active():
		_fail("Inventory placement did not receive the single playable-world implementation")
		_finish()
		return
	if not player.has_method("get_inventory") or not player.has_method("select_inventory_slot"):
		_fail("Player does not expose inventory placement controls")
		_finish()
		return

	var inventory = player.get_inventory()
	if inventory == null or inventory.get_slot_count() != 36:
		_fail("Runtime inventory does not use 36 slots")
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	player.global_position = Vector3(12.5, 20.0, 8.5)
	manager.refresh_streaming(Vector3(4.5, 20.5, 0.5))
	if not await _wait_for_world_ready(manager, "inventory placement startup"):
		_finish()
		return

	var first_base: Vector3i = await _prepare_natural_base(manager, FIRST_COLUMN)
	var second_base: Vector3i = await _prepare_natural_base(manager, SECOND_COLUMN)
	var empty_base: Vector3i = await _prepare_natural_base(manager, EMPTY_COLUMN)
	if not failures.is_empty():
		_finish()
		return

	if not inventory.add_item(BLOCK_STONE, 2):
		_fail("Could not seed two stone items")
	if not player.select_inventory_slot(0):
		_fail("Could not select hotbar slot 0")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 2, "seeded stone hotbar")

	var first_coord := first_base + Vector3i.UP
	if await _aim_at_block(player, camera, first_base):
		await _press_place_action(manager, true, "first inventory placement")
	if manager.get_block_world(first_coord) != BLOCK_STONE:
		_fail("First inventory placement did not place stone")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 1, "stone after first placement")

	var second_coord := second_base + Vector3i.UP
	if await _aim_at_block(player, camera, second_base):
		await _press_place_action(manager, true, "second inventory placement")
	if manager.get_block_world(second_coord) != BLOCK_STONE:
		_fail("Second inventory placement did not place stone")
	_assert_slot(inventory.get_slot(0), BLOCK_AIR, 0, "depleted stone hotbar")

	var empty_coord := empty_base + Vector3i.UP
	var world_before_empty: int = manager.get_block_world(empty_coord)
	var inventory_before_empty: Array[Dictionary] = inventory.get_slots()
	if await _aim_at_block(player, camera, empty_base):
		await _press_place_action(manager, false, "selected-empty-slot rejection")
	if world_before_empty != BLOCK_AIR or manager.get_block_world(empty_coord) != BLOCK_AIR:
		_fail("Selected-empty-slot placement changed the world")
	if inventory.get_slots() != inventory_before_empty:
		_fail("Selected-empty-slot placement mutated inventory")

	if not inventory.add_item(BLOCK_DIRT, 1):
		_fail("Could not seed one dirt item for retry")
	_assert_slot(inventory.get_slot(0), BLOCK_DIRT, 1, "seeded dirt retry")
	if await _aim_at_block(player, camera, empty_base):
		await _press_place_action(manager, true, "dirt placement retry")
	if manager.get_block_world(empty_coord) != BLOCK_DIRT:
		_fail("Retry did not place dirt from selected hotbar slot")
	_assert_slot(inventory.get_slot(0), BLOCK_AIR, 0, "depleted dirt retry")

	if failures.is_empty():
		print("INVENTORY_PLACEMENT_STEP_3_GATE_PASS")
		print("PLACEMENT_WORLD=playable_world_port.gd natural terrain fixtures")
		print("PLACEMENT_CONSUMPTION=STONE 2->1->0 in hotbar slot 0")
		print("PLACEMENT_EMPTY_SLOT=blocked with world and all 36 slots unchanged")
		print("PLACEMENT_RETRY=DIRT 1->0 from hotbar slot 0")
	_finish()


func _prepare_natural_base(manager, column: Vector2i) -> Vector3i:
	var surface_y: int = manager.get_playable_world_height(column.x, column.y)
	var base_coord := Vector3i(column.x, surface_y, column.y)
	var placement_coord := base_coord + Vector3i.UP
	if manager.get_block_world(base_coord) == BLOCK_AIR:
		_fail("Natural terrain base was air at %s" % base_coord)
		return base_coord
	if manager.get_block_world(placement_coord) != BLOCK_AIR:
		var swaps_before := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
		if not manager.mine_block_world(placement_coord):
			_fail("Could not clear natural placement cell at %s" % placement_coord)
			return base_coord
		await _wait_for_atomic_swap(manager, swaps_before, "natural fixture clear at %s" % placement_coord)
	return base_coord


func _aim_at_block(player, camera: Camera3D, block_coord: Vector3i) -> bool:
	var target_center := Vector3(block_coord) + Vector3.ONE * 0.5
	camera.global_position = target_center + Vector3(0.0, 3.5, 0.0)
	camera.look_at(target_center, Vector3.FORWARD)
	for _frame in range(120):
		await process_frame
		var target: Dictionary = player.get_block_target()
		if (
			not target.is_empty()
			and target.get("block_coord", Vector3i.ZERO) == block_coord
			and target.get("hit_face", Vector3i.ZERO) == Vector3i.UP
		):
			return true
	_fail("Camera did not acquire playable-world placement base %s" % block_coord)
	return false


func _press_place_action(manager, expect_swap: bool, context: String) -> void:
	var swaps_before := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	Input.action_press("place_block", 1.0)
	await process_frame
	Input.action_release("place_block")
	if expect_swap:
		await _wait_for_atomic_swap(manager, swaps_before, context)
	else:
		await _wait_frames(12)


func _assert_slot(slot: Dictionary, block_id: int, count: int, context: String) -> void:
	var actual_block_id := int(slot.get("block_id", -1))
	var actual_count := int(slot.get("count", -1))
	if actual_block_id != block_id or actual_count != count:
		_fail("%s expected %d/%d, got %d/%d" % [context, block_id, count, actual_block_id, actual_count])


func _finish() -> void:
	Input.action_release("place_block")
	if failures.is_empty():
		quit(0)
	else:
		print("INVENTORY_PLACEMENT_STEP_3_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
