extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const CHUNK_SIZE := 12
const CAPTURE_SIZE := Vector2i(1280, 720)
const BEFORE_PATH := "res://artifacts/shadow-artifact-before.png"
const AFTER_PATH := "res://artifacts/shadow-artifact-after.png"
const INVALID_TREE := Vector2i(2147483647, 2147483647)


func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var main := MAIN_SCENE.instantiate()
	var production_sun := main.get_node_or_null("Sun") as DirectionalLight3D
	_expect(production_sun != null, "Production scene must contain Sun", failures)
	if production_sun == null:
		_finish([], main, failures)
		return
	_assert_shadow_contract(production_sun, failures)

	var data = WORLD_DATA.new()
	var tree_origin := _find_tree_origin(data)
	_expect(tree_origin != INVALID_TREE, "A deterministic tree must exist for visual capture", failures)
	if tree_origin == INVALID_TREE:
		_finish([], main, failures)
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
	_assert_mesh_winding(mesh_data, failures)

	var surface: int = data.terrain_height(tree_origin.x, tree_origin.y)
	var before := _build_capture_viewport(
		mesh_data,
		chunk_coord,
		tree_origin,
		surface,
		production_sun,
		false,
		"ProductionNormalCullViewport"
	)
	var after := _build_capture_viewport(
		mesh_data,
		chunk_coord,
		tree_origin,
		surface,
		production_sun,
		true,
		"ReverseCullReferenceViewport"
	)
	root.add_child(before)
	root.add_child(after)

	for _frame in range(90):
		await process_frame
	await RenderingServer.frame_post_draw

	_capture_viewport(before, BEFORE_PATH, failures)
	_capture_viewport(after, AFTER_PATH, failures)

	print("POLISH_MINECRAFT_SHADOWS_GATE_PASS tree=%s surface=%d chunk=%s normal=%s reverse_reference=%s" % [
		tree_origin,
		surface,
		chunk_coord,
		BEFORE_PATH,
		AFTER_PATH,
	])
	_finish([before, after], main, failures)


func _build_capture_viewport(
	mesh_data: Dictionary,
	chunk_coord: Vector2i,
	tree_origin: Vector2i,
	surface: int,
	production_sun: DirectionalLight3D,
	reverse_cull: bool,
	viewport_name: String
) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = CAPTURE_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X

	var scene := Node3D.new()
	scene.name = "ControlledTreeShadowScene"
	viewport.add_child(scene)

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color(0.28, 0.55, 0.82)
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.72, 0.78, 0.86)
	environment_resource.ambient_light_energy = 0.48
	environment.environment = environment_resource
	scene.add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = production_sun.rotation
	sun.light_color = production_sun.light_color
	sun.light_energy = production_sun.light_energy
	sun.shadow_enabled = production_sun.shadow_enabled
	sun.shadow_reverse_cull_face = reverse_cull
	sun.shadow_bias = production_sun.shadow_bias
	sun.shadow_normal_bias = production_sun.shadow_normal_bias
	sun.shadow_blur = production_sun.shadow_blur
	sun.directional_shadow_mode = production_sun.directional_shadow_mode
	sun.directional_shadow_max_distance = production_sun.directional_shadow_max_distance
	sun.directional_shadow_split_1 = production_sun.directional_shadow_split_1
	sun.directional_shadow_split_2 = production_sun.directional_shadow_split_2
	sun.directional_shadow_split_3 = production_sun.directional_shadow_split_3
	sun.directional_shadow_blend_splits = production_sun.directional_shadow_blend_splits
	sun.directional_shadow_fade_start = production_sun.directional_shadow_fade_start
	scene.add_child(sun)

	var mesh_instance := _build_mesh_instance(mesh_data)
	mesh_instance.position = Vector3(chunk_coord.x * CHUNK_SIZE, 0, chunk_coord.y * CHUNK_SIZE)
	scene.add_child(mesh_instance)

	var canopy_target := Vector3(
		float(tree_origin.x) + 0.5,
		float(surface + WORLD_DATA.TREE_TRUNK_HEIGHT) + 0.25,
		float(tree_origin.y) + 0.5
	)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 42.0
	scene.add_child(camera)
	camera.look_at_from_position(
		canopy_target + Vector3(-7.0, 0.8, 8.0),
		canopy_target,
		Vector3.UP
	)
	return viewport


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
	material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.surface_set_material(0, material)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	return mesh_instance


func _assert_shadow_contract(sun: DirectionalLight3D, failures: PackedStringArray) -> void:
	_expect(sun.shadow_enabled, "Sun shadows must be enabled", failures)
	_expect(not sun.shadow_reverse_cull_face, "Corrected voxel winding must use normal shadow culling", failures)
	_expect(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Sun must use four cascaded shadow splits", failures)
	_expect(not sun.directional_shadow_blend_splits, "Split blending must remain disabled for crisp block-style transitions", failures)
	_expect(sun.directional_shadow_max_distance <= 72.0, "Shadow distance must stay bounded for mobile", failures)
	_expect(sun.directional_shadow_fade_start >= 0.85, "Shadows must retain contrast through most of their range", failures)
	_expect(sun.shadow_blur <= 0.2, "Shadow blur must remain low for hard block edges", failures)
	_expect(sun.shadow_bias >= 0.02 and sun.shadow_bias <= 0.06, "Shadow bias must stay in the tuned range", failures)
	_expect(sun.shadow_normal_bias >= 0.5 and sun.shadow_normal_bias <= 1.0, "Normal bias must stay in the tuned voxel range", failures)


func _assert_mesh_winding(mesh_data: Dictionary, failures: PackedStringArray) -> void:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var corrected_triangles := 0
	var bad_triangles := 0
	for index_offset in range(0, indices.size(), 3):
		var index_a := indices[index_offset]
		var index_b := indices[index_offset + 1]
		var index_c := indices[index_offset + 2]
		var cross_normal := (vertices[index_b] - vertices[index_a]).cross(
			vertices[index_c] - vertices[index_a]
		).normalized()
		if cross_normal.dot(normals[index_a]) < -0.99:
			corrected_triangles += 1
		else:
			bad_triangles += 1
	_expect(bad_triangles == 0, "Production tree chunk contains %d incorrectly wound triangles" % bad_triangles, failures)
	if bad_triangles == 0:
		print("SHADOW_MESH_WINDING_PASS triangles=%d" % corrected_triangles)


func _capture_viewport(viewport: SubViewport, path: String, failures: PackedStringArray) -> void:
	var image := viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "%s must produce an image" % path, failures)
	if image == null or image.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	_expect(image.save_png(absolute_path) == OK, "%s must save successfully" % path, failures)
	_expect(_sample_average_luminance(image) > 0.05, "%s must not be black" % path, failures)
	_expect(_non_background_fraction(image, Color(0.28, 0.55, 0.82)) > 0.08, "%s must visibly frame the tree chunk" % path, failures)


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


func _non_background_fraction(image: Image, background: Color) -> float:
	var different := 0
	var count := 0
	var background_rgb := Vector3(background.r, background.g, background.b)
	for y in range(0, image.get_height(), 12):
		for x in range(0, image.get_width(), 12):
			var color := image.get_pixel(x, y)
			var color_rgb := Vector3(color.r, color.g, color.b)
			if color_rgb.distance_to(background_rgb) > 0.08:
				different += 1
			count += 1
	return float(different) / float(maxi(count, 1))


func _finish(viewports: Array, main: Node, failures: PackedStringArray) -> void:
	for viewport in viewports:
		if is_instance_valid(viewport):
			viewport.queue_free()
	if is_instance_valid(main):
		main.free()
	if failures.is_empty():
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
