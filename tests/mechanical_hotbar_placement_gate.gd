extends SceneTree

# Verifies the actual player-facing flow Akila asked for: craft a
# mechanical item, select it in the hotbar, place it exactly like a normal
# block. Exercises the real production entry point (place_block_at) with a
# supplied coordinate instead of a live physics raycast -- get_block_target/
# place_targeted_block just resolve a coordinate and forward to
# place_block_at, so this is testing 100% real logic without fighting
# headless-physics-raycast timing, which playable_world_mining_port_gate.gd
# also avoids by talking to ChunkManager directly rather than through a
# simulated raycast.

const MAIN_SCENE := "res://scenes/main.tscn"
const MECHANICAL_DATA_SCRIPT := preload("res://scripts/world/mechanical_block_data.gd")

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
	await _wait_frames(48)

	var player = main.get_node_or_null("Player")
	var chunk_manager = main.get_node_or_null("ChunkManager")
	if player == null or chunk_manager == null:
		_fail("Player or ChunkManager missing from main scene")
		_finish()
		return
	if not player.has_method("craft_test_shaft_recipe") or not player.has_method("place_block_at"):
		_fail("Player is missing the mechanical crafting/placement methods under test")
		_finish()
		return

	# Craft: give the player the recipe's input, then craft.
	var inventory = player.get_inventory()
	inventory.add_item(player.TEST_MECH_RECIPE_INPUT_BLOCK_ID, player.TEST_MECH_RECIPE_INPUT_COUNT)
	if not player.craft_test_shaft_recipe():
		_fail("craft_test_shaft_recipe failed even with sufficient input items")
		_finish()
		return

	# Select whichever hotbar slot the crafted shaft landed in.
	var shaft_slot: int = inventory.find_first_slot(MECHANICAL_DATA_SCRIPT.MECH_SHAFT)
	if shaft_slot < 0:
		_fail("Crafted shaft is not present in any inventory slot")
		_finish()
		return
	if not player.select_inventory_slot(shaft_slot):
		_fail("select_inventory_slot failed for the shaft's slot")
		_finish()
		return

	# Place it exactly like a normal block: a coordinate a few blocks above
	# the player's own position, guaranteed air and guaranteed loaded.
	var place_cell := Vector3i(
		floori(player.global_position.x),
		floori(player.global_position.y) + 5,
		floori(player.global_position.z)
	)
	var count_before := int(inventory.get_slot(shaft_slot).get("count", 0))

	if not player.place_block_at(place_cell):
		_fail("place_block_at failed for the crafted shaft on an air cell")
		_finish()
		return
	if not chunk_manager.has_mechanical_block_world(place_cell):
		_fail("ChunkManager does not report the shaft as placed after place_block_at succeeded")
	var placed_entry: Dictionary = chunk_manager.get_mechanical_block_world(place_cell)
	if int(placed_entry.get("type_id", -1)) != MECHANICAL_DATA_SCRIPT.MECH_SHAFT:
		_fail("Placed block's type_id does not match MECH_SHAFT")

	var count_after := int(inventory.get_slot(shaft_slot).get("count", 0))
	if count_after != count_before - 1:
		_fail("Inventory count did not decrement by 1 on placement (before=%d after=%d)" % [count_before, count_after])

	# Regression: placing on a solid cell must fail and must not consume
	# inventory (same rollback-safety property normal blocks already have).
	var solid_cell := Vector3i(place_cell.x, place_cell.y - 20, place_cell.z)
	if player.place_block_at(solid_cell):
		_fail("place_block_at succeeded on a non-air cell")
	var count_after_rejected := int(inventory.get_slot(shaft_slot).get("count", 0))
	if count_after_rejected != count_after:
		_fail("Inventory was consumed even though placement on a solid cell was rejected")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("MECHANICAL_HOTBAR_PLACEMENT_GATE_PASS")
		quit(0)
	else:
		print("MECHANICAL_HOTBAR_PLACEMENT_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
