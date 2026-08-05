extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const FRAME_LIMIT := 900
const BLOCK_AIR := 0
const BLOCK_DIRT := 2
const BLOCK_STONE := 3

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _wait_for_collision_ring(manager) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if manager.is_playable_world_collision_ring_ready():
			return true
	_fail("Playable-world collision ring did not become ready")
	return false


func _wait_for_swap(manager, previous_count: int) -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if int(manager.get_remesh_diagnostics().get("atomic_swaps", 0)) > previous_count:
			return true
	_fail("Playable-world edit did not complete an atomic mesh/collision swap")
	return false


func _run_gate() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("Main scene failed to load")
		_finish()
		return

	var main := packed.instantiate()
	root.add_child(main)
	await _wait_frames(2)

	var manager = main.get_node_or_null("ChunkManager")
	var player = main.get_node_or_null("Player")
	if manager == null or player == null:
		_fail("Main scene is missing the world adapter or player")
		_finish()
		return

	if not manager.is_playable_world_port_active():
		_fail("The single playable-world implementation is not active")
	if manager.expected_chunk_count() != 49:
		_fail("Single world no longer targets the 7x7 visual ring")
	if not await _wait_for_collision_ring(manager):
		_finish()
		return
	if manager.chunk_count() < 9 or manager.chunk_count() > 49:
		_fail("Unexpected startup chunk count: %d" % manager.chunk_count())

	var varied_heights := {}
	for sample in [Vector2i(2, 2), Vector2i(28, 7), Vector2i(-19, 31), Vector2i(47, -23)]:
		varied_heights[manager.get_playable_world_height(sample.x, sample.y)] = true
	if varied_heights.size() < 2:
		_fail("Deterministic terrain samples did not vary")

	var surface_y: int = manager.get_playable_world_height(2, 2)
	var mine_coord := Vector3i(2, surface_y, 2)
	var original_block: int = manager.get_block_world(mine_coord)
	if original_block == BLOCK_AIR:
		_fail("Controlled surface target was air")
		_finish()
		return

	var swaps := int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.mine_block_world(mine_coord):
		_fail("Valid surface mining was rejected")
	elif manager.get_block_world(mine_coord) != BLOCK_AIR:
		_fail("Mined block did not become air immediately")
	if not await _wait_for_swap(manager, swaps):
		_finish()
		return

	swaps = int(manager.get_remesh_diagnostics().get("atomic_swaps", 0))
	if not manager.place_block_world(mine_coord, BLOCK_STONE):
		_fail("Placement into the mined air cell was rejected")
	elif manager.get_block_world(mine_coord) != BLOCK_STONE:
		_fail("Placed stone was not stored")
	if not await _wait_for_swap(manager, swaps):
		_finish()
		return
	if manager.place_block_world(mine_coord, BLOCK_DIRT):
		_fail("Placement incorrectly overwrote an occupied voxel")

	if player.has_method("get_inventory"):
		var inventory = player.get_inventory()
		if inventory == null or inventory.get_slot_count() != 24 or inventory.get_max_stack_size() != 64:
			_fail("Shared 24-slot/64-stack inventory contract changed")
		else:
			var before := inventory.snapshot()
			if inventory.remove_item(BLOCK_DIRT, 1):
				_fail("Empty inventory unexpectedly removed dirt")
			if inventory.snapshot() != before:
				_fail("Failed inventory transaction mutated slots")
	else:
		_fail("Player no longer exposes the shared inventory")

	var destination := Vector3(96.5, 20.0, -72.5)
	manager.refresh_streaming(destination)
	if not await _wait_for_collision_ring(manager):
		_finish()
		return
	var expected_center := Vector3i(floori(destination.x / 12.0), 0, floori(destination.z / 12.0))
	if manager.last_center_chunk != expected_center:
		_fail("Streaming center did not follow the requested world position")
	if manager.chunk_count() > manager.expected_chunk_count():
		_fail("Streaming exceeded the bounded visual chunk count")

	var recovery := manager.get_recovery_position(destination)
	var terrain_y := manager.get_playable_world_height(floori(destination.x), floori(destination.z))
	if not is_equal_approx(recovery.y, terrain_y + 3.0):
		_fail("Recovery position is not terrain-relative")

	var diagnostics: Dictionary = manager.get_remesh_diagnostics()
	if int(diagnostics.get("atomic_swap_failures", 0)) != 0:
		_fail("Atomic world replacement reported a failure")

	if failures.is_empty():
		print("SINGLE_WORLD_GAMEPLAY_GATE_PASS")
		print("SINGLE_WORLD_CHUNKS=%d" % manager.chunk_count())
		print("SINGLE_WORLD_ATOMIC_SWAPS=%d" % int(diagnostics.get("atomic_swaps", 0)))
		print("SINGLE_WORLD_STREAM_CENTER=%s" % manager.last_center_chunk)

	_finish()


func _finish() -> void:
	quit(1 if not failures.is_empty() else 0)
