extends SceneTree

const INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/inventory-step1.png"
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4

var failures: Array[String] = []
var stacking_summary := ""
var removal_summary := ""
var full_summary := ""


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _run_gate() -> void:
	_validate_default_shape_and_queries()
	_validate_add_and_stacking()
	_validate_remove_and_empty_reset()
	_validate_full_inventory_atomic_failure()
	await _capture_world_screenshot()

	if failures.is_empty():
		print("INVENTORY_STEP_1_GATE_PASS")
		print("INVENTORY_DEFAULTS=24 slots,64 max stack")
		print("INVENTORY_STACKING=%s" % stacking_summary)
		print("INVENTORY_REMOVAL=%s" % removal_summary)
		print("INVENTORY_FULL_CASE=%s" % full_summary)
	_finish()


func _validate_default_shape_and_queries() -> void:
	var inventory = INVENTORY_SCRIPT.new()
	if inventory.get_slot_count() != 24:
		_fail("Default inventory had %d slots instead of 24" % inventory.get_slot_count())
	if inventory.get_max_stack_size() != 64:
		_fail("Default max stack was %d instead of 64" % inventory.get_max_stack_size())
	if not inventory.is_empty():
		_fail("New inventory was not empty")
	if inventory.is_full():
		_fail("New inventory incorrectly reported full")
	if inventory.get_item_count(BLOCK_STONE) != 0:
		_fail("New inventory reported a non-zero stone count")
	if inventory.find_first_slot(BLOCK_STONE) != -1:
		_fail("New inventory found a stone slot")
	if not inventory.get_slot(-1).is_empty() or not inventory.get_slot(24).is_empty():
		_fail("Out-of-range slot query did not return an empty dictionary")

	var slots: Array[Dictionary] = inventory.get_slots()
	if slots.size() != 24:
		_fail("Slot snapshot had %d entries instead of 24" % slots.size())
	for slot_index in range(slots.size()):
		_assert_slot(slots[slot_index], 0, 0, "initial slot %d" % slot_index)

	if inventory.add_item(0, 1):
		_fail("Air block ID was accepted as an inventory item")
	if inventory.add_item(BLOCK_STONE, 0):
		_fail("Zero-count add was accepted")
	if inventory.remove_item(BLOCK_STONE, 1):
		_fail("Removal from an empty inventory succeeded")


func _validate_add_and_stacking() -> void:
	var inventory = INVENTORY_SCRIPT.new()
	if not inventory.add_item(BLOCK_STONE, 40):
		_fail("Initial stone add failed")
	if not inventory.add_item(BLOCK_STONE, 30):
		_fail("Stone stacking add failed")
	if not inventory.add_item(BLOCK_DIRT, 12):
		_fail("Dirt add failed")

	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 64, "stacked slot 0")
	_assert_slot(inventory.get_slot(1), BLOCK_STONE, 6, "overflow slot 1")
	_assert_slot(inventory.get_slot(2), BLOCK_DIRT, 12, "new item slot 2")
	if inventory.get_item_count(BLOCK_STONE) != 70:
		_fail("Stone query returned %d instead of 70" % inventory.get_item_count(BLOCK_STONE))
	if inventory.get_item_count(BLOCK_DIRT) != 12:
		_fail("Dirt query returned %d instead of 12" % inventory.get_item_count(BLOCK_DIRT))
	if inventory.find_first_slot(BLOCK_STONE) != 0:
		_fail("First stone slot was not index 0")
	if inventory.find_first_slot(BLOCK_DIRT) != 2:
		_fail("First dirt slot was not index 2")
	if not inventory.has_item(BLOCK_STONE, 70):
		_fail("has_item rejected the exact stone total")
	if inventory.has_item(BLOCK_STONE, 71):
		_fail("has_item accepted more stone than stored")

	var detached_snapshot: Array[Dictionary] = inventory.get_slots()
	detached_snapshot[0]["count"] = 1
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 64, "snapshot isolation slot 0")
	stacking_summary = "stone 40+30 -> slots [3x64,3x6]; dirt 12 -> slot 2"


