extends SceneTree

const INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")
const BLOCK_AIR := 0
const BLOCK_DIRT := 2
const BLOCK_STONE := 3

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _assert_stack(stack: Dictionary, block_id: int, count: int, context: String) -> void:
	var actual_block_id := int(stack.get("block_id", -1))
	var actual_count := int(stack.get("count", -1))
	if actual_block_id != block_id or actual_count != count:
		_fail("%s expected %d/%d, got %d/%d" % [context, block_id, count, actual_block_id, actual_count])


func _run_gate() -> void:
	var inventory = INVENTORY_SCRIPT.new()
	if inventory.get_slot_count() != 36:
		_fail("Default inventory had %d slots instead of 36" % inventory.get_slot_count())
	if inventory.get_hotbar_slot_count() != 9:
		_fail("Hotbar count was %d instead of 9" % inventory.get_hotbar_slot_count())
	if inventory.get_storage_slot_count() != 27:
		_fail("Storage count was %d instead of 27" % inventory.get_storage_slot_count())
	if inventory.get_max_stack_size() != 64:
		_fail("Max stack was %d instead of 64" % inventory.get_max_stack_size())

	if not inventory.add_item(BLOCK_STONE, 70):
		_fail("Could not seed 70 stone")
	_assert_stack(inventory.get_slot(0), BLOCK_STONE, 64, "initial stone slot 0")
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 6, "initial stone slot 1")

	var held: Dictionary = inventory.take_from_slot(0, 10)
	_assert_stack(held, BLOCK_STONE, 10, "ten-item pickup")
	_assert_stack(inventory.get_slot(0), BLOCK_STONE, 54, "source after pickup")
	held = inventory.put_stack_into_slot(1, held)
	_assert_stack(held, BLOCK_AIR, 0, "merge remainder")
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 16, "merged destination")

	held = inventory.split_from_slot(1)
	_assert_stack(held, BLOCK_STONE, 8, "split pickup")
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 8, "split remainder")
	held = inventory.put_stack_into_slot(2, held, true)
	_assert_stack(inventory.get_slot(2), BLOCK_STONE, 1, "single-item place")
	_assert_stack(held, BLOCK_STONE, 7, "single-item cursor remainder")
	held = inventory.put_stack_into_slot(3, held)
	_assert_stack(held, BLOCK_AIR, 0, "full-stack empty placement remainder")
	_assert_stack(inventory.get_slot(3), BLOCK_STONE, 7, "full-stack empty placement")

	if not inventory.add_item(BLOCK_DIRT, 5):
		_fail("Could not seed dirt stack")
	var dirt_slot := inventory.find_first_slot(BLOCK_DIRT)
	if dirt_slot < 0:
		_fail("Dirt slot was not found")
	else:
		held = inventory.take_from_slot(dirt_slot)
		_assert_stack(held, BLOCK_DIRT, 5, "dirt pickup")
		held = inventory.put_stack_into_slot(0, held)
		_assert_stack(inventory.get_slot(0), BLOCK_DIRT, 5, "swap destination")
		_assert_stack(held, BLOCK_STONE, 54, "swap cursor")
		held = inventory.put_stack_into_slot(5, held)
		_assert_stack(held, BLOCK_AIR, 0, "swap cursor returned")
		_assert_stack(inventory.get_slot(5), BLOCK_STONE, 54, "swapped stone placement")

	var snapshot: Array[Dictionary] = inventory.get_slots()
	var invalid_remainder: Dictionary = inventory.put_stack_into_slot(99, {"block_id": BLOCK_DIRT, "count": 4})
	_assert_stack(invalid_remainder, BLOCK_DIRT, 4, "invalid-slot remainder")
	if inventory.get_slots() != snapshot:
		_fail("Invalid-slot deposit mutated inventory")
	_assert_stack(inventory.take_from_slot(-1), BLOCK_AIR, 0, "invalid pickup")

	if failures.is_empty():
		print("MINECRAFT_INVENTORY_STEP_1_GATE_PASS")
		print("INVENTORY_SHAPE=9 hotbar + 27 storage = 36")
		print("STACK_LIMIT=64")
		print("STACK_OPERATIONS=pickup,merge,swap,split,single-place")
		quit(0)
	else:
		print("MINECRAFT_INVENTORY_STEP_1_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
