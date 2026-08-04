extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

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
	_validate_baked_voxel_ambient_occlusion()

	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load")
		_finish()
		return

	var main := packed_scene.instantiate()
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	var player := main.get_node_or_null("Player") as CharacterBody3D
	var touch_controls := main.get_node_or_null("TouchControls")
	if sun == null:
		_fail("Sun node is missing")
	elif sun.shadow_enabled:
		_fail("Real-time directional shadow maps are still enabled")
	if player == null:
		_fail("Player node is missing")
	elif float(player.get("action_look_speed")) < 10.0:
		_fail("Action look speed is still too low: %.3f" % float(player.get("action_look_speed")))
	if touch_controls == null:
		_fail("TouchControls node is missing")
	elif float(touch_controls.get("look_drag_pixels_for_full_strength")) > 32.0:
		_fail("Touch drag requires too many pixels for full strength: %.3f" % float(touch_controls.get("look_drag_pixels_for_full_strength")))
	if not failures.is_empty():
		main.free()
		_finish()
		return

	root.add_child(main)
	await _wait_frames(8)
	player.set_physics_process(false)
	_release_look_actions()

	var viewport_size := root.get_visible_rect().size
	var look_start := Vector2(viewport_size.x * 0.75, minf(viewport_size.y * 0.35, viewport_size.y - 180.0))
	var baseline_yaw: float = player.rotation.y
	await _simulate_touch(7, look_start, true)
	await _simulate_drag(7, look_start + Vector2(64.0, 0.0), Vector2(64.0, 0.0))
	await process_frame
	var yaw_delta := absf(wrapf(player.rotation.y - baseline_yaw, -PI, PI))
	if yaw_delta < 0.15:
		_fail("A 64-pixel mobile swipe still turns too slowly: %.5f radians" % yaw_delta)
	await _simulate_touch(7, look_start + Vector2(64.0, 0.0), false)
	_release_look_actions()

	if failures.is_empty():
		print("VANILLA_LIGHTING_FAST_LOOK_GATE_PASS")
		print("VANILLA_LIGHTING_SHADOW_MAPS=disabled")
		print("VANILLA_LIGHTING_AO=baked per vertex")
		print("MOBILE_LOOK_64PX_YAW_RADIANS=%.5f" % yaw_delta)
		print("MOBILE_LOOK_SPEED=%.3f" % float(player.get("action_look_speed")))
		print("MOBILE_LOOK_FULL_STRENGTH_PIXELS=%.3f" % float(touch_controls.get("look_drag_pixels_for_full_strength")))
	_finish()


func _validate_baked_voxel_ambient_occlusion() -> void:
	var heights := PackedInt32Array()
	heights.resize(9)
	heights.fill(-1)
	var baseline_overrides := {
		"0,0,0": 3,
	}
	var baseline: Dictionary = WORLD_MESHER.build(
		Vector2i.ZERO,
		heights,
		baseline_overrides,
		1,
		4,
		0
	)
	var baseline_colors: PackedColorArray = baseline.get("colors", PackedColorArray())
	if baseline_colors.size() < 4:
		_fail("Mesher did not emit the expected top face")
		return
	for index in range(1, 4):
		if not baseline_colors[0].is_equal_approx(baseline_colors[index]):
			_fail("Unoccluded top face has inconsistent vertex lighting")
			return

	var occluded_overrides := baseline_overrides.duplicate(true)
	occluded_overrides["-1,1,0"] = 3
	occluded_overrides["0,1,-1"] = 3
	occluded_overrides["-1,1,-1"] = 3
	var occluded: Dictionary = WORLD_MESHER.build(
		Vector2i.ZERO,
		heights,
		occluded_overrides,
		1,
		4,
		0
	)
	var occluded_colors: PackedColorArray = occluded.get("colors", PackedColorArray())
	if occluded_colors.size() < 4:
		_fail("Occluded mesher result did not emit the expected top face")
		return
	var dark_corner := _luminance(occluded_colors[0])
	var open_corner := _luminance(occluded_colors[2])
	if dark_corner >= open_corner - 0.08:
		_fail("Baked ambient occlusion did not darken the enclosed corner: %.4f vs %.4f" % [dark_corner, open_corner])


func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


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
	await process_frame


func _release_look_actions() -> void:
	for action in ["look_left", "look_right", "look_up", "look_down"]:
		Input.action_release(action)


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		quit(1)
