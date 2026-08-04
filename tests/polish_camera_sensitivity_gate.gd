extends SceneTree

class MockPlayer:
	extends Node
	var action_look_speed: float = 2.2
	var applied_deltas: Array[Vector2] = []

	func apply_look_delta(delta: Vector2) -> void:
		applied_deltas.append(delta)


func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()
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

	var unrelated_drag := InputEventScreenDrag.new()
	unrelated_drag.index = 9
	unrelated_drag.position = Vector2(1080, 200)
	unrelated_drag.relative = Vector2(100, 100)
	adapter.call("_input", unrelated_drag)
	_expect(player.applied_deltas.size() == 1, "unclaimed touch must not rotate camera", failures)

	look_touch.pressed = false
	adapter.call("_input", look_touch)
	_expect(int(adapter.call("get_active_look_touch_index")) == -1, "look touch release must clear capture", failures)

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	_expect(main_scene != null, "main scene must load", failures)
	if main_scene != null:
		var main_instance := main_scene.instantiate()
		_expect(main_instance.get_node_or_null("MobileCameraSensitivity") != null, "main scene must wire the sensitivity adapter", failures)
		main_instance.free()

	if failures.is_empty():
		print("CAMERA_SENSITIVITY_GATE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
