extends SceneTree

const INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/minecraft-inventory-step5.png"
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
		_fail("Default inventory had %d slots instead of 36" % inventory.get_slot_count())
	if inventory.get_hotbar_slot_count() != 9:
		_fail("Inventory hotbar count was not 9")
	if inventory.get_storage_slot_count() != 27:
		_fail("Inventory storage count was not 27")
	if inventory.get_max_stack_size() != 64:
		_fail("Inventory max stack was not 64")
	if not inventory.add_item(BLOCK_STONE, 70):
		_fail("Could not seed model stacking")
	var held: Dictionary = inventory.take_from_slot(0, 10)
	held = inventory.put_stack_into_slot(1, held)
	_assert_stack(held, BLOCK_AIR, 0, "model merge remainder")
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 16, "model merge target")
	held = inventory.split_from_slot(1)
	_assert_stack(held, BLOCK_STONE, 8, "model half pickup")
	held = inventory.put_stack_into_slot(2, held, true)
	_assert_stack(inventory.get_slot(2), BLOCK_STONE, 1, "model one-item placement")
	_assert_stack(held, BLOCK_STONE, 7, "model one-item remainder")


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
	if (
		player == null
		or not player.has_method("get_inventory_screen")
		or not player.has_method("is_inventory_input_locked")
	):
		_fail("Player inventory screen or input-lock API is missing")
		_finish()
		return
	var inventory = player.get_inventory()
	var screen = player.get_inventory_screen()
	var hotbar = player.get_hotbar()
	if inventory == null or screen == null or hotbar == null:
		_fail("Runtime inventory, screen, or hotbar is null")
		_finish()
		return
	if screen.get_storage_slot_count() != 27 or screen.get_hotbar_slot_count() != 9:
		_fail("Runtime screen did not render 27 storage plus 9 hotbar slots")
	if not screen.get_toggle_button().is_visible_in_tree():
		_fail("Touch inventory toggle is not visible")

	if not inventory.add_item(BLOCK_STONE, 5):
		_fail("Could not seed five stone")
	if not inventory.add_item(BLOCK_DIRT, 3):
		_fail("Could not seed three dirt")
	await _wait_frames(3)

	screen.get_toggle_button().emit_signal("pressed")
	await _wait_frames(3)
	if not screen.is_inventory_open() or not player.is_inventory_input_locked():
		_fail("Visible inventory button did not open and lock gameplay")
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_fail("Inventory open state did not expose the cursor")

	var position_before: Vector3 = player.global_position
	var rotation_before: Vector3 = player.rotation
	var selected_before: int = player.get_selected_inventory_slot()
	for action in ["move_forward", "jump", "look_right", "mine_block", "place_block", "select_hotbar_2"]:
		Input.action_press(action)
	await _wait_frames(10)
	for action in ["move_forward", "jump", "look_right", "mine_block", "place_block", "select_hotbar_2"]:
		Input.action_release(action)
	if player.global_position.distance_to(position_before) > 0.0001:
		_fail("Player moved while inventory was open")
	if player.rotation.distance_to(rotation_before) > 0.0001:
		_fail("Player looked while inventory was open")
	if player.get_selected_inventory_slot() != selected_before:
		_fail("Hotbar selection changed while inventory was open")

	var hotbar_zero := screen.get_slot_button(0) as Button
	var hotbar_one := screen.get_slot_button(1) as Button
	var storage_zero := screen.get_slot_button(9) as Button
	var storage_one := screen.get_slot_button(10) as Button
	var storage_two := screen.get_slot_button(11) as Button
	if hotbar_zero == null or hotbar_one == null or storage_zero == null or storage_one == null or storage_two == null:
		_fail("One or more inventory interaction buttons are missing")
		_finish()
		return

	hotbar_zero.emit_signal("button_down")
	hotbar_zero.emit_signal("button_up")
	await _wait_frames(2)
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 5, "primary-button pickup")
	_assert_stack(inventory.get_slot(0), BLOCK_AIR, 0, "primary-button source")

	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	storage_zero.emit_signal("gui_input", right_click)
	await _wait_frames(2)
	_assert_stack(inventory.get_slot(9), BLOCK_STONE, 1, "right-click one-item placement")
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 4, "right-click cursor remainder")

	storage_one.emit_signal("button_down")
	await _wait_frames(35)
	storage_one.emit_signal("button_up")
	await _wait_frames(2)
	_assert_stack(inventory.get_slot(10), BLOCK_STONE, 1, "touch long-press one-item placement")
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 3, "long-press cursor remainder")

	storage_two.emit_signal("button_down")
	storage_two.emit_signal("button_up")
	await _wait_frames(2)
	_assert_stack(inventory.get_slot(11), BLOCK_STONE, 3, "primary storage placement")
	_assert_stack(screen.get_cursor_stack(), BLOCK_AIR, 0, "cursor after storage placement")

	hotbar_one.emit_signal("button_down")
	hotbar_one.emit_signal("button_up")
	await _wait_frames(2)
	_assert_stack(screen.get_cursor_stack(), BLOCK_DIRT, 3, "carried dirt before close")
	_assert_stack(inventory.get_slot(1), BLOCK_AIR, 0, "dirt source before close")

	screen.get_close_button().emit_signal("pressed")
	await _wait_frames(3)
	if screen.is_inventory_open() or player.is_inventory_input_locked():
		_fail("Visible close button did not close and unlock gameplay")
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_fail("Closing inventory did not recapture the cursor")
	_assert_stack(screen.get_cursor_stack(), BLOCK_AIR, 0, "cursor returned before close")
	if inventory.get_item_count(BLOCK_DIRT) != 3 or inventory.get_item_count(BLOCK_STONE) != 5:
		_fail("Closing inventory lost or duplicated carried items")
	_assert_stack(inventory.get_slot(0), BLOCK_DIRT, 3, "returned dirt hotbar slot")

	var visible_hotbar_label := hotbar.get_node_or_null("HotbarRoot/Slots/Slot1/Content") as Label
	if visible_hotbar_label == null or visible_hotbar_label.text != "1\nDIRT x3":
		_fail("Always-visible hotbar did not synchronize returned dirt")

	screen.get_toggle_button().emit_signal("pressed")
	await _wait_frames(3)
	var screen_hotbar_label := screen.get_hotbar_slot_label(0) as Label
	if screen_hotbar_label == null or screen_hotbar_label.text != "1\nDIRT x3":
		_fail("Full-screen hotbar did not synchronize returned dirt")
	if screen.get_cursor_label().text != "CARRIED: EMPTY x0":
		_fail("Cursor label was not empty after safe close")
	await _capture_screenshot()
	screen.close_inventory()

	if failures.is_empty():
		print("MINECRAFT_INVENTORY_STEP_5_GATE_PASS")
		print("INVENTORY_SHAPE=9 hotbar + 27 storage; stack limit 64")
		print("PRIMARY=button pickup,place,merge,swap")
		print("SECONDARY=right-click and 0.45 second touch long press")
		print("INPUT_LOCK=movement,look,jump,mine,place,hotbar selection")
		print("CURSOR_RETURN=all carried items returned before close")
	_finish()


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Final inventory screenshot was empty")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Final screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Final screenshot save failed with error %d" % save_error)
		return
	print("MINECRAFT_INVENTORY_STEP_5_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("MINECRAFT_INVENTORY_STEP_5_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
