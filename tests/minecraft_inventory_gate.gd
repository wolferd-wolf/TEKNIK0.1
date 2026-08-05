extends SceneTree

const INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/minecraft-inventory-step3.png"
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


func _assert_stack(stack: Dictionary, block_id: int, count: int, context: String) -> void:
	var actual_block_id := int(stack.get("block_id", -1))
	var actual_count := int(stack.get("count", -1))
	if actual_block_id != block_id or actual_count != count:
		_fail("%s expected %d/%d, got %d/%d" % [context, block_id, count, actual_block_id, actual_count])


func _validate_model() -> void:
	var inventory = INVENTORY_SCRIPT.new()
	if inventory.get_slot_count() != 36:
		_fail("Default inventory did not have 36 slots")
	if not inventory.add_item(BLOCK_STONE, 70):
		_fail("Could not seed model test")
	var held: Dictionary = inventory.take_from_slot(0)
	held = inventory.put_stack_into_slot(1, held)
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 64, "model merge target")
	_assert_stack(held, BLOCK_STONE, 6, "model merge remainder")


func _run_gate() -> void:
	_validate_model()
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load")
		_finish()
		return
	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(30)

	var player := main.get_node_or_null("Player")
	if player == null or not player.has_method("get_inventory_screen"):
		_fail("Inventory player or screen accessor is missing")
		_finish()
		return
	var inventory = player.get_inventory()
	var screen = player.get_inventory_screen()
	if inventory == null or screen == null:
		_fail("Inventory or screen is null")
		_finish()
		return

	if not inventory.add_item(BLOCK_STONE, 70):
		_fail("Could not seed stone stacks")
	if not inventory.add_item(BLOCK_DIRT, 5):
		_fail("Could not seed dirt stack")
	screen.open_inventory()
	await _wait_frames(3)

	screen.interact_slot_primary(0)
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 64, "primary full-stack pickup")
	_assert_stack(inventory.get_slot(0), BLOCK_AIR, 0, "picked-up source")

	screen.interact_slot_primary(1)
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 64, "primary merge target")
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 6, "primary merge remainder")

	screen.interact_slot_primary(2)
	_assert_stack(inventory.get_slot(2), BLOCK_STONE, 6, "primary swap destination")
	_assert_stack(screen.get_cursor_stack(), BLOCK_DIRT, 5, "primary swap cursor")

	screen.interact_slot_primary(9)
	_assert_stack(inventory.get_slot(9), BLOCK_DIRT, 5, "storage full-stack placement")
	_assert_stack(screen.get_cursor_stack(), BLOCK_AIR, 0, "cursor after storage placement")

	screen.interact_slot_secondary(9)
	_assert_stack(inventory.get_slot(9), BLOCK_DIRT, 2, "secondary split source")
	_assert_stack(screen.get_cursor_stack(), BLOCK_DIRT, 3, "secondary split cursor")

	screen.interact_slot_secondary(10)
	_assert_stack(inventory.get_slot(10), BLOCK_DIRT, 1, "secondary single placement")
	_assert_stack(screen.get_cursor_stack(), BLOCK_DIRT, 2, "single placement remainder")

	var long_press_button := screen.get_slot_button(10) as Button
	if long_press_button == null:
		_fail("Storage slot long-press button is missing")
	else:
		long_press_button.emit_signal("button_down")
		await _wait_frames(35)
		long_press_button.emit_signal("button_up")
		await _wait_frames(2)
		_assert_stack(inventory.get_slot(10), BLOCK_DIRT, 2, "touch long-press single placement")
		_assert_stack(screen.get_cursor_stack(), BLOCK_DIRT, 1, "touch long-press cursor remainder")

	screen.interact_slot_primary(11)
	_assert_stack(inventory.get_slot(11), BLOCK_DIRT, 1, "final cursor placement")
	_assert_stack(screen.get_cursor_stack(), BLOCK_AIR, 0, "empty final cursor")

	var storage_zero := screen.get_storage_slot_label(0) as Label
	var storage_one := screen.get_storage_slot_label(1) as Label
	if storage_zero == null or storage_zero.text != "DIRT x2":
		_fail("Storage label 1 did not refresh to DIRT x2")
	if storage_one == null or storage_one.text != "DIRT x2":
		_fail("Storage label 2 did not refresh to DIRT x2")
	if screen.get_cursor_label().text != "CARRIED: EMPTY x0":
		_fail("Cursor label did not refresh to empty")

	await _capture_screenshot()
	if failures.is_empty():
		print("MINECRAFT_INVENTORY_STEP_3_GATE_PASS")
		print("PRIMARY=pickup,place,merge,swap")
		print("SECONDARY=split-half,place-one")
		print("TOUCH_SECONDARY=0.45 second long press")
	_finish()


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Step 3 screenshot was empty")
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Step 3 screenshot save failed with error %d" % save_error)
		return
	print("MINECRAFT_INVENTORY_STEP_3_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("MINECRAFT_INVENTORY_STEP_3_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
