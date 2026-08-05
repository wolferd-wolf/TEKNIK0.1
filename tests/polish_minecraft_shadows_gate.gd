extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const CHUNK_SIZE := 12
const BEFORE_PATH := "res://artifacts/shadow-artifact-before.png"
const AFTER_PATH := "res://artifacts/shadow-artifact-after.png"
const INVALID_TREE := Vector2i(2147483647, 2147483647)


func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var data = WORLD_DATA.new()
	var tree_origin := _find_tree_origin(data)
	_expect(tree_origin != INVALID_TREE, "A deterministic tree must exist for visual capture", failures)
	if tree_origin == INVALID_TREE:
		_finish(null, failures)
		return

	var chunk_coord := Vector2i(
		floori(float(tree_origin.x) / float(CHUNK_SIZE)),
		floori(float(tree_origin.y) / float(CHUNK_SIZE))
	)
	var heights := _height_cache(data, chunk_coord)
	var mesh_data: Dictionary = WORLD_MESHER.build(
		chunk_coord,
		heights,
		data.overrides,
		CHUNK_SIZE,
		WORLD_DATA.WORLD_HEIGHT,
		WORLD_DATA.SEA_LEVEL
	)
	_expect(int(mesh_data.get("face_count", 0)) > 0, "Controlled tree chunk must contain visible faces", failures)

	var test_scene := Node3D.new()
	test_scene.name = "ShadowArtifactComparison"
	root.add_child(test_scene)

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color(0.28, 0.55, 0.82)
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.72, 0.78, 0.86)
	environment_resource.ambient_light_energy = 0.42
	environment.environment = environment_resource
	test_scene.add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 0.75
	sun.shadow_blur = 0.15
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 72.0
	sun.directional_shadow_split_1 = 0.12
	sun.directional_shadow_split_2 = 0.3
	sun.directional_shadow_split_3 = 0.55
	sun.directional_shadow_blend_splits = false
	sun.directional_shadow_fade_start = 0.9
	test_scene.add_child(sun)

	var mesh_instance := _build_mesh_instance(mesh_data)
	mesh_instance.position = Vector3(chunk_coord.x * CHUNK_SIZE, 0, chunk_coord.y * CHUNK_SIZE)
	test_scene.add_child(mesh_instance)

	var surface: int = data.terrain_height(tree_origin.x, tree_origin.y)
	var canopy_target := Vector3(
		float(tree_origin.x) + 0.5,
		float(surface + WORLD_DATA.TREE_TRUNK_HEIGHT) + 0.25,
		float(tree_origin.y) + 0.5
	)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	camera.position = canopy_target + Vector3(-7.0, 1.0, 8.0)
	test_scene.add_child(camera)
	camera.look_at(canopy_target, Vector3.UP)

	await _settle_render(45)
	sun.shadow_reverse_cull_face = false
	await _settle_render(12)
	_capture(BEFORE_PATH, failures)

	sun.shadow_reverse_cull_face = true
	await _settle_render(12)
	_capture(AFTER_PATH, failures)

	_assert_shadow_contract(sun, failures)
	print("POLISH_MINECRAFT_SHADOWS_GATE_PASS tree=%s surface=%d chunk=%s before=%s after=%s" % [
		tree_origin,
		surface,
		chunk_coord,
		BEFORE_PATH,
		AFTER_PATH,
	])
	_finish(test_scene, failures)


func _build_mesh_instance(mesh_data: Dictionary) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data.get("vertices", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = mesh_data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = mesh_data.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_INDEX] = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	return mesh_instance


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


func _capture(path: String, failures: PackedStringArray) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "%s must produce an image" % path, failures)
	if image == null or image.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	_expect(image.save_png(absolute_path) == OK, "%s must save successfully" % path, failures)
	_expect(_sample_average_luminance(image) > 0.05, "%s must not be black" % path, failures)


func _settle_render(frame_count: int) -> void:
	for _frame in range(frame_count):
		await process_frame


func _find_tree_origin(data) -> Vector2i:
	for z in range(-48, 49):
		for x in range(-48, 49):
			if data.is_tree_origin(x, z):
				return Vector2i(x, z)
	return INVALID_TREE


func _height_cache(data, coord: Vector2i) -> PackedInt32Array:
	var width := CHUNK_SIZE + 2
	var heights := PackedInt32Array()
	heights.resize(width * width)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-1, CHUNK_SIZE + 1):
		for local_x in range(-1, CHUNK_SIZE + 1):
			var index := (local_z + 1) * width + local_x + 1
			heights[index] = data.terrain_height(origin_x + local_x, origin_z + local_z)
	return heights


func _sample_average_luminance(image: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0, image.get_height(), 24):
		for x in range(0, image.get_width(), 24):
			var color := image.get_pixel(x, y)
			total += (color.r + color.g + color.b) / 3.0
			count += 1
	return total / float(maxi(count, 1))


func _finish(test_scene: Node, failures: PackedStringArray) -> void:
	if is_instance_valid(test_scene):
		test_scene.queue_free()
	if failures.is_empty():
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
