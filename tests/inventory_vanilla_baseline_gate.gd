extends SceneTree

const INVENTORY_SCRIPT := preload("res://scripts/inventory/block_inventory.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/inventory-vanilla-baseline.png"
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


func _run_gate() -> void:
	_validate_inventory_model()
	_validate_input_map()

	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(32)

	var player := main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	var mobile_camera := main.get_node_or_null("MobileCameraSensitivity")
	var localized_water := main.get_node_or_null("ChunkManager/LocalizedWaterBodies")
	if player == null:
		_fail("Approved player node is missing")
	if camera == null:
		_fail("Approved player camera is missing")
	if sun == null:
		_fail("Approved sun node is missing")
	if mobile_camera == null:
		_fail("Approved MobileCameraSensitivity node is missing")
	if localized_water == null:
		_fail("Approved LocalizedWaterBodies node is missing")
	if not failures.is_empty():
		_finish()
		return

	if sun.shadow_enabled:
		_fail("Directional shadow maps were re-enabled")
	var drag_sensitivity := float(mobile_camera.get("radians_per_drag_pixel"))
	if not is_equal_approx(drag_sensitivity, 0.0035):
		_fail("Mobile camera sensitivity changed from 0.0035 to %.6f" % drag_sensitivity)

	if not player.has_method("get_inventory") or not player.has_method("get_inventory_screen"):
		_fail("Player does not expose the Minecraft inventory integration")
		_finish()
		return
	var inventory = player.get_inventory()
	var screen = player.get_inventory_screen()
	var hotbar = player.get_hotbar()
	if inventory == null or screen == null or hotbar == null:
		_fail("Inventory, screen, or hotbar was not created")
		_finish()
		return

	if inventory.get_slot_count() != 36:
		_fail("Runtime inventory had %d slots instead of 36" % inventory.get_slot_count())
	if screen.get_hotbar_slot_count() != 9:
		_fail("Inventory screen hotbar had %d slots instead of 9" % screen.get_hotbar_slot_count())
	if screen.get_storage_slot_count() != 27:
		_fail("Inventory screen storage had %d slots instead of 27" % screen.get_storage_slot_count())
	if screen.is_inventory_open():
		_fail("Inventory screen started open")

	if not inventory.add_item(BLOCK_STONE, 32):
		_fail("Failed to seed stone stack")
	if not inventory.add_item(BLOCK_DIRT, 5):
		_fail("Failed to seed dirt stack")
	await _wait_frames(3)

	screen.open_inventory()
	await _wait_frames(2)
	if not screen.is_inventory_open() or not player.is_inventory_input_locked():
		_fail("Opening inventory did not lock gameplay")
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_fail("Opening inventory did not reveal the pointer")
	if not screen.get_inventory_panel().is_visible_in_tree():
		_fail("Inventory panel is not visible while open")

	var yaw_before_lock: float = player.rotation.y
	var pitch_before_lock: float = camera.rotation.x
	player.apply_look_delta(Vector2(0.4, -0.25))
	if not is_equal_approx(player.rotation.y, yaw_before_lock):
		_fail("Camera yaw changed while inventory was open")
	if not is_equal_approx(camera.rotation.x, pitch_before_lock):
		_fail("Camera pitch changed while inventory was open")

	player.velocity = Vector3(1.0, 2.0, 3.0)
	Input.action_press("move_forward", 1.0)
	player.call("_physics_process", 1.0 / 60.0)
	Input.action_release("move_forward")
	if not player.velocity.is_zero_approx():
		_fail("Player velocity was not frozen while inventory was open")

	screen.interact_slot_primary(0)
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 32, "picked-up stone cursor")
	_assert_stack(inventory.get_slot(0), BLOCK_AIR, 0, "emptied hotbar slot")
	screen.interact_slot_secondary(9)
	_assert_stack(inventory.get_slot(9), BLOCK_STONE, 1, "single-item storage placement")
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 31, "cursor after single placement")
	screen.interact_slot_primary(9)
	_assert_stack(inventory.get_slot(9), BLOCK_STONE, 32, "merged storage stack")
	_assert_stack(screen.get_cursor_stack(), BLOCK_AIR, 0, "cursor after merge")
	screen.interact_slot_secondary(9)
	_assert_stack(inventory.get_slot(9), BLOCK_STONE, 16, "split storage remainder")
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 16, "split cursor stack")
	screen.interact_slot_primary(1)
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 16, "swapped target stack")
	_assert_stack(screen.get_cursor_stack(), BLOCK_DIRT, 5, "swapped cursor stack")

	if not screen.close_inventory():
		_fail("Inventory failed to close and return carried items")
	await _wait_frames(2)
	if screen.is_inventory_open() or player.is_inventory_input_locked():
		_fail("Closing inventory did not restore gameplay")
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_fail("Closing inventory did not recapture the pointer")
	_assert_stack(screen.get_cursor_stack(), BLOCK_AIR, 0, "cursor after close")
	if inventory.get_item_count(BLOCK_DIRT) != 5:
		_fail("Closing inventory lost the carried dirt stack")

	var yaw_before_unlock: float = player.rotation.y
	player.apply_look_delta(Vector2(0.2, 0.0))
	if is_equal_approx(player.rotation.y, yaw_before_unlock):
		_fail("Approved camera look did not resume after inventory closed")

	await _validate_touch_interaction(screen, inventory)
	await _capture_screenshot(screen)

	if failures.is_empty():
		print("INVENTORY_VANILLA_BASELINE_GATE_PASS")
		print("INVENTORY_LAYOUT=9 hotbar + 27 storage; max stack 64")
		print("INVENTORY_INTERACTION=pickup, merge, swap, split, single-item placement")
		print("INVENTORY_INPUT_LOCK=movement and camera blocked only while open")
		print("APPROVED_CAMERA_SENSITIVITY=0.0035 radians per drag pixel")
		print("APPROVED_DIRECTIONAL_SHADOW_MAPS=disabled")
	_finish()


