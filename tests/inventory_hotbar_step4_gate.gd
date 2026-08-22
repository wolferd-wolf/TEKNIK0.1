extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/inventory-hotbar-step4.png"
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const HOTBAR_SLOT_COUNT := 9

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
	if not player.has_method("get_inventory") or not player.has_method("get_hotbar"):
		_fail("Player does not expose inventory and hotbar state")
		_finish()
		return

	var inventory = player.get_inventory()
	var hotbar = player.get_hotbar()
	if inventory == null:
		_fail("Player inventory is null")
	if hotbar == null:
		_fail("Rendered inventory hotbar was not created")
	if not failures.is_empty():
		_finish()
		return

	var hotbar_root := hotbar.get_node_or_null("Root") as Control
	var slots_row := hotbar.get_node_or_null("Root/Bar") as HBoxContainer
	if hotbar_root == null:
		_fail("Rendered hotbar Root control is missing")
	if slots_row == null:
		_fail("Rendered hotbar Bar row is missing")
	if not failures.is_empty():
		_finish()
		return

	if not hotbar_root.is_visible_in_tree():
		_fail("HotbarRoot is not visible in the rendered scene tree")
	var hotbar_rect := hotbar_root.get_global_rect()
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	if hotbar_rect.size.x < 900.0 or hotbar_rect.size.y < 70.0:
		_fail("Rendered hotbar is too small: %s" % hotbar_rect)
	if not viewport_rect.encloses(hotbar_rect):
		_fail("Rendered hotbar lies outside the viewport: %s" % hotbar_rect)
	if slots_row.get_child_count() != HOTBAR_SLOT_COUNT:
		_fail("Rendered hotbar has %d slots instead of 9" % slots_row.get_child_count())

	if not inventory.add_item(BLOCK_STONE, 2):
		_fail("Failed to seed stone for rendered hotbar")
	if not inventory.add_item(BLOCK_DIRT, 5):
		_fail("Failed to seed dirt for rendered hotbar")
	if not inventory.add_item(BLOCK_GRASS, 1):
		_fail("Failed to seed grass for rendered hotbar")
	await _wait_frames(4)

	_assert_rendered_slot(hotbar, 0, "1\nSTONE x2", true)
	_assert_rendered_slot(hotbar, 1, "2\nDIRT x5", false)
	_assert_rendered_slot(hotbar, 2, "3\nGRASS x1", false)
	_assert_rendered_slot(hotbar, 3, "4\nEMPTY x0", false)

	await _press_action("select_hotbar_2")
	if player.get_selected_inventory_slot() != 1:
		_fail("select_hotbar_2 selected slot %d instead of 1" % player.get_selected_inventory_slot())
	_assert_rendered_slot(hotbar, 0, "1\nSTONE x2", false)
	_assert_rendered_slot(hotbar, 1, "2\nDIRT x5", true)

	await _press_action("hotbar_next")
	if player.get_selected_inventory_slot() != 2:
		_fail("hotbar_next selected slot %d instead of 2" % player.get_selected_inventory_slot())
	_assert_rendered_slot(hotbar, 1, "2\nDIRT x5", false)
	_assert_rendered_slot(hotbar, 2, "3\nGRASS x1", true)

	await _press_action("hotbar_previous")
	if player.get_selected_inventory_slot() != 1:
		_fail("hotbar_previous selected slot %d instead of 1" % player.get_selected_inventory_slot())
	_assert_rendered_slot(hotbar, 1, "2\nDIRT x5", true)
	_assert_rendered_slot(hotbar, 2, "3\nGRASS x1", false)

	if not inventory.remove_from_slot(1, 2):
		_fail("Failed to mutate dirt count for rendered UI refresh")
	await _wait_frames(4)
	_assert_rendered_slot(hotbar, 1, "2\nDIRT x3", true)

	await _capture_screenshot()
	if failures.is_empty():
		print("INVENTORY_HOTBAR_STEP_4_GATE_PASS")
		print("HOTBAR_RENDERED_CONTENT=1 STONE x2; 2 DIRT x5->x3; 3 GRASS x1; 4 EMPTY x0")
		print("HOTBAR_KEY_SELECTION=select_hotbar_2 -> rendered slot 2 highlighted")
		print("HOTBAR_SCROLL_SELECTION=next -> slot 3; previous -> slot 2")
		print("HOTBAR_RENDERED_RECT=%s" % hotbar_rect)
	_finish()


