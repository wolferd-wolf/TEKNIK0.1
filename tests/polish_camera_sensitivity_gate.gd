extends SceneTree

class MockPlayer:
	extends Node
	var action_look_speed: float = 2.2
	var applied_deltas: Array[Vector2] = []

	func apply_look_delta(delta: Vector2) -> void:
		applied_deltas.append(delta)


func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()
	await _run_adapter_unit_gate(failures)
	await _run_main_scene_input_gate(failures)

	if failures.is_empty():
		print("CAMERA_SENSITIVITY_GATE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _run_adapter_unit_gate(failures: PackedStringArray) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)

	var host := Node.new()
	viewport.add_child(host)
	var player := MockPlayer.new()
	player.name = "Player"
	host.add_child(player)

	var adapter_script: Script = load("res://scripts/player/mobile_camera_sensitivity.gd")
	var adapter: Node = adapter_script.new()
	adapter.name = "MobileCameraSensitivity"
	adapter.set("player_path", NodePath("../Player"))
	adapter.set("force_enabled_for_tests", true)
	adapter.set("radians_per_drag_pixel", 0.0035)
	host.add_child(adapter)
	await process_frame

	_expect(bool(adapter.call("is_mobile_look_enabled")), "adapter must enable in forced test mode", failures)
	_expect(bool(adapter.call("has_input_precedence")), "adapter must own first input dispatch position", failures)
	_expect(is_equal_approx(player.action_look_speed, 0.0), "legacy frame-scaled action look must be disabled", failures)

	var left_touch := InputEventScreenTouch.new()
	left_touch.index = 1
	left_touch.position = Vector2(200, 200)
	left_touch.pressed = true
	adapter.call("_input", left_touch)
	_expect(int(adapter.call("get_active_look_touch_index")) == -1, "left-half touch must not claim camera look", failures)

	var bottom_touch := InputEventScreenTouch.new()
	bottom_touch.index = 2
	bottom_touch.position = Vector2(1000, 680)
	bottom_touch.pressed = true
	adapter.call("_input", bottom_touch)
	_expect(int(adapter.call("get_active_look_touch_index")) == -1, "bottom action area must remain reserved", failures)

	var look_touch := InputEventScreenTouch.new()
	look_touch.index = 3
	look_touch.position = Vector2(1000, 240)
	look_touch.pressed = true
	adapter.call("_input", look_touch)
	_expect(int(adapter.call("get_active_look_touch_index")) == 3, "right-side look touch must be captured", failures)

	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(1040, 220)
	drag.relative = Vector2(40, -20)
	adapter.call("_input", drag)
	_expect(player.applied_deltas.size() == 1, "captured drag must rotate exactly once", failures)
	if player.applied_deltas.size() == 1:
		_expect(player.applied_deltas[0].is_equal_approx(Vector2(0.14, -0.07)), "drag pixels must map directly through configured sensitivity", failures)

	look_touch.pressed = false
	adapter.call("_input", look_touch)
	_expect(int(adapter.call("get_active_look_touch_index")) == -1, "look touch release must clear capture", failures)
	viewport.queue_free()
	await process_frame


func _run_main_scene_input_gate(failures: PackedStringArray) -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	_expect(main_scene != null, "main scene must load", failures)
	if main_scene == null:
		return

	var main_instance := main_scene.instantiate()
	var adapter := main_instance.get_node_or_null("MobileCameraSensitivity")
	var touch_controls := main_instance.get_node_or_null("TouchControls")
	var player := main_instance.get_node_or_null("Player") as Node3D
	var camera := main_instance.get_node_or_null("Player/Camera3D") as Camera3D
	_expect(adapter != null, "main scene must wire the sensitivity adapter", failures)
	_expect(touch_controls != null, "main scene must retain legacy touch controls", failures)
	_expect(player != null and camera != null, "main scene must provide player and camera", failures)
	if adapter == null or touch_controls == null or player == null or camera == null:
		main_instance.free()
		return

	adapter.set("force_enabled_for_tests", true)
	root.add_child(main_instance)
	await process_frame
	_expect(bool(adapter.call("is_mobile_look_enabled")), "main-scene adapter must enable in forced mode", failures)
	_expect(bool(adapter.call("has_input_precedence")), "main-scene adapter must run before the handling touch overlay", failures)
	_expect(is_equal_approx(float(player.get("action_look_speed")), 0.0), "main-scene legacy action rotation must be disabled", failures)

	var viewport_size := root.get_visible_rect().size
	_expect(viewport_size.x > 0.0 and viewport_size.y > 240.0, "root viewport must have a usable test size", failures)
	var look_position := Vector2(viewport_size.x * 0.75, viewport_size.y * 0.3)
	var touch := InputEventScreenTouch.new()
	touch.index = 41
	touch.position = look_position
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	_expect(int(adapter.call("get_active_look_touch_index")) == 41, "real scene propagation must reach direct camera adapter before handling", failures)
	_expect(int(touch_controls.call("get_active_look_touch_index")) == 41, "test must also exercise the legacy overlay conflict path", failures)

	var yaw_before := player.rotation.y
	var pitch_before := camera.rotation.x
	var drag := InputEventScreenDrag.new()
	drag.index = 41
	drag.position = look_position + Vector2(40, -20)
	drag.relative = Vector2(40, -20)
	Input.parse_input_event(drag)
	await process_frame
	_expect(is_equal_approx(player.rotation.y, yaw_before - 0.14), "scene-level Android drag must rotate yaw from raw pixels", failures)
	_expect(is_equal_approx(camera.rotation.x, pitch_before + 0.07), "scene-level Android drag must rotate pitch from raw pixels", failures)

	touch.pressed = false
	touch.position = drag.position
	Input.parse_input_event(touch)
	await process_frame
	_expect(int(adapter.call("get_active_look_touch_index")) == -1, "scene-level release must clear direct camera capture", failures)

	main_instance.queue_free()
	await process_frame


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
