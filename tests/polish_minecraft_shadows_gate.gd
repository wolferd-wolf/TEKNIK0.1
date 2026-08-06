extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const CHUNK_SIZE := 3
const WORLD_HEIGHT := 8
const SEA_LEVEL := 0
const CACHE_PADDING := 2
const CAPTURE_SIZE := Vector2i(960, 540)
const CAPTURE_PATH := "res://artifacts/vanilla-lighting.png"


func _init() -> void:
	var failures := PackedStringArray()
	_assert_face_dimming(failures)

	var heights := _empty_heights()
	var overrides := _ao_fixture_overrides()
	var cache_width := CHUNK_SIZE + CACHE_PADDING * 2
	_assert_corner_ambient_occlusion(heights, overrides, cache_width, failures)
	_assert_leaf_skylight(heights, cache_width, failures)

	var mesh_data := WORLD_MESHER.build(
		Vector2i.ZERO,
		heights,
		overrides,
		CHUNK_SIZE,
		WORLD_HEIGHT,
		SEA_LEVEL
	)
	_assert_mesh_contract(mesh_data, failures)

	var main := MAIN_SCENE.instantiate()
	var chunk_manager := main.get_node_or_null("ChunkManager")
	_expect(chunk_manager != null, "Main scene must contain ChunkManager", failures)
	root.add_child(main)
	await process_frame
	_assert_runtime_contract(main, failures)

	var viewport := _build_capture_viewport(mesh_data)
	root.add_child(viewport)
	for _frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	_capture(viewport, failures)

	print("VANILLA_FACE_DIMMING_PASS")
	print("VANILLA_CORNER_AO_PASS")
	print("VANILLA_SKYLIGHT_PASS")
	print("VANILLA_LIGHTING_GATE_PASS capture=%s" % CAPTURE_PATH)
	_finish(viewport, main, failures)


func _assert_face_dimming(failures: PackedStringArray) -> void:
	_expect(is_equal_approx(WORLD_MESHER._face_shade(0), 1.0), "Up face must use vanilla brightness 1.0", failures)
	_expect(is_equal_approx(WORLD_MESHER._face_shade(1), 0.5), "Down face must use vanilla brightness 0.5", failures)
	_expect(is_equal_approx(WORLD_MESHER._face_shade(2), 0.6), "East face must use vanilla brightness 0.6", failures)
	_expect(is_equal_approx(WORLD_MESHER._face_shade(3), 0.6), "West face must use vanilla brightness 0.6", failures)
	_expect(is_equal_approx(WORLD_MESHER._face_shade(4), 0.8), "South face must use vanilla brightness 0.8", failures)
	_expect(is_equal_approx(WORLD_MESHER._face_shade(5), 0.8), "North face must use vanilla brightness 0.8", failures)


func _assert_corner_ambient_occlusion(
	heights: PackedInt32Array,
	overrides: Dictionary,
	cache_width: int,
	failures: PackedStringArray
) -> void:
	var cell := Vector3i(1, 1, 1)
	var dark_level: int = WORLD_MESHER._vertex_ao_level(
		cell,
		0,
		Vector3(WORLD_MESHER.FACE_VERTICES[0][0]),
		Vector3i.ZERO,
		heights,
		overrides,
		cache_width,
		CACHE_PADDING,
		WORLD_HEIGHT,
		SEA_LEVEL
	)
	var open_level: int = WORLD_MESHER._vertex_ao_level(
		cell,
		0,
		Vector3(WORLD_MESHER.FACE_VERTICES[0][2]),
		Vector3i.ZERO,
		heights,
		overrides,
		cache_width,
		CACHE_PADDING,
		WORLD_HEIGHT,
		SEA_LEVEL
	)
	_expect(dark_level == 0, "Two occupied sides must fully occlude their shared corner", failures)
	_expect(open_level == 3, "An open corner must retain full ambient light", failures)
	var diagonal_levels: Array[int] = [3, 0, 3, 0]
	_expect(
		WORLD_MESHER._should_flip_ao_diagonal(diagonal_levels),
		"AO gradient must flip the quad diagonal to prevent a false lighting seam",
		failures
	)


func _assert_leaf_skylight(
	heights: PackedInt32Array,
	cache_width: int,
	failures: PackedStringArray
) -> void:
	var overrides := {
		_key(Vector3i(1, 5, 1)): WORLD_MESHER.BLOCK_LEAVES,
		_key(Vector3i(1, 4, 1)): WORLD_MESHER.BLOCK_LEAVES,
		_key(Vector3i(1, 3, 1)): WORLD_MESHER.BLOCK_LEAVES,
	}
	var sky_light: PackedByteArray = WORLD_MESHER._build_sky_light(
		Vector3i.ZERO,
		heights,
		overrides,
		cache_width,
		CACHE_PADDING,
		WORLD_HEIGHT,
		SEA_LEVEL
	)
	var below_canopy: int = WORLD_MESHER._sky_light_at(
		Vector3i(1, 2, 1),
		Vector3i.ZERO,
		sky_light,
		cache_width,
		CACHE_PADDING,
		WORLD_HEIGHT
	)
	var open_sky: int = WORLD_MESHER._sky_light_at(
		Vector3i(2, 2, 2),
		Vector3i.ZERO,
		sky_light,
		cache_width,
		CACHE_PADDING,
		WORLD_HEIGHT
	)
	_expect(below_canopy == 12, "Three leaf layers must damp skylight from 15 to 12", failures)
	_expect(open_sky == 15, "Open columns must retain full skylight", failures)


