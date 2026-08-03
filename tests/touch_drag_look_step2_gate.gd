extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/touch-drag-look-step2.png"
const LOOK_LEFT_ACTION := StringName("look_left")
const LOOK_RIGHT_ACTION := StringName("look_right")
const LOOK_UP_ACTION := StringName("look_up")
const LOOK_DOWN_ACTION := StringName("look_down")
const LOOK_ACTIONS := [
	LOOK_LEFT_ACTION,
	LOOK_RIGHT_ACTION,
	LOOK_UP_ACTION,
	LOOK_DOWN_ACTION,
]
const MOVEMENT_ACTIONS := [
	StringName("move_left"),
	StringName("move_right"),
	StringName("move_forward"),
	StringName("move_backward"),
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
	_validate_input_actions()

	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(30)

	var player := main.get_node_or_null("Player") as CharacterBody3D
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	var touch_controls := main.get_node_or_null("TouchControls")
	if player == null:
		_fail("Player node is missing")
	if camera == null:
		_fail("Player camera is missing")
	if touch_controls == null:
		_fail("TouchControls node is missing")
	if not failures.is_empty():
		_finish()
		return

	var required_methods := [
		"get_joystick_center",
		"get_active_touch_index",
		"get_active_look_touch_index",
		"get_look_vector",
		"get_look_hint",
	]
	for method_name in required_methods:
		if not touch_controls.has_method(method_name):
			_fail("TouchControls is missing method %s" % method_name)
	if not failures.is_empty():
		_finish()
		return

	player.set_physics_process(false)
	_release_all_actions()
	await _wait_frames(2)

	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	var look_hint := touch_controls.get_look_hint() as PanelContainer
	if look_hint == null:
		_fail("Rendered drag-look hint is missing")
		_finish()
		return
	var hint_rect := look_hint.get_global_rect()
	if not look_hint.is_visible_in_tree():
		_fail("Drag-look hint is not visible in the rendered tree")
	if not viewport_rect.encloses(hint_rect):
		_fail("Drag-look hint lies outside the viewport: %s" % hint_rect)
	if hint_rect.get_center().x <= viewport_rect.size.x * 0.5:
		_fail("Drag-look hint is not on the right side: %s" % hint_rect)
	_assert_hint_border(look_hint, 2, "inactive look hint")

	var baseline_yaw: float = player.rotation.y
	var baseline_pitch: float = camera.rotation.x
	var joystick_center: Vector2 = touch_controls.get_joystick_center()

	_inject_touch(11, joystick_center, true)
	if int(touch_controls.get_active_touch_index()) != 11:
		_fail("Left-side joystick touch was not captured")
	if int(touch_controls.get_active_look_touch_index()) != -1:
		_fail("Left-side touch bled into drag-look capture")
	_inject_drag(11, joystick_center + Vector2(60.0, -60.0), Vector2(60.0, -60.0))
	_assert_all_actions_released(LOOK_ACTIONS, "left-side joystick drag look boundary")
	if not (touch_controls.get_look_vector() as Vector2).is_zero_approx():
		_fail("Left-side joystick drag changed the look vector")
	await _wait_frames(3)
	if absf(player.rotation.y - baseline_yaw) > 0.001:
		_fail("Left-side joystick drag changed yaw from %.5f to %.5f" % [baseline_yaw, player.rotation.y])
	if absf(camera.rotation.x - baseline_pitch) > 0.001:
		_fail("Left-side joystick drag changed pitch from %.5f to %.5f" % [baseline_pitch, camera.rotation.x])
	_inject_touch(11, joystick_center + Vector2(60.0, -60.0), false)
	await _wait_frames(2)
	_assert_all_actions_released(MOVEMENT_ACTIONS, "left joystick release")

	var look_start := Vector2(960.0, 300.0)
	_inject_touch(22, look_start, true)
	if int(touch_controls.get_active_look_touch_index()) != 22:
		_fail("Right-side touch was not captured for drag-look")
	if int(touch_controls.get_active_touch_index()) != -1:
		_fail("Right-side drag-look touch bled into joystick capture")
	_assert_hint_border(look_hint, 4, "active look hint")

	var up_right_relative := Vector2(64.0, -64.0)
	_inject_drag(22, look_start + up_right_relative, up_right_relative)
	_assert_action_pressed(LOOK_RIGHT_ACTION, 0.69, "up-right drag right")
	_assert_action_pressed(LOOK_UP_ACTION, 0.69, "up-right drag up")
	_assert_action_released(LOOK_LEFT_ACTION, "up-right drag left")
	_assert_action_released(LOOK_DOWN_ACTION, "up-right drag down")
	_assert_all_actions_released(MOVEMENT_ACTIONS, "right-side drag movement boundary")
	var up_right_right_strength: float = Input.get_action_strength(LOOK_RIGHT_ACTION)
	var up_right_up_strength: float = Input.get_action_strength(LOOK_UP_ACTION)
	var active_look_vector: Vector2 = touch_controls.get_look_vector()
	if active_look_vector.x < 0.69 or active_look_vector.y > -0.69:
		_fail("Touch look vector did not reflect up-right drag: %s" % active_look_vector)

	await _wait_frames(3)
	_assert_all_actions_released(LOOK_ACTIONS, "up-right look pulse completion")
	var yaw_after_up_right: float = player.rotation.y
	var pitch_after_up_right: float = camera.rotation.x
	if yaw_after_up_right >= baseline_yaw - 0.01:
		_fail("Rightward touch drag did not rotate yaw leftward through existing look logic: %.5f -> %.5f" % [baseline_yaw, yaw_after_up_right])
	if pitch_after_up_right <= baseline_pitch + 0.01:
		_fail("Upward touch drag did not increase camera pitch through existing look logic: %.5f -> %.5f" % [baseline_pitch, pitch_after_up_right])
	if int(touch_controls.get_active_look_touch_index()) != 22:
		_fail("Drag-look touch stopped being tracked after its action pulse")

	await _capture_screenshot()

	var down_left_relative := Vector2(-64.0, 64.0)
	_inject_drag(22, look_start, down_left_relative)
	_assert_action_pressed(LOOK_LEFT_ACTION, 0.69, "down-left drag left")
	_assert_action_pressed(LOOK_DOWN_ACTION, 0.69, "down-left drag down")
	_assert_action_released(LOOK_RIGHT_ACTION, "down-left drag right")
	_assert_action_released(LOOK_UP_ACTION, "down-left drag up")
	await _wait_frames(3)
	if player.rotation.y <= yaw_after_up_right + 0.01:
		_fail("Leftward touch drag did not reverse yaw direction")
	if camera.rotation.x >= pitch_after_up_right - 0.01:
		_fail("Downward touch drag did not reverse pitch direction")

	_inject_touch(22, look_start, false)
	await _wait_frames(2)
	if int(touch_controls.get_active_look_touch_index()) != -1:
		_fail("Released right-side touch remained captured")
	_assert_all_actions_released(LOOK_ACTIONS, "right-side touch release")
	_assert_hint_border(look_hint, 2, "released look hint")

	var pitch_limit_degrees: float = float(player.get("pitch_limit_degrees"))
	var pitch_limit_radians: float = deg_to_rad(pitch_limit_degrees)
	var clamp_touch := Vector2(1000.0, 260.0)
	_inject_touch(33, clamp_touch, true)
	for _drag_index in range(45):
		_inject_drag(33, clamp_touch, Vector2(0.0, -96.0))
		_assert_action_pressed(LOOK_UP_ACTION, 0.99, "upper pitch clamp drag")
		await _wait_frames(3)
	var upper_clamped_pitch: float = camera.rotation.x
	if upper_clamped_pitch > pitch_limit_radians + 0.001:
		_fail("Upper pitch exceeded clamp: %.5f > %.5f" % [upper_clamped_pitch, pitch_limit_radians])
	if upper_clamped_pitch < pitch_limit_radians - 0.03:
		_fail("Repeated upward touch drag did not reach upper pitch clamp: %.5f" % upper_clamped_pitch)

	for _drag_index in range(55):
		_inject_drag(33, clamp_touch, Vector2(0.0, 96.0))
		_assert_action_pressed(LOOK_DOWN_ACTION, 0.99, "lower pitch clamp drag")
		await _wait_frames(3)
	var lower_clamped_pitch: float = camera.rotation.x
	if lower_clamped_pitch < -pitch_limit_radians - 0.001:
		_fail("Lower pitch exceeded clamp: %.5f < %.5f" % [lower_clamped_pitch, -pitch_limit_radians])
	if lower_clamped_pitch > -pitch_limit_radians + 0.03:
		_fail("Repeated downward touch drag did not reach lower pitch clamp: %.5f" % lower_clamped_pitch)
	_inject_touch(33, clamp_touch, false)
	await _wait_frames(2)
	_assert_all_actions_released(LOOK_ACTIONS, "pitch clamp touch release")

	if failures.is_empty():
		print("TOUCH_DRAG_LOOK_STEP_2_GATE_PASS")
		print("TOUCH_DRAG_LOOK_INPUTMAP=look_right %.3f + look_up %.3f during simulated up-right drag" % [
			up_right_right_strength,
			up_right_up_strength,
		])
		print("TOUCH_DRAG_LOOK_ROTATION=yaw %.5f->%.5f; pitch %.5f->%.5f" % [
			baseline_yaw,
			yaw_after_up_right,
			baseline_pitch,
			pitch_after_up_right,
		])
		print("TOUCH_DRAG_LOOK_PITCH_CLAMP=+%.1fdeg %.5f; -%.1fdeg %.5f" % [
			pitch_limit_degrees,
			upper_clamped_pitch,
			pitch_limit_degrees,
			lower_clamped_pitch,
		])
		print("TOUCH_DRAG_LOOK_BOUNDARY=left joystick drag left look actions and camera unchanged; right look drag left movement actions unchanged")
		print("TOUCH_DRAG_LOOK_SIMULATION=InputEventScreenTouch+InputEventScreenDrag through Input.parse_input_event")
	_finish()


func _validate_input_actions() -> void:
	for action in LOOK_ACTIONS:
		if not InputMap.has_action(action):
			_fail("Look InputMap action is missing: %s" % action)
	for action in MOVEMENT_ACTIONS:
		if not InputMap.has_action(action):
			_fail("Movement InputMap action is missing: %s" % action)


func _inject_touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)