func _validate_remove_and_empty_reset() -> void:
	var inventory = INVENTORY_SCRIPT.new()
	inventory.add_item(BLOCK_STONE, 70)
	inventory.add_item(BLOCK_DIRT, 12)
	var before_failed_remove: Array[Dictionary] = inventory.get_slots()
	if inventory.remove_item(BLOCK_STONE, 71):
		_fail("Over-count stone removal succeeded")
	if inventory.get_slots() != before_failed_remove:
		_fail("Failed stone removal partially mutated inventory")

	if not inventory.remove_item(BLOCK_STONE, 5):
		_fail("Five-stone removal failed")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 64, "post-remove slot 0")
	_assert_slot(inventory.get_slot(1), BLOCK_STONE, 1, "post-remove slot 1")
	if not inventory.remove_item(BLOCK_STONE, 1):
		_fail("Final overflow stone removal failed")
	_assert_slot(inventory.get_slot(1), 0, 0, "emptied overflow slot")
	if not inventory.remove_from_slot(0, 4):
		_fail("Direct slot removal failed")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 60, "directly reduced slot 0")
	if inventory.remove_from_slot(0, 61):
		_fail("Direct over-count slot removal succeeded")
	_assert_slot(inventory.get_slot(0), BLOCK_STONE, 60, "unchanged after failed slot removal")
	if inventory.get_item_count(BLOCK_STONE) != 60:
		_fail("Stone total after removals was %d instead of 60" % inventory.get_item_count(BLOCK_STONE))
	removal_summary = "atomic over-remove rejected; overflow stack cleared to air/0; slot remove left 60"


func _validate_full_inventory_atomic_failure() -> void:
	var inventory = INVENTORY_SCRIPT.new(4, 2)
	var block_ids := [BLOCK_GRASS, BLOCK_DIRT, BLOCK_STONE, BLOCK_SAND]
	for block_id in block_ids:
		if not inventory.add_item(block_id, 2):
			_fail("Failed to fill compact inventory with block ID %d" % block_id)

	if not inventory.is_full():
		_fail("Four full compact slots did not report full")
	for slot_index in range(block_ids.size()):
		_assert_slot(
			inventory.get_slot(slot_index),
			block_ids[slot_index],
			2,
			"full slot %d" % slot_index
		)

	var before_failed_add: Array[Dictionary] = inventory.get_slots()
	if inventory.can_add_item(BLOCK_GRASS, 1):
		_fail("Full inventory reported capacity for grass")
	if inventory.add_item(BLOCK_GRASS, 1):
		_fail("Full inventory accepted an additional grass block")
	if inventory.get_slots() != before_failed_add:
		_fail("Failed full-inventory add partially mutated slots")
	if inventory.get_item_count(BLOCK_GRASS) != 2:
		_fail("Grass total changed after full-inventory rejection")

	if not inventory.remove_from_slot(1, 1):
		_fail("Could not free one dirt capacity in full inventory")
	if not inventory.can_add_item(BLOCK_DIRT, 1):
		_fail("Freed matching dirt capacity was not queryable")
	if not inventory.add_item(BLOCK_DIRT, 1):
		_fail("Add into freed matching dirt stack failed")
	_assert_slot(inventory.get_slot(1), BLOCK_DIRT, 2, "refilled dirt slot")
	full_summary = "4x2 slots full; extra add rejected atomically; freed matching capacity refilled"


func _assert_slot(
	slot: Dictionary,
	expected_block_id: int,
	expected_count: int,
	context: String
) -> void:
	if slot.is_empty():
		_fail("%s returned an empty dictionary" % context)
		return
	var actual_block_id := int(slot.get("block_id", -1))
	var actual_count := int(slot.get("count", -1))
	if actual_block_id != expected_block_id or actual_count != expected_count:
		_fail(
			"%s expected block/count %d/%d, got %d/%d"
			% [context, expected_block_id, expected_count, actual_block_id, actual_count]
		)


func _capture_world_screenshot() -> void:
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load for screenshot: %s" % MAIN_SCENE)
		return
	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(24)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Inventory Step 1 screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Inventory Step 1 screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Inventory Step 1 screenshot save failed with error %d" % save_error)
		return
	print("INVENTORY_STEP_1_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("INVENTORY_STEP_1_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
