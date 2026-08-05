extends SceneTree

const INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/minecraft-inventory-step2.png"
const TOGGLE_ACTION := StringName("toggle_inventory")
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
	if inventory.get_hotbar_slot_count() != 9 or inventory.get_storage_slot_count() != 27:
		_fail("Inventory did not expose 9 hotbar plus 27 storage slots")
	if not inventory.add_item(BLOCK_STONE, 70):
		_fail("Could not seed model stack test")
	var held: Dictionary = inventory.take_from_slot(0, 10)
	held = inventory.put_stack_into_slot(1, held)
	_assert_stack(held, BLOCK_AIR, 0, "merge remainder")
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 16, "merged slot")
	held = inventory.split_from_slot(1)
	_assert_stack(held, BLOCK_STONE, 8, "split held stack")
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 8, "split source stack")


func _validate_toggle_input() -> void:
	if not InputMap.has_action(TOGGLE_ACTION):
		_fail("toggle_inventory InputMap action is missing")
		return
	var has_e_key := false
	for event in InputMap.action_get_events(TOGGLE_ACTION):
		if event is InputEventKey and event.physical_keycode == 69:
			has_e_key = true
			break
	if not has_e_key:
		_fail("toggle_inventory is not bound to physical key E")


func _run_gate() -> void:
	_validate_model()
	_validate_toggle_input()

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
		_fail("Inventory or full inventory screen is null")
		_finish()
		return

	if screen.get_storage_slot_count() != 27:
		_fail("Screen rendered %d storage slots instead of 27" % screen.get_storage_slot_count())
	if screen.get_hotbar_slot_count() != 9:
		_fail("Screen rendered %d hotbar slots instead of 9" % screen.get_hotbar_slot_count())
	if screen.is_inventory_open():
		_fail("Inventory screen started open")
	if screen.get_inventory_panel().is_visible_in_tree():
		_fail("Inventory panel was visible before opening")
	if not screen.get_toggle_button().is_visible_in_tree():
		_fail("Touch-friendly inventory toggle is not visible")

	if not inventory.add_item(BLOCK_STONE, 9 * 64):
		_fail("Could not fill the nine hotbar stacks")
	if not inventory.add_item(BLOCK_DIRT, 12):
		_fail("Could not seed first storage slot")
	await _wait_frames(4)

	var hotbar_label := screen.get_hotbar_slot_label(0) as Label
	var storage_label := screen.get_storage_slot_label(0) as Label
	if hotbar_label == null or hotbar_label.text != "1\nSTONE x64":
		_fail("Full-screen hotbar slot 1 did not mirror STONE x64")
	if storage_label == null or storage_label.text != "DIRT x12":
		_fail("First storage slot did not render DIRT x12")

	Input.action_press(TOGGLE_ACTION)
	await process_frame
	Input.action_release(TOGGLE_ACTION)
	await _wait_frames(4)
	if not screen.is_inventory_open() or not screen.get_inventory_panel().is_visible_in_tree():
		_fail("InputMap action did not open the inventory screen")
	if screen.get_toggle_button().text != "CLOSE":
		_fail("Visible toggle did not change to CLOSE while open")

	await _capture_screenshot()
	screen.close_inventory()
	await _wait_frames(2)
	if screen.is_inventory_open() or screen.get_inventory_panel().is_visible_in_tree():
		_fail("Close operation did not hide the inventory screen")

	if failures.is_empty():
		print("MINECRAFT_INVENTORY_STEP_2_GATE_PASS")
		print("INVENTORY_LAYOUT=27 storage + shared 9-slot hotbar")
		print("INVENTORY_TOGGLE=physical E + visible touch button")
		print("INVENTORY_INTERACTION=disabled until Step 3")
	_finish()


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Inventory screen screenshot was empty")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Screenshot save failed with error %d" % save_error)
		return
	print("MINECRAFT_INVENTORY_STEP_2_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("MINECRAFT_INVENTORY_STEP_2_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
