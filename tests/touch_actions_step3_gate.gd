extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/touch-actions-step3.png"
const ACTION_BUTTONS := {
	"JumpButton": StringName("jump"),
	"MineButton": StringName("mine_block"),
	"PlaceButton": StringName("place_block"),
	"InventoryButton": StringName("toggle_inventory"),
}
const HOTBAR_SLOT_COUNT := 9
const MAP_PIXEL_DIAMETER := 49
const MAP_PIXEL_CENTER := 24

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
	_validate_input_map_contract()
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(30)

	var player := main.get_node_or_null("Player")
	var controls := main.get_node_or_null("TouchActionControls")
	var touch_controls := main.get_node_or_null("TouchControls")
	var map_overlay := main.get_node_or_null("WorldMapOverlay")
	if player == null:
		_fail("Player node is missing")
	if controls == null:
		_fail("TouchActionControls node is missing")
	if touch_controls == null:
		_fail("TouchControls node is missing")
	if map_overlay == null:
		_fail("WorldMapOverlay node is missing")
	if not failures.is_empty():
		_finish()
		return

	if not controls.has_method("get_action_button") or not controls.has_method("get_hotbar_button"):
		_fail("TouchActionControls does not expose required gate accessors")
	if (
		not map_overlay.has_method("get_map_button")
		or not map_overlay.has_method("get_map_panel")
		or not map_overlay.has_method("get_map_texture_rect")
		or not map_overlay.has_method("get_close_button")
		or not map_overlay.has_method("is_map_open")
	):
		_fail("WorldMapOverlay does not expose required gate accessors")
	if not touch_controls.has_method("get_look_hint"):
		_fail("TouchControls no longer exposes the drag-look visual accessor")
	if not failures.is_empty():
		_finish()
		return

	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	for button_name in ACTION_BUTTONS.keys():
		var button := controls.get_action_button(StringName(button_name)) as Button
		if button == null:
			_fail("Missing rendered action button %s" % button_name)
			continue
		if not button.is_visible_in_tree():
			_fail("Action button %s is not visible" % button_name)
		if not viewport_rect.encloses(button.get_global_rect()):
			_fail("Action button %s lies outside viewport: %s" % [button_name, button.get_global_rect()])

	var inventory_button := controls.get_action_button(StringName("InventoryButton")) as Button
	if inventory_button != null and inventory_button.text != "INVENTORY":
		_fail("Lower action button label is %s instead of INVENTORY" % inventory_button.text)
	if controls.get_action_button(StringName("CraftButton")) != null:
		_fail("The lower CRAFT touch button still exists")

	for slot_index in range(HOTBAR_SLOT_COUNT):
		var hotbar_button := controls.get_hotbar_button(slot_index) as Button
		if hotbar_button == null:
			_fail("Missing hotbar touch target %d" % slot_index)
			continue
		if not viewport_rect.encloses(hotbar_button.get_global_rect()):
			_fail("Hotbar touch target %d lies outside viewport: %s" % [slot_index, hotbar_button.get_global_rect()])

	var map_button := map_overlay.get_map_button() as Button
	var map_panel := map_overlay.get_map_panel() as PanelContainer
	var map_texture_rect := map_overlay.get_map_texture_rect() as TextureRect
	var map_close_button := map_overlay.get_close_button() as Button
	if map_button == null or map_panel == null or map_texture_rect == null or map_close_button == null:
		_fail("Map controls are incomplete")
	else:
		var map_button_rect := map_button.get_global_rect()
		if not viewport_rect.encloses(map_button_rect):
			_fail("Map button lies outside viewport: %s" % map_button_rect)
		if map_button_rect.position.x > 32.0 or map_button_rect.position.y > 32.0:
			_fail("Map button is not in the upper-left corner: %s" % map_button_rect)
		if map_button_rect.size.x > 120.0 or map_button_rect.size.y > 64.0:
			_fail("Map button is not small: %s" % map_button_rect.size)
		if bool(map_overlay.is_map_open()):
			_fail("Map opened without the map button being pressed")
		if map_panel.is_visible_in_tree():
			_fail("Map panel is visible before the map button is pressed")

	var look_hint := touch_controls.get_look_hint() as CanvasItem
	if look_hint == null:
		_fail("Drag-look visual node is missing instead of being visually removed")
	elif look_hint.modulate.a > 0.01:
		_fail("DRAG TO LOOK button remains visible with alpha %.3f" % look_hint.modulate.a)

	if not failures.is_empty():
		_finish()
		return

	player.set_process(false)
	player.set_physics_process(false)
	_release_gate_actions()
	await _wait_frames(2)

	for button_name in ACTION_BUTTONS.keys():
		var action: StringName = ACTION_BUTTONS[button_name]
		var button := controls.get_action_button(StringName(button_name)) as Button
		await _simulate_touch(10, button.get_global_rect().get_center(), true)
		if button_name == "InventoryButton":
			if Input.is_action_pressed(action):
				_fail("One-shot lower INVENTORY button left toggle_inventory pressed")
			var inventory_screen = player.get_inventory_screen()
			if inventory_screen == null or not bool(inventory_screen.is_inventory_open()):
				_fail("Lower INVENTORY button did not open the real inventory screen")
			await _simulate_touch(10, button.get_global_rect().get_center(), false)
			if Input.is_action_pressed(action):
				_fail("Lower INVENTORY touch-up left toggle_inventory pressed")
			if inventory_screen != null and bool(inventory_screen.is_inventory_open()):
				inventory_screen.close_inventory()
				await process_frame
			continue
		if not Input.is_action_pressed(action):
			_fail("Simulated touch-down on %s did not press InputMap action %s" % [button_name, action])
		await _simulate_touch(10, button.get_global_rect().get_center(), false)
		if Input.is_action_pressed(action):
			_fail("Simulated touch-up on %s did not release InputMap action %s" % [button_name, action])

	player.set_process(true)
	for slot_index in range(HOTBAR_SLOT_COUNT):
		var hotbar_button := controls.get_hotbar_button(slot_index) as Button
		var action := StringName("select_hotbar_%d" % (slot_index + 1))
		await _simulate_touch(20 + slot_index, hotbar_button.get_global_rect().get_center(), true)
		if not Input.is_action_pressed(action):
			_fail("Hotbar touch-down %d did not press %s" % [slot_index, action])
		await process_frame
		if int(player.get_selected_inventory_slot()) != slot_index:
			_fail("Hotbar touch %d selected slot %d" % [slot_index, int(player.get_selected_inventory_slot())])
		await _simulate_touch(20 + slot_index, hotbar_button.get_global_rect().get_center(), false)
		if Input.is_action_pressed(action):
			_fail("Hotbar touch-up %d did not release %s" % [slot_index, action])

	Input.action_press(StringName("move_right"))
	await _simulate_touch(50, map_button.get_global_rect().get_center(), true)
	if not bool(map_overlay.is_map_open()):
		_fail("Map button touch did not open the map")
	if Input.is_action_pressed(StringName("move_right")):
		_fail("Opening the map did not release active gameplay movement")
	await _simulate_touch(50, map_button.get_global_rect().get_center(), false)
	await _wait_frames(2)

	if not map_panel.is_visible_in_tree():
		_fail("Map panel is not visible after pressing the map button")
	elif not viewport_rect.encloses(map_panel.get_global_rect()):
		_fail("Map panel lies outside viewport: %s" % map_panel.get_global_rect())
	if map_button.text != "CLOSE":
		_fail("Open map button label is %s instead of CLOSE" % map_button.text)
	if map_texture_rect.texture == null:
		_fail("Map opened without a generated terrain texture")
	else:
		var map_texture := map_texture_rect.texture as ImageTexture
		if map_texture == null:
			_fail("Map texture is not an ImageTexture")
		else:
			var map_image := map_texture.get_image()
			if map_image.get_width() != MAP_PIXEL_DIAMETER or map_image.get_height() != MAP_PIXEL_DIAMETER:
				_fail("Map texture dimensions are %dx%d instead of %dx%d" % [
					map_image.get_width(),
					map_image.get_height(),
					MAP_PIXEL_DIAMETER,
					MAP_PIXEL_DIAMETER,
				])
			var marker := map_image.get_pixel(MAP_PIXEL_CENTER, MAP_PIXEL_CENTER)
			if marker.r < 0.9 or marker.g < 0.7 or marker.b > 0.3:
				_fail("Map center does not contain the yellow player marker: %s" % marker)
			var unique_colors: Dictionary = {}
			for pixel_y in range(MAP_PIXEL_DIAMETER):
				for pixel_x in range(MAP_PIXEL_DIAMETER):
					unique_colors[map_image.get_pixel(pixel_x, pixel_y).to_html()] = true
			if unique_colors.size() < 4:
				_fail("Map texture lacks terrain variation: only %d colors" % unique_colors.size())

	await _capture_screenshot()
	await _simulate_touch(51, map_button.get_global_rect().get_center(), true)
	await _simulate_touch(51, map_button.get_global_rect().get_center(), false)
	if bool(map_overlay.is_map_open()):
		_fail("Second map-button press did not close the map")
	if map_panel.is_visible_in_tree():
		_fail("Map panel remained visible after closing")

	_release_gate_actions()
	if failures.is_empty():
		print("TOUCH_ACTIONS_STEP_3_GATE_PASS")
		print("TOUCH_ACTIONS_BUTTONS=jump,mine_block,place_block,direct_inventory_toggle")
		print("TOUCH_ACTIONS_CRAFT_BUTTON=removed; craft_test_recipe desktop action preserved")
		print("TOUCH_ACTIONS_DRAG_HINT=visual alpha zero; drag-look behavior retained by inherited gate")
		print("TOUCH_ACTIONS_MAP=upper-left button generated a 49x49 north-up terrain image and toggled the overlay")
		print("TOUCH_ACTIONS_HOTBAR=simulated taps selected slots 0-8")
		print("TOUCH_ACTIONS_INPUTMAP=jump/mine/place/hotbar actions pressed and released through rendered Button touch targets")
		print("TOUCH_ACTIONS_DESKTOP_BINDINGS=keyboard/mouse events remain present")
		print("TOUCH_ACTIONS_SIMULATION=InputEventScreenTouch through Input.parse_input_event")
		print("TOUCH_ACTIONS_DEVICE_SCOPE=desktop touch simulation; real Android deferred")
	_finish()


