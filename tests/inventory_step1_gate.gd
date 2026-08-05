extends SceneTree

const INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run_gate() -> void:
	var inventory = INVENTORY_SCRIPT.new()
	if inventory.get_slot_count() != 36:
		_fail("Default inventory had %d slots instead of 36" % inventory.get_slot_count())
	if inventory.get_hotbar_slot_count() != 9:
		_fail("Hotbar had %d slots instead of 9" % inventory.get_hotbar_slot_count())
	if inventory.get_storage_slot_count() != 27:
		_fail("Storage had %d slots instead of 27" % inventory.get_storage_slot_count())
	if inventory.get_max_stack_size() != 64:
		_fail("Max stack was %d instead of 64" % inventory.get_max_stack_size())
	if not inventory.is_empty() or inventory.is_full():
		_fail("New inventory empty/full state was invalid")

	if not inventory.add_item(BLOCK_STONE, 70):
		_fail("Stone stacking add failed")
	if not inventory.add_item(BLOCK_DIRT, 12):
		_fail("Dirt add failed")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 64, "stone slot 0")
	_assert_slot(inventory.get_slot(1), BLOCK_STONE, 6, "stone overflow")
	_assert_slot(inventory.get_slot(2), BLOCK_DIRT, 12, "dirt slot")

	var split := inventory.split_from_slot(0)
	_assert_slot(split, BLOCK_STONE, 32, "split cursor")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 32, "split remainder")
	var remainder := inventory.put_stack_into_slot(1, split)
	_assert_slot(inventory.get_slot(1), BLOCK_STONE, 38, "merged split")
	_assert_slot(remainder, 0, 0, "merge remainder")

	var swap_stack := inventory.take_from_slot(2)
	_assert_slot(swap_stack, BLOCK_DIRT, 12, "dirt pickup")
	var swapped_out := inventory.put_stack_into_slot(0, swap_stack)
	_assert_slot(inventory.get_slot(0), BLOCK_DIRT, 12, "swapped target")
	_assert_slot(swapped_out, BLOCK_STONE, 32, "swapped-out cursor")
	var returned := inventory.put_stack_into_slot(2, swapped_out)
	_assert_slot(inventory.get_slot(2), BLOCK_STONE, 32, "returned swapped stack")
	_assert_slot(returned, 0, 0, "returned cursor")

	var full_inventory = INVENTORY_SCRIPT.new()
	if not full_inventory.add_item(BLOCK_SAND, 36 * 64):
		_fail("Could not fill all 36 slots")
	if not full_inventory.is_full():
		_fail("36 full stacks did not report full")
	var before_failed_add: Array[Dictionary] = full_inventory.get_slots()
	if full_inventory.add_item(BLOCK_GRASS, 1):
		_fail("Full inventory accepted an extra item")
	if full_inventory.get_slots() != before_failed_add:
		_fail("Full-inventory rejection partially mutated slots")
	if not full_inventory.remove_from_slot(35, 64):
		_fail("Could not free final storage slot")
	if not full_inventory.add_item(BLOCK_GRASS, 1):
		_fail("Could not add into freed final storage slot")
	_assert_slot(full_inventory.get_slot(35), BLOCK_GRASS, 1, "freed storage refill")

	if failures.is_empty():
		print("INVENTORY_STEP_1_GATE_PASS")
		print("INVENTORY_DEFAULTS=36 slots; 9 hotbar + 27 storage; 64 max stack")
		print("INVENTORY_STACKS=add, merge, split, swap, full rejection, final-slot refill")
		quit(0)
	else:
		print("INVENTORY_STEP_1_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)


func _assert_slot(slot: Dictionary, expected_block_id: int, expected_count: int, context: String) -> void:
	var block_id := int(slot.get("block_id", -1))
	var count := int(slot.get("count", -1))
	if block_id != expected_block_id or count != expected_count:
		_fail("%s expected %d/%d, got %d/%d" % [context, expected_block_id, expected_count, block_id, count])