func _validate_input_map() -> void:
	for slot_number in range(1, HOTBAR_SLOT_COUNT + 1):
		var action := StringName("select_hotbar_%d" % slot_number)
		if not InputMap.has_action(action):
			_fail("%s InputMap action is missing" % action)
			continue
		if not _has_key_binding(action, 48 + slot_number):
			_fail("%s is not bound to physical number key %d" % [action, 48 + slot_number])

	if not InputMap.has_action("hotbar_previous"):
		_fail("hotbar_previous InputMap action is missing")
	elif not _has_mouse_button_binding("hotbar_previous", MOUSE_BUTTON_WHEEL_UP):
		_fail("hotbar_previous is not bound to mouse wheel up")
	if not InputMap.has_action("hotbar_next"):
		_fail("hotbar_next InputMap action is missing")
	elif not _has_mouse_button_binding("hotbar_next", MOUSE_BUTTON_WHEEL_DOWN):
		_fail("hotbar_next is not bound to mouse wheel down")


func _has_key_binding(action: StringName, physical_keycode: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == physical_keycode:
			return true
	return false


func _has_mouse_button_binding(action: StringName, button_index: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button_index:
			return true
	return false


func _press_action(action: StringName) -> void:
	Input.action_press(action, 1.0)
	await process_frame
	Input.action_release(action)
	await _wait_frames(3)


func _assert_rendered_slot(hotbar, slot_index: int, expected_text: String, selected: bool) -> void:
	# expected_text keeps the legacy "<key>\n<NAME> x<count>" shape for
	# readability; assertions target the rewritten swatch/count widgets.
	var parts := expected_text.split("\n")
	var stack_part := parts[parts.size() - 1] if parts.size() > 0 else ""
	var name_count := stack_part.rsplit(" x", true, 1)
	var expected_name := name_count[0].strip_edges() if name_count.size() > 0 else ""
	var expected_count := int(name_count[1]) if name_count.size() > 1 else 0

	var panel_path := "Root/Bar/Slot%d" % (slot_index + 1)
	var frame := hotbar.get_node_or_null(panel_path) as Panel
	var view: Node = hotbar.get_node_or_null(panel_path + "/View")
	var count_label := hotbar.get_node_or_null(panel_path + "/View/Count") as Label
	if frame == null or view == null or count_label == null:
		_fail("Rendered widgets are missing for hotbar slot %d" % (slot_index + 1))
		return
	if not frame.is_visible_in_tree():
		_fail("Hotbar slot %d is not visible in the rendered scene tree" % (slot_index + 1))

	var style: StyleBoxFlat = frame.get_theme_stylebox("panel")
	var is_highlighted := style != null and style.border_color.a > 0.9
	if is_highlighted != selected:
		_fail(
			"Rendered slot %d selection highlight expected %s got %s"
			% [slot_index + 1, selected, is_highlighted]
		)

	var has_item := expected_name != "EMPTY" and expected_count > 0
	if count_label.text != ("x%d" % expected_count if has_item else ""):
		_fail(
			"Rendered slot %d count expected x%d got %s"
			% [slot_index + 1, expected_count, count_label.text]
		)
	var icon := view.get_node_or_null("Icon") as TextureRect
	var swatch_rect := view.get_node_or_null("Swatch") as ColorRect
	var item_visual_visible := (icon != null and icon.visible) or (swatch_rect != null and swatch_rect.visible)
	if item_visual_visible != has_item:
		_fail(
			"Rendered slot %d item visual visibility expected %s got %s"
			% [slot_index + 1, has_item, item_visual_visible]
		)

	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	if not viewport_rect.encloses(frame.get_global_rect()):
		_fail("Rendered slot %d frame lies outside the viewport" % (slot_index + 1))


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Hotbar screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Hotbar screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Hotbar screenshot save failed with error %d" % save_error)
		return
	print("INVENTORY_HOTBAR_STEP_4_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("INVENTORY_HOTBAR_STEP_4_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