func _validate_inventory_model() -> void:
	var inventory = INVENTORY_SCRIPT.new()
	if inventory.get_slot_count() != 36:
		_fail("Default inventory model had %d slots instead of 36" % inventory.get_slot_count())
	if inventory.get_hotbar_slot_count() != 9 or inventory.get_storage_slot_count() != 27:
		_fail("Default inventory model did not expose the 9+27 layout")
	if inventory.get_max_stack_size() != 64:
		_fail("Default max stack changed from 64")
	if not inventory.add_item(BLOCK_STONE, 2304):
		_fail("Could not fill all 36 inventory stacks")
	if not inventory.is_full():
		_fail("36 full stacks did not report a full inventory")
	var snapshot: Array[Dictionary] = inventory.get_slots()
	if inventory.add_item(BLOCK_DIRT, 1):
		_fail("Full inventory accepted an extra item")
	if inventory.get_slots() != snapshot:
		_fail("Rejected full-inventory add was not atomic")


func _validate_input_map() -> void:
	if not InputMap.has_action("toggle_inventory"):
		_fail("toggle_inventory InputMap action is missing")
		return
	var has_e_binding := false
	for event in InputMap.action_get_events("toggle_inventory"):
		if event is InputEventKey and event.physical_keycode == 69:
			has_e_binding = true
			break
	if not has_e_binding:
		_fail("toggle_inventory is not bound to physical key E")


func _validate_touch_interaction(screen, inventory) -> void:
	screen.open_inventory()
	await _wait_frames(2)
	var slot_button := screen.get_slot_button(1) as Button
	if slot_button == null or not slot_button.is_visible_in_tree():
		_fail("Touch test slot button is unavailable")
		return
	var center := slot_button.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 7
	press.position = center
	press.pressed = true
	screen.call("_input", press)
	await get_root().get_tree().create_timer(0.52).timeout
	var release := InputEventScreenTouch.new()
	release.index = 7
	release.position = center
	release.pressed = false
	screen.call("_input", release)
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 8, "touch long-press remainder")
	_assert_stack(screen.get_cursor_stack(), BLOCK_STONE, 8, "touch long-press split")
	if not screen.close_inventory():
		_fail("Touch interaction cursor stack could not be returned")
	await _wait_frames(2)
	_assert_stack(inventory.get_slot(1), BLOCK_STONE, 16, "touch split restored on close")

	var toggle_button := screen.get_toggle_button() as Button
	var toggle_center := toggle_button.get_global_rect().get_center()
	var toggle_press := InputEventScreenTouch.new()
	toggle_press.index = 8
	toggle_press.position = toggle_center
	toggle_press.pressed = true
	screen.call("_input", toggle_press)
	if not screen.is_inventory_open():
		_fail("Touch inventory button did not open the screen")
	var toggle_release := InputEventScreenTouch.new()
	toggle_release.index = 8
	toggle_release.position = toggle_center
	toggle_release.pressed = false
	screen.call("_input", toggle_release)


func _capture_screenshot(screen) -> void:
	if not screen.is_inventory_open():
		screen.open_inventory()
	await _wait_frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Inventory screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Inventory screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if error != OK:
		_fail("Inventory screenshot save failed with error %d" % error)
		return
	print("INVENTORY_VANILLA_BASELINE_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _assert_stack(stack: Dictionary, block_id: int, count: int, context: String) -> void:
	var actual_block_id := int(stack.get("block_id", -1))
	var actual_count := int(stack.get("count", -1))
	if actual_block_id != block_id or actual_count != count:
		_fail(
			"%s expected block/count %d/%d, got %d/%d"
			% [context, block_id, count, actual_block_id, actual_count]
		)


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("INVENTORY_VANILLA_BASELINE_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
