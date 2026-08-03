extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/palette-step4.png"
const BLOCK_AIR := 0
const PALETTE_CASES := [
	{
		"slot": 1,
		"action": "select_block_1",
		"physical_keycode": 49,
		"block_id": 3,
		"name": "STONE",
		"column": Vector2i(-6, 4),
	},
	{
		"slot": 2,
		"action": "select_block_2",
		"physical_keycode": 50,
		"block_id": 2,
		"name": "DIRT",
		"column": Vector2i(-2, 4),
	},
	{
		"slot": 3,
		"action": "select_block_3",
		"physical_keycode": 51,
		"block_id": 1,
		"name": "GRASS",
		"column": Vector2i(2, 4),
	},
	{
		"slot": 4,
		"action": "select_block_4",
		"physical_keycode": 52,
		"block_id": 4,
		"name": "SAND",
		"column": Vector2i(6, 4),
	},
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
	_validate_input_map()

	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load: %s" % MAIN_SCENE)
		_finish()
		return

	var main := packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(24)

	var manager := main.get_node_or_null("ChunkManager")
	var player := main.get_node_or_null("Player")
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null:
		_fail("ChunkManager node is missing")
	if player == null:
		_fail("Player node is missing")
	if camera == null:
		_fail("Player camera is missing")
	if not failures.is_empty():
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(true)
	player.global_position = Vector3(10.5, 20.0, 10.5)
	manager.refresh_streaming(Vector3(0.5, 20.0, 0.5))
	await _wait_frames(12)

	var indicator := player.get_palette_indicator() as Label
	if indicator == null:
		_fail("Palette indicator was not created")
	elif not indicator.is_visible_in_tree():
		_fail("Palette indicator is not visible in the scene tree")
	else:
		_validate_indicator_rect(indicator)
		if not indicator.text.contains("[1] STONE"):
			_fail("Default palette text did not visibly select stone: %s" % indicator.text)

	if player.active_placement_block_id != 3:
		_fail("Default placement block was not stone ID 3")

	var placed_records: Array[String] = []
	for palette_case in PALETTE_CASES:
		await _select_action(palette_case["action"])

		var expected_id: int = palette_case["block_id"]
		var expected_slot: int = palette_case["slot"]
		var expected_name: String = palette_case["name"]
		if player.active_placement_block_id != expected_id:
			_fail(
				"%s selected block ID %d instead of %d"
				% [palette_case["action"], player.active_placement_block_id, expected_id]
			)
		if player.get_active_placement_block_name().to_upper() != expected_name:
			_fail(
				"Active block name mismatch for slot %d: %s"
				% [expected_slot, player.get_active_placement_block_name()]
			)
		if indicator != null and not indicator.text.contains(
			"[%d] %s" % [expected_slot, expected_name]
		):
			_fail(
				"Indicator did not visibly mark slot %d: %s"
				% [expected_slot, indicator.text]
			)

		var column: Vector2i = palette_case["column"]
		var surface_y := _find_surface_y(manager, column.x, column.y)
		if surface_y == -2147483648:
			_fail("No surface found for palette slot %d" % expected_slot)
			continue

		var placement_coord := Vector3i(column.x, surface_y + 1, column.y)
		if manager.get_block_world(placement_coord) != BLOCK_AIR:
			_fail("Palette placement coordinate was not air: %s" % placement_coord)
			continue
		if not player.place_block_at(placement_coord):
			_fail("Palette slot %d failed to place at %s" % [expected_slot, placement_coord])
			continue
		await _wait_frames(4)
		var placed_id: int = manager.get_block_world(placement_coord)
		if placed_id != expected_id:
			_fail(
				"Palette slot %d placed block ID %d instead of %d"
				% [expected_slot, placed_id, expected_id]
			)
		placed_records.append("%d:%s=%d" % [expected_slot, placement_coord, placed_id])

	camera.global_position = Vector3(11.0, 18.0, 13.0)
	camera.look_at(Vector3(0.5, 9.5, 4.5), Vector3.UP)
	await _wait_frames(12)
	await _capture_screenshot()

	if failures.is_empty():
		print("PALETTE_STEP_4_GATE_PASS")
		print("PALETTE_MAPPING=1:STONE,2:DIRT,3:GRASS,4:SAND")
		print("PALETTE_PLACEMENTS=%s" % ",".join(placed_records))
		if indicator != null:
			print("PALETTE_INDICATOR_TEXT=%s" % indicator.text)
	_finish()


func _validate_input_map() -> void:
	for palette_case in PALETTE_CASES:
		var action: StringName = palette_case["action"]
		if not InputMap.has_action(action):
			_fail("%s InputMap action is missing" % action)
			continue
		if not _has_physical_key_binding(action, palette_case["physical_keycode"]):
			_fail(
				"%s is not bound to physical number key %d"
				% [action, palette_case["physical_keycode"]]
			)


func _has_physical_key_binding(action: StringName, physical_keycode: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == physical_keycode:
			return true
	return false


func _select_action(action: StringName) -> void:
	Input.action_press(action, 1.0)
	await process_frame
	Input.action_release(action)
	await _wait_frames(2)


func _validate_indicator_rect(indicator: Label) -> void:
	var indicator_rect := indicator.get_global_rect()
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	if indicator_rect.size.x < 300.0 or indicator_rect.size.y < 30.0:
		_fail("Palette indicator is too small to be clearly visible: %s" % indicator_rect)
	if not viewport_rect.has_point(indicator_rect.get_center()):
		_fail("Palette indicator center is outside the viewport: %s" % indicator_rect)


func _find_surface_y(manager, world_x: int, world_z: int) -> int:
	for world_y in range(31, -17, -1):
		if manager.get_block_world(Vector3i(world_x, world_y, world_z)) != BLOCK_AIR:
			return world_y
	return -2147483648


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Palette screenshot capture returned an empty image")
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		_fail("Palette screenshot dimensions were %dx%d" % [image.get_width(), image.get_height()])
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if save_error != OK:
		_fail("Palette screenshot save failed with error %d" % save_error)
		return
	print("PALETTE_STEP_4_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("PALETTE_STEP_4_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
