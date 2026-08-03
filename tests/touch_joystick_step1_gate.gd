extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/touch-joystick-step1.png"
const MOVE_LEFT_ACTION := StringName("move_left")
const MOVE_RIGHT_ACTION := StringName("move_right")
const MOVE_FORWARD_ACTION := StringName("move_forward")
const MOVE_BACKWARD_ACTION := StringName("move_backward")
const MOVEMENT_ACTIONS := [
	MOVE_LEFT_ACTION,
	MOVE_RIGHT_ACTION,
	MOVE_FORWARD_ACTION,
	MOVE_BACKWARD_ACTION,
]

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
	_validate_movement_actions()

	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(30)

	var player := main.get_node_or_null("Player") as CharacterBody3D
	var touch_controls := main.get_node_or_null("TouchControls")
	if player == null:
		_fail("Player node is missing")
	if touch_controls == null:
		_fail("TouchControls node is missing from the main scene")
	if not failures.is_empty():
		_finish()
		return
	if (
		not touch_controls.has_method("get_joystick_center")
		or not touch_controls.has_method("get_joystick_vector")
		or not touch_controls.has_method("get_joystick_base")
		or not touch_controls.has_method("get_joystick_knob")
	):
		_fail("TouchControls does not expose the rendered joystick test representation")
		_finish()
		return

	player.set_physics_process(false)
	var joystick_base := touch_controls.get_joystick_base() as Panel
	var joystick_knob := touch_controls.get_joystick_knob() as Panel
	if joystick_base == null or joystick_knob == null:
		_fail("Rendered joystick base or knob is missing")
		_finish()
		return

	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	var base_rect := joystick_base.get_global_rect()
	var knob_rect := joystick_knob.get_global_rect()
	if not joystick_base.is_visible_in_tree() or not joystick_knob.is_visible_in_tree():
		_fail("Virtual joystick controls are not visible in the rendered tree")
	if not viewport_rect.encloses(base_rect):
		_fail("Joystick base lies outside the viewport: %s" % base_rect)
	if not viewport_rect.encloses(knob_rect):
		_fail("Joystick knob lies outside the viewport: %s" % knob_rect)
	if base_rect.get_center().x >= viewport_rect.size.x * 0.5:
		_fail("Joystick base is not on the left side of the screen: %s" % base_rect)

	var center: Vector2 = touch_controls.get_joystick_center()
	await _simulate_touch(9, Vector2(980.0, 360.0), true)
	await _simulate_drag(9, Vector2(1060.0, 280.0), Vector2(80.0, -80.0))
	_assert_all_movement_actions_released("right-side touch")
	if touch_controls.get_active_touch_index() != -1:
		_fail("Right-side touch was incorrectly captured by the left joystick")
	await _simulate_touch(9, Vector2(1060.0, 280.0), false)

	await _simulate_touch(1, center, true)
	_assert_all_movement_actions_released("centered joystick touch")
	if touch_controls.get_active_touch_index() != 1:
		_fail("Left joystick did not capture simulated touch index 1")

	var up_right_position := center + Vector2(60.0, -60.0)
	await _simulate_drag(1, up_right_position, Vector2(60.0, -60.0))
	_assert_action_pressed(MOVE_FORWARD_ACTION, 0.65, "up-right drag forward")
	_assert_action_pressed(MOVE_RIGHT_ACTION, 0.65, "up-right drag right")
	_assert_action_released(MOVE_LEFT_ACTION, "up-right drag left")
	_assert_action_released(MOVE_BACKWARD_ACTION, "up-right drag backward")
	var up_right_forward_strength := Input.get_action_strength(MOVE_FORWARD_ACTION)
	var up_right_right_strength := Input.get_action_strength(MOVE_RIGHT_ACTION)
	var up_right_vector := Input.get_vector(
		MOVE_LEFT_ACTION,
		MOVE_RIGHT_ACTION,
		MOVE_FORWARD_ACTION,
		MOVE_BACKWARD_ACTION
	)
	if up_right_vector.x < 0.65 or up_right_vector.y > -0.65:
		_fail("InputMap vector did not reflect up-right touch drag: %s" % up_right_vector)
	var active_knob_center := joystick_knob.get_global_rect().get_center()
	if active_knob_center.x <= center.x + 20.0 or active_knob_center.y >= center.y - 20.0:
		_fail("Rendered joystick knob did not move with the active drag: %s" % active_knob_center)

	await _capture_screenshot()
	await _simulate_touch(1, up_right_position, false)
	_assert_all_movement_actions_released("up-right release")
	if not touch_controls.get_joystick_vector().is_zero_approx():
		_fail("Joystick vector did not return to zero after release")
	if joystick_knob.get_global_rect().get_center().distance_to(center) > 0.5:
		_fail("Rendered joystick knob did not return to center after release")

	await _simulate_touch(2, center, true)
	var down_left_position := center + Vector2(-60.0, 60.0)
	await _simulate_drag(2, down_left_position, Vector2(-60.0, 60.0))
	_assert_action_pressed(MOVE_LEFT_ACTION, 0.65, "down-left drag left")
	_assert_action_pressed(MOVE_BACKWARD_ACTION, 0.65, "down-left drag backward")
	_assert_action_released(MOVE_RIGHT_ACTION, "down-left drag right")
	_assert_action_released(MOVE_FORWARD_ACTION, "down-left drag forward")
	var down_left_vector := Input.get_vector(
		MOVE_LEFT_ACTION,
		MOVE_RIGHT_ACTION,
		MOVE_FORWARD_ACTION,
		MOVE_BACKWARD_ACTION
	)
	if down_left_vector.x > -0.65 or down_left_vector.y < 0.65:
		_fail("InputMap vector did not reflect down-left touch drag: %s" % down_left_vector)
	await _simulate_touch(2, down_left_position, false)
	_assert_all_movement_actions_released("down-left release")

	if failures.is_empty():
		print("TOUCH_JOYSTICK_STEP_1_GATE_PASS")
		print("TOUCH_JOYSTICK_RENDERED_RECT=%s" % base_rect)
		print("TOUCH_JOYSTICK_UP_RIGHT=move_forward+move_right strengths %.3f/%.3f" % [
			up_right_forward_strength,
			up_right_right_strength,
		])
		print("TOUCH_JOYSTICK_SIMULATION=InputEventScreenTouch+InputEventScreenDrag through Input.parse_input_event")
		print("TOUCH_JOYSTICK_RELEASE=all four movement InputMap actions released")
		print("TOUCH_JOYSTICK_DEVICE_SCOPE=desktop touch simulation; real Android deferred")
	_finish()