func _assert_mesh_contract(mesh_data: Dictionary, failures: PackedStringArray) -> void:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	_expect(not vertices.is_empty(), "Vanilla lighting fixture must generate geometry", failures)
	_expect(colors.size() == vertices.size(), "Every voxel vertex must carry a baked lighting colour", failures)
	_expect(indices.size() % 3 == 0, "Mesh index count must remain triangular", failures)

	var minimum_luminance := 1.0
	var maximum_luminance := 0.0
	for color in colors:
		var luminance := (color.r + color.g + color.b) / 3.0
		minimum_luminance = minf(minimum_luminance, luminance)
		maximum_luminance = maxf(maximum_luminance, luminance)
	_expect(maximum_luminance - minimum_luminance > 0.12, "Baked face and corner lighting must produce visible contrast", failures)

	var bad_triangles := 0
	for index_offset in range(0, indices.size(), 3):
		var index_a := indices[index_offset]
		var index_b := indices[index_offset + 1]
		var index_c := indices[index_offset + 2]
		var cross_normal := (vertices[index_b] - vertices[index_a]).cross(
			vertices[index_c] - vertices[index_a]
		).normalized()
		if cross_normal.dot(normals[index_a]) >= -0.99:
			bad_triangles += 1
	_expect(bad_triangles == 0, "AO diagonal selection must preserve corrected voxel winding", failures)


func _assert_runtime_contract(main: Node, failures: PackedStringArray) -> void:
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	_expect(sun != null, "Main scene must contain Sun", failures)
	if sun != null:
		_expect(not sun.shadow_enabled, "Classic vanilla lighting must not allocate real sun shadow maps", failures)

	var runtime = main.get_node_or_null("ChunkManager/PlayableWorldRuntime")
	_expect(runtime != null, "Standalone playable-world adapter must create its runtime", failures)
	if runtime == null:
		return
	var material := runtime.material as StandardMaterial3D
	_expect(material != null, "Playable-world runtime must expose its terrain material", failures)
	if material == null:
		return
	_expect(material.vertex_color_use_as_albedo, "Terrain material must use baked vertex lighting colours", failures)
	_expect(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Terrain must not receive a second dynamic-light pass", failures)
	_expect(material.specular_mode == BaseMaterial3D.SPECULAR_DISABLED, "Vanilla blocks must not receive a PBR specular highlight", failures)
	_expect(material.cull_mode == BaseMaterial3D.CULL_BACK, "Corrected voxel faces must keep normal back-face culling", failures)


func _build_capture_viewport(mesh_data: Dictionary) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = CAPTURE_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X

	var scene := Node3D.new()
	viewport.add_child(scene)

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color(0.34, 0.62, 0.88)
	environment.environment = environment_resource
	scene.add_child(environment)

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
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.surface_set_material(0, material)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	scene.add_child(mesh_instance)

	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 40.0
	scene.add_child(camera)
	camera.look_at_from_position(Vector3(5.2, 4.2, 5.2), Vector3(1.3, 1.6, 1.3), Vector3.UP)
	return viewport


func _capture(viewport: SubViewport, failures: PackedStringArray) -> void:
	var image := viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "Vanilla lighting gate must produce an image", failures)
	if image == null or image.is_empty():
		return
	var absolute_path := ProjectSettings.globalize_path(CAPTURE_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	_expect(image.save_png(absolute_path) == OK, "Vanilla lighting capture must save", failures)
	_expect(_non_background_fraction(image, Color(0.34, 0.62, 0.88)) > 0.015, "Capture must visibly frame the voxel fixture", failures)
	_expect(_image_luminance_range(image) > 0.08, "Capture must retain visible baked-lighting contrast", failures)


func _empty_heights() -> PackedInt32Array:
	var width := CHUNK_SIZE + CACHE_PADDING * 2
	var heights := PackedInt32Array()
	heights.resize(width * width)
	heights.fill(-1)
	return heights


func _ao_fixture_overrides() -> Dictionary:
	return {
		_key(Vector3i(1, 1, 1)): WORLD_MESHER.BLOCK_GRASS,
		_key(Vector3i(0, 2, 1)): WORLD_MESHER.BLOCK_STONE,
		_key(Vector3i(1, 2, 0)): WORLD_MESHER.BLOCK_STONE,
		_key(Vector3i(0, 2, 0)): WORLD_MESHER.BLOCK_STONE,
	}


func _key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


func _non_background_fraction(image: Image, background: Color) -> float:
	var different := 0
	var count := 0
	var background_rgb := Vector3(background.r, background.g, background.b)
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var color := image.get_pixel(x, y)
			if Vector3(color.r, color.g, color.b).distance_to(background_rgb) > 0.08:
				different += 1
			count += 1
	return float(different) / float(maxi(count, 1))


func _image_luminance_range(image: Image) -> float:
	var minimum_luminance := 1.0
	var maximum_luminance := 0.0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var color := image.get_pixel(x, y)
			var luminance := (color.r + color.g + color.b) / 3.0
			minimum_luminance = minf(minimum_luminance, luminance)
			maximum_luminance = maxf(maximum_luminance, luminance)
	return maximum_luminance - minimum_luminance


func _finish(viewport: SubViewport, main: Node, failures: PackedStringArray) -> void:
	if is_instance_valid(viewport):
		viewport.queue_free()
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
