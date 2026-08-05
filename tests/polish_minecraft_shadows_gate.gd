extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const SCREENSHOT_PATH := "res://artifacts/shadow-artifact-after.png"
const INVALID_TREE := Vector2i(2147483647, 2147483647)


func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var main := MAIN_SCENE.instantiate()
	var player := main.get_node_or_null("Player") as CharacterBody3D
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	_expect(player != null and camera != null, "Main scene must provide player and camera", failures)
	_expect(sun != null, "Main scene must contain a DirectionalLight3D named Sun", failures)
	if player == null or camera == null or sun == null:
		_finish(main, failures)
		return

	_assert_shadow_contract(sun, failures)

	var data = WORLD_DATA.new()
	var tree_origin := _find_tree_origin(data)
	_expect(tree_origin != INVALID_TREE, "A deterministic tree must exist for visual capture", failures)
	if tree_origin == INVALID_TREE:
		_finish(main, failures)
		return

	var surface: int = data.terrain_height(tree_origin.x, tree_origin.y)
	var canopy_target := Vector3(
		float(tree_origin.x) + 0.5,
		float(surface + WORLD_DATA.TREE_TRUNK_HEIGHT) + 0.4,
		float(tree_origin.y) + 0.5
	)
	player.position = Vector3(
		float(tree_origin.x) - 7.0,
		float(surface) + 2.0,
		float(tree_origin.y) + 8.0
	)
	player.set_process(false)
	player.set_physics_process(false)
	camera.fov = 62.0

	root.add_child(main)
	await process_frame
	camera.look_at(canopy_target, Vector3.UP)

	for _frame in range(180):
		await process_frame

	_hide_canvas_layers(main)
	await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "Rendered shadow capture must produce an image", failures)
	if image != null and not image.is_empty():
		var absolute_path := ProjectSettings.globalize_path(SCREENSHOT_PATH)
		DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
		var save_error := image.save_png(absolute_path)
		_expect(save_error == OK, "Shadow artifact screenshot must save successfully", failures)
		_expect(_sample_average_luminance(image) > 0.05, "Shadow artifact screenshot must not be black", failures)

	print("POLISH_MINECRAFT_SHADOWS_GATE_PASS reverse_cull=%s tree=%s surface=%d screenshot=%s" % [
		sun.shadow_reverse_cull_face,
		tree_origin,
		surface,
		SCREENSHOT_PATH,
	])
	_finish(main, failures)


func _assert_shadow_contract(sun: DirectionalLight3D, failures: PackedStringArray) -> void:
	_expect(sun.shadow_enabled, "Sun shadows must be enabled", failures)
	_expect(sun.shadow_reverse_cull_face, "Closed voxel meshes must use reverse shadow culling to prevent triangle acne", failures)
	_expect(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Sun must use four cascaded shadow splits", failures)
	_expect(not sun.directional_shadow_blend_splits, "Split blending must remain disabled for crisp block-style transitions", failures)
	_expect(sun.directional_shadow_max_distance <= 72.0, "Shadow distance must stay bounded for mobile resolution and stability", failures)
	_expect(sun.directional_shadow_fade_start >= 0.85, "Shadows must retain contrast through most of the configured range", failures)
	_expect(sun.shadow_blur <= 0.2, "Shadow blur must remain low for Minecraft-style hard edges", failures)
	_expect(sun.shadow_bias >= 0.02 and sun.shadow_bias <= 0.06, "Shadow bias must stay in the tuned range", failures)
	_expect(sun.shadow_normal_bias >= 0.5 and sun.shadow_normal_bias <= 1.0, "Normal bias must stay in the tuned voxel range", failures)
	_expect(sun.directional_shadow_split_1 < sun.directional_shadow_split_2, "First cascade split must precede second", failures)
	_expect(sun.directional_shadow_split_2 < sun.directional_shadow_split_3, "Second cascade split must precede third", failures)


func _find_tree_origin(data) -> Vector2i:
	for z in range(-48, 49):
		for x in range(-48, 49):
			if data.is_tree_origin(x, z):
				return Vector2i(x, z)
	return INVALID_TREE


func _hide_canvas_layers(main: Node) -> void:
	for child in main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false


func _sample_average_luminance(image: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0, image.get_height(), 24):
		for x in range(0, image.get_width(), 24):
			var color := image.get_pixel(x, y)
			total += (color.r + color.g + color.b) / 3.0
			count += 1
	return total / float(maxi(count, 1))


func _finish(main: Node, failures: PackedStringArray) -> void:
	if is_instance_valid(main):
		main.queue_free()
	if failures.is_empty():
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