func _validate_movement_actions() -> void:
	for action in MOVEMENT_ACTIONS:
		if not InputMap.has_action(action):
			_fail("Movement InputMap action is missing: %s" % action)


func _simulate_touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)
	await _wait_frames(2)


func _simulate_drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	event.velocity = relative * 60.0
	event.pressure = 1.0
	Input.parse_input_event(event)
	await _wait_frames(2)


func _assert_action_pressed(action: StringName, minimum_strength: float, context: String) -> void:
	if not Input.is_action_pressed(action):
		_fail("%s did not press InputMap action %s" % [context, action])
		return
	var strength := Input.get_action_strength(action)
	if strength < minimum_strength:
		_fail("%s strength for %s was %.3f, expected at least %.3f" % [
			context,
			action,
			strength,
			minimum_strength,
		])


func _assert_action_released(action: StringName, context: String) -> void:
	if Input.is_action_pressed(action):
		_fail("%s unexpectedly pressed InputMap action %s" % [context, action])
	if Input.get_action_strength(action) > 0.001:
		_fail("%s left non-zero strength on %s: %.3f" % [
			context,
			action,
			Input.get_action_strength(action),
		])


func _assert_all_movement_actions_released(context: String) -> void:
	for action in MOVEMENT_ACTIONS:
		_assert_action_released(action, context)


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Touch joystick screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Touch joystick screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Touch joystick screenshot save failed with error %d" % save_error)
		return
	print("TOUCH_JOYSTICK_STEP_1_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _release_all_actions() -> void:
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)


func _finish() -> void:
	_release_all_actions()
	if failures.is_empty():
		quit(0)
	else:
		print("TOUCH_JOYSTICK_STEP_1_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
