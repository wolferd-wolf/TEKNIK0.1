extends SceneTree

const INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/minecraft-inventory-step4.png"
const BLOCK_AIR := 0
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


func _run_gate() -> void:
	var model = INVENTORY_SCRIPT.new()
	if model.get_slot_count() != 36:
		_fail("Inventory model regressed from 36 slots")

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
		_fail("Inventory player lock API is missing")
		_finish()
		return
	var inventory = player.get_inventory()
	var screen = player.get_inventory_screen()
	var hotbar = player.get_hotbar()
	if inventory == null or screen == null or hotbar == null:
		_fail("Inventory, screen, or always-visible hotbar is null")
		_finish()
		return

	if not inventory.add_item(BLOCK_STONE, 5):
		_fail("Could not seed five stone")
	screen.open_inventory()
	await _wait_frames(3)
	if not player.is_inventory_input_locked():
		_fail("Opening inventory did not lock gameplay input")
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_fail("Opening inventory did not expose the mouse cursor")

	var position_before: Vector3 = player.global_position
	var rotation_before: Vector3 = player.rotation
	for action in ["move_forward", "jump", "look_right", "mine_block", "place_block"]:
		Input.action_press(action)
	await _wait_frames(10)
	for action in ["move_forward", "jump", "look_right", "mine_block", "place_block"]:
		Input.action_release(action)
	if player.global_position.distance_to(position_before) > 0.0001:
		_fail("Player moved while inventory input was locked")
	if player.rotation.distance_to(rotation_before) > 0.0001:
		_fail("Player looked around while inventory input was locked")
	if inventory.get_item_count(BLOCK_STONE) != 5:
		_fail("Locked gameplay actions changed inventory contents")

	screen.interact_slot_primary(0)
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 5, "carried stack before close")
	_assert_stack(inventory.get_slot(0), BLOCK_AIR, 0, "emptied source before close")
	if not screen.close_inventory():
		_fail("Inventory refused to close with a returnable carried stack")
	await _wait_frames(3)
	_assert_stack(screen.get_cursor_stack(), BLOCK_AIR, 0, "cursor after close")
	if inventory.get_item_count(BLOCK_STONE) != 5:
		_fail("Closing inventory did not return all five carried stone")
	if player.is_inventory_input_locked():
		_fail("Closing inventory did not restore gameplay input")
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_fail("Closing inventory did not recapture the mouse")

	var hotbar_label := hotbar.get_node_or_null("HotbarRoot/Slots/Slot1/Content") as Label
	if hotbar_label == null or hotbar_label.text != "1\nSTONE x5":
		_fail("Always-visible hotbar did not synchronize returned stack")

	screen.open_inventory()
	await _wait_frames(3)
	var screen_label := screen.get_hotbar_slot_label(0) as Label
	if screen_label == null or screen_label.text != "1\nSTONE x5":
		_fail("Full inventory hotbar did not synchronize returned stack")
	await _capture_screenshot()
	screen.close_inventory()

	if failures.is_empty():
		print("MINECRAFT_INVENTORY_STEP_4_GATE_PASS")
		print("INPUT_LOCK=movement,look,jump,mine,place")
		print("CURSOR_RETURN=atomic before close")
		print("HOTBAR_SYNC=always-visible and full-screen views")
	_finish()


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Step 4 screenshot was empty")
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Step 4 screenshot save failed with error %d" % save_error)
		return
	print("MINECRAFT_INVENTORY_STEP_4_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("MINECRAFT_INVENTORY_STEP_4_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