func _inject_drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	event.velocity = relative * 60.0
	event.pressure = 1.0
	Input.parse_input_event(event)


func _assert_action_pressed(action: StringName, minimum_strength: float, context: String) -> void:
	if not Input.is_action_pressed(action):
		_fail("%s did not press InputMap action %s" % [context, action])
		return
	var strength: float = Input.get_action_strength(action)
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
	var strength: float = Input.get_action_strength(action)
	if strength > 0.001:
		_fail("%s left non-zero strength on %s: %.3f" % [context, action, strength])


func _assert_all_actions_released(actions: Array, context: String) -> void:
	for action in actions:
		_assert_action_released(action as StringName, context)


func _assert_hint_border(hint: PanelContainer, expected_width: int, context: String) -> void:
	var style := hint.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		_fail("%s has no StyleBoxFlat" % context)
		return
	if style.border_width_left != expected_width:
		_fail("%s border was %d, expected %d" % [context, style.border_width_left, expected_width])


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Drag-look screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Drag-look screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Drag-look screenshot save failed with error %d" % save_error)
		return
	print("TOUCH_DRAG_LOOK_STEP_2_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _release_all_actions() -> void:
	for action in LOOK_ACTIONS:
		Input.action_release(action)
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)


func _finish() -> void:
	_release_all_actions()
	if failures.is_empty():
		quit(0)
	else:
		print("TOUCH_DRAG_LOOK_STEP_2_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