func _validate_input_map_contract() -> void:
	var action_names: Array[StringName] = [
		StringName("jump"), StringName("mine_block"), StringName("place_block"), StringName("toggle_inventory")
	]
	for slot_index in range(HOTBAR_SLOT_COUNT):
		action_names.append(StringName("select_hotbar_%d" % (slot_index + 1)))
	for action in action_names:
		_validate_desktop_action(action)
	_validate_desktop_action(StringName("craft_test_recipe"))
	if InputMap.has_action(StringName("toggle_map")):
		_fail("Map has an InputMap action; it must open only from its upper-left button")


func _validate_desktop_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		_fail("Required InputMap action is missing: %s" % action)
		return
	var has_desktop_event := false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton:
			has_desktop_event = true
			break
	if not has_desktop_event:
		_fail("Existing desktop binding is missing for action %s" % action)


func _simulate_touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(SCREENSHOT_PATH)
	if error != OK:
		_fail("Failed to save screenshot: %s" % error_string(error))


func _release_gate_actions() -> void:
	for action in ACTION_BUTTONS.values():
		Input.action_release(action)
	Input.action_release(StringName("craft_test_recipe"))
	Input.action_release(StringName("move_right"))
	for slot_index in range(HOTBAR_SLOT_COUNT):
		Input.action_release(StringName("select_hotbar_%d" % (slot_index + 1)))


func _finish() -> void:
	_release_gate_actions()
	if failures.is_empty():
		quit(0)
	else:
		print("TOUCH_ACTIONS_STEP_3_GATE_FAIL count=%d" % failures.size())
		for failure in failures:
			print("TOUCH_ACTIONS_STEP_3_FAILURE=%s" % failure)
		quit(1)
