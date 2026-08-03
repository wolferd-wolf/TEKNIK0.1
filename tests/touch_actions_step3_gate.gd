extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/touch-actions-step3.png"
const ACTION_BUTTONS := {
	"JumpButton": StringName("jump"),
	"MineButton": StringName("mine_block"),
	"PlaceButton": StringName("place_block"),
	"CraftButton": StringName("craft_test_recipe"),
}
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
	if player == null:
		_fail("Player node is missing")
	if controls == null:
		_fail("TouchActionControls node is missing")
	if not failures.is_empty():
		_finish()
		return

	if not controls.has_method("get_action_button") or not controls.has_method("get_hotbar_button"):
		_fail("TouchActionControls does not expose required gate accessors")
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

	for slot_index in range(HOTBAR_SLOT_COUNT):
		var hotbar_button := controls.get_hotbar_button(slot_index) as Button
		if hotbar_button == null:
			_fail("Missing hotbar touch target %d" % slot_index)
			continue
		if not viewport_rect.encloses(hotbar_button.get_global_rect()):
			_fail("Hotbar touch target %d lies outside viewport: %s" % [slot_index, hotbar_button.get_global_rect()])

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

	await _capture_screenshot()
	_release_gate_actions()
	if failures.is_empty():
		print("TOUCH_ACTIONS_STEP_3_GATE_PASS")
		print("TOUCH_ACTIONS_BUTTONS=jump,mine_block,place_block,craft_test_recipe")
		print("TOUCH_ACTIONS_HOTBAR=simulated taps selected slots 0-8")
		print("TOUCH_ACTIONS_INPUTMAP=existing actions pressed and released through rendered Button touch targets")
		print("TOUCH_ACTIONS_DESKTOP_BINDINGS=keyboard/mouse events remain present")
		print("TOUCH_ACTIONS_SIMULATION=InputEventScreenTouch through Input.parse_input_event")
		print("TOUCH_ACTIONS_DEVICE_SCOPE=desktop touch simulation; real Android deferred")
	_finish()


func _validate_input_map_contract() -> void:
	var action_names: Array[StringName] = [
		StringName("jump"), StringName("mine_block"), StringName("place_block"), StringName("craft_test_recipe")
	]
	for slot_index in range(HOTBAR_SLOT_COUNT):
		action_names.append(StringName("select_hotbar_%d" % (slot_index + 1)))
	for action in action_names:
		if not InputMap.has_action(action):
			_fail("Required InputMap action is missing: %s" % action)
			continue
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
