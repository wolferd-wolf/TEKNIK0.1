extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/inventory-crafting-step5.png"
const BLOCK_AIR := 0
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const CRAFT_ACTION := StringName("craft_test_recipe")
const CRAFT_KEYCODE := 67

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
	_validate_input_map()

	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(28)

	var player := main.get_node_or_null("Player")
	if player == null:
		_fail("Player node is missing")
		_finish()
		return
	if (
		not player.has_method("get_inventory")
		or not player.has_method("get_hotbar")
		or not player.has_method("craft_test_recipe")
	):
		_fail("Player does not expose inventory, hotbar, and test recipe state")
		_finish()
		return

	var inventory = player.get_inventory()
	var hotbar = player.get_hotbar()
	if inventory == null:
		_fail("Player inventory is null")
	if hotbar == null:
		_fail("Rendered inventory hotbar is null")
	if not failures.is_empty():
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)

	if not inventory.add_item(BLOCK_DIRT, 3):
		_fail("Failed to seed three dirt for the insufficient-ingredients case")
	await _wait_frames(4)
	_assert_rendered_slot(hotbar, 0, 3, BLOCK_DIRT)

	var insufficient_snapshot: Array[Dictionary] = inventory.get_slots()
	await _press_craft_action()
	if inventory.get_slots() != insufficient_snapshot:
		_fail("Insufficient-ingredients craft action mutated inventory")
	if inventory.get_item_count(BLOCK_DIRT) != 3:
		_fail("Insufficient craft changed dirt count from 3")
	if inventory.get_item_count(BLOCK_STONE) != 0:
		_fail("Insufficient craft produced stone")
	_assert_rendered_slot(hotbar, 0, 3, BLOCK_DIRT)
	_assert_rendered_slot(hotbar, 1, 0, BLOCK_AIR)

	if not inventory.add_item(BLOCK_DIRT, 1):
		_fail("Failed to add the fourth dirt for the successful recipe")
	if not inventory.add_item(BLOCK_STONE, 63):
		_fail("Failed to seed the matching 63-stone output stack")
	await _wait_frames(4)
	_assert_rendered_slot(hotbar, 0, 4, BLOCK_DIRT)
	_assert_rendered_slot(hotbar, 1, 63, BLOCK_STONE)

	var success_snapshot: Array[Dictionary] = inventory.get_slots()
	var dirt_before: int = inventory.get_item_count(BLOCK_DIRT)
	var stone_before: int = inventory.get_item_count(BLOCK_STONE)
	await _press_craft_action()

	if inventory.get_item_count(BLOCK_DIRT) != dirt_before - 4:
		_fail(
			"Successful craft consumed %d dirt instead of 4"
			% [dirt_before - inventory.get_item_count(BLOCK_DIRT)]
		)
	if inventory.get_item_count(BLOCK_STONE) != stone_before + 1:
		_fail(
			"Successful craft produced %d stone instead of 1"
			% [inventory.get_item_count(BLOCK_STONE) - stone_before]
		)
	_assert_slot(inventory.get_slot(0), BLOCK_AIR, 0, "depleted dirt slot")
	_assert_slot(inventory.get_slot(1), BLOCK_STONE, 64, "stacked recipe output")
	for slot_index in range(2, inventory.get_slot_count()):
		if inventory.get_slot(slot_index) != success_snapshot[slot_index]:
			_fail("Successful craft unexpectedly mutated slot %d" % slot_index)
	_assert_rendered_slot(hotbar, 0, 0, BLOCK_AIR)
	_assert_rendered_slot(hotbar, 1, 64, BLOCK_STONE)

	await _capture_screenshot()
	if failures.is_empty():
		print("INVENTORY_CRAFTING_STEP_5_GATE_PASS")
		print("CRAFT_ACTION=craft_test_recipe; physical key C")
		print("CRAFT_RECIPE=4 DIRT -> 1 STONE")
		print("CRAFT_INSUFFICIENT=3 DIRT; all 24 slots unchanged")
		print("CRAFT_SUCCESS=DIRT 4->0; STONE 63->64; rendered hotbar refreshed")
	_finish()


func _validate_input_map() -> void:
	if not InputMap.has_action(CRAFT_ACTION):
		_fail("craft_test_recipe InputMap action is missing")
		return
	var has_expected_key := false
	for event in InputMap.action_get_events(CRAFT_ACTION):
		if event is InputEventKey and event.physical_keycode == CRAFT_KEYCODE:
			has_expected_key = true
			break
	if not has_expected_key:
		_fail("craft_test_recipe is not bound to physical key C")


func _press_craft_action() -> void:
	Input.action_press(CRAFT_ACTION, 1.0)
	await process_frame
	Input.action_release(CRAFT_ACTION)
	await _wait_frames(5)


func _assert_slot(
	slot: Dictionary,
	expected_block_id: int,
	expected_count: int,
	context: String
) -> void:
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


func _assert_rendered_slot(hotbar, slot_index: int, expected_count: int, block_id: int) -> void:
	var count_label := hotbar.get_node_or_null(
		"HotbarRoot/Slots/Slot%d/Count" % (slot_index + 1)
	) as Label
	var swatch := hotbar.get_node_or_null(
		"HotbarRoot/Slots/Slot%d/Swatch" % (slot_index + 1)
	) as PanelContainer
	if count_label == null or swatch == null:
		_fail("Rendered widgets are missing for hotbar slot %d" % (slot_index + 1))
		return
	var has_item := block_id > 0 and expected_count > 0
	if count_label.text != ("x%d" % expected_count if has_item else ""):
		_fail("Rendered slot %d count expected x%d got %s"
			% [slot_index + 1, expected_count, count_label.text])
	if swatch.visible != has_item:
		_fail("Rendered slot %d swatch visibility expected %s" % [slot_index + 1, has_item])


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Inventory crafting screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail(
			"Inventory crafting screenshot dimensions were %dx%d"
			% [image.get_width(), image.get_height()]
		)
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Inventory crafting screenshot save failed with error %d" % save_error)
		return
	print("INVENTORY_CRAFTING_STEP_5_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("INVENTORY_CRAFTING_STEP_5_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
