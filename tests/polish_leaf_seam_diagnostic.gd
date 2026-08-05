extends SceneTree

# Uses the production playable-world mesher; this is not a synthetic face table.
const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const ARTIFACT_DIR := "res://artifacts"
const CULL_ON_PATH := "res://artifacts/leaf-seam-culling-on.png"
const CULL_OFF_PATH := "res://artifacts/leaf-seam-culling-off.png"
const RUNTIME_SOURCE_PATH := "res://scripts/world/playable_world_runtime.gd"
const MAIN_SCENE_SOURCE_PATH := "res://scenes/main.tscn"
const MAGENTA := Color(1.0, 0.0, 1.0, 1.0)
const LEAF_COLOR := Color(0.15, 0.85, 0.25, 1.0)
const CHUNK_SIZE := 4
const WORLD_HEIGHT := 6
const SEA_LEVEL := 0

var failures: Array[String] = []
var scene_root: Node3D
var camera: Camera3D
var mesh_instance: MeshInstance3D


func _initialize() -> void:
	call_deferred("_run")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR))
	var mesh_data := _build_adjacent_leaf_mesh()
	_validate_shared_face_culling(mesh_data)
	_validate_runtime_render_settings()
	var winding_state := _inspect_winding(mesh_data)

	_setup_scene()
	mesh_instance.mesh = _top_face_mesh(mesh_data)
	await _wait_frames(5)

	var cull_on_center := await _capture(BaseMaterial3D.CULL_BACK, CULL_ON_PATH)
	var cull_off_center := await _capture(BaseMaterial3D.CULL_DISABLED, CULL_OFF_PATH)
	var cull_on_visible := not _is_magenta(cull_on_center)
	var cull_off_visible := not _is_magenta(cull_off_center)

	if not cull_off_visible:
		_fail("Isolated leaf top faces were not visible with culling disabled")
	if winding_state != "OUTWARD":
		_fail("Leaf exterior winding was not corrected: %s" % winding_state)
	elif not cull_on_visible:
		_fail("Corrected isolated leaf top faces were culled")
	else:
		print("LEAF_SEAM_GATE_PASS")

	print("LEAF_CULL_CAPTURE mode=on center=%s visible=%s" % [cull_on_center, cull_on_visible])
	print("LEAF_CULL_CAPTURE mode=off center=%s visible=%s" % [cull_off_center, cull_off_visible])
	_finish()


func _build_adjacent_leaf_mesh() -> Dictionary:
	var width := CHUNK_SIZE + 2
	var heights := PackedInt32Array()
	heights.resize(width * width)
	heights.fill(-1)
	var overrides := {
		"1,2,1": WORLD_DATA.BLOCK_LEAVES,
		"2,2,1": WORLD_DATA.BLOCK_LEAVES,
	}
	return WORLD_MESHER.build(
		Vector2i.ZERO,
		heights,
		overrides,
		CHUNK_SIZE,
		WORLD_HEIGHT,
		SEA_LEVEL
	)


func _validate_shared_face_culling(mesh_data: Dictionary) -> void:
	var face_count := int(mesh_data.get("face_count", 0))
	if face_count != 10:
		_fail("Two adjacent leaves must emit 10 exterior faces, got %d" % face_count)
		return

	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var shared_plane_faces := 0
	var top_faces := 0
	for base_index in range(0, vertices.size(), 4):
		var normal := normals[base_index]
		if normal.is_equal_approx(Vector3.UP):
			top_faces += 1
		if absf(normal.x) < 0.99:
			continue
		var on_shared_plane := true
		for vertex_index in range(base_index, base_index + 4):
			if not is_equal_approx(vertices[vertex_index].x, 2.0):
				on_shared_plane = false
				break
		if on_shared_plane:
			shared_plane_faces += 1

	if shared_plane_faces != 0:
		_fail("Leaf-to-leaf shared plane emitted %d internal faces" % shared_plane_faces)
	if top_faces != 2:
		_fail("Adjacent leaf pair must retain two exterior top faces, got %d" % top_faces)
	if failures.is_empty():
		print("LEAF_SHARED_FACE_CULL_PASS faces=%d top_faces=%d" % [face_count, top_faces])


func _validate_runtime_render_settings() -> void:
	var runtime_source := FileAccess.get_file_as_string(RUNTIME_SOURCE_PATH)
	if runtime_source.is_empty():
		_fail("Could not read playable-world runtime source")
	elif not runtime_source.contains("material.cull_mode = BaseMaterial3D.CULL_BACK"):
		_fail("Playable-world runtime does not enable back-face culling")
	elif runtime_source.contains("material.cull_mode = BaseMaterial3D.CULL_DISABLED"):
		_fail("Playable-world runtime still disables culling")

	var main_scene_source := FileAccess.get_file_as_string(MAIN_SCENE_SOURCE_PATH)
	if main_scene_source.is_empty():
		_fail("Could not read main scene source")
	elif main_scene_source.contains("shadow_reverse_cull_face = true"):
		_fail("Main scene still uses the reverse-shadow-cull workaround")

	if failures.is_empty():
		print("LEAF_RENDER_SETTINGS_PASS")


func _inspect_winding(mesh_data: Dictionary) -> String:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var inward_faces := 0
	var outward_faces := 0
	var degenerate_faces := 0

	for index_offset in range(0, indices.size(), 6):
		var index_a := indices[index_offset]
		var index_b := indices[index_offset + 1]
		var index_c := indices[index_offset + 2]
		var cross_normal := (vertices[index_b] - vertices[index_a]).cross(
			vertices[index_c] - vertices[index_a]
		).normalized()
		var winding_dot := cross_normal.dot(normals[index_a])
		if winding_dot > 0.99:
			inward_faces += 1
		elif winding_dot < -0.99:
			outward_faces += 1
		else:
			degenerate_faces += 1

	print("LEAF_WINDING_COUNTS inward=%d outward=%d degenerate=%d" % [
		inward_faces,
		outward_faces,
		degenerate_faces,
	])
	if inward_faces > 0 and outward_faces == 0 and degenerate_faces == 0:
		return "INWARD"
	if outward_faces > 0 and inward_faces == 0 and degenerate_faces == 0:
		return "OUTWARD"
	return "MIXED"


func _top_face_mesh(mesh_data: Dictionary) -> ArrayMesh:
	var source_vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var source_normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var source_colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var source_indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for index_offset in range(0, source_indices.size(), 6):
		var source_base := source_indices[index_offset]
		if not source_normals[source_base].is_equal_approx(Vector3.UP):
			continue
		var destination_base := vertices.size()
		for vertex_offset in range(4):
			vertices.append(source_vertices[source_base + vertex_offset])
			normals.append(source_normals[source_base + vertex_offset])
			colors.append(source_colors[source_base + vertex_offset])
		for triangle_offset in range(6):
			indices.append(destination_base + source_indices[index_offset + triangle_offset] - source_base)

	if vertices.size() != 8 or indices.size() != 12:
		_fail("Expected two isolated top quads, got %d vertices and %d indices" % [
			vertices.size(),
			indices.size(),
		])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _setup_scene() -> void:
	scene_root = Node3D.new()
	root.add_child(scene_root)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = MAGENTA
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.0
	world_environment.environment = environment
	scene_root.add_child(world_environment)

	mesh_instance = MeshInstance3D.new()
	scene_root.add_child(mesh_instance)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 28.0
	camera.near = 0.05
	camera.far = 20.0
	scene_root.add_child(camera)
	camera.global_position = Vector3(1.5, 7.0, 1.5)
	camera.look_at(Vector3(1.5, 3.0, 1.5), Vector3.FORWARD)


func _capture(cull_mode: BaseMaterial3D.CullMode, path: String) -> Color:
	var material := StandardMaterial3D.new()
	material.albedo_color = LEAF_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = cull_mode
	mesh_instance.material_override = material
	await _wait_frames(3)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Capture was empty for %s" % path)
		return MAGENTA
	var save_error := image.save_png(ProjectSettings.globalize_path(path))
	if save_error != OK:
		_fail("Failed to save %s with error %d" % [path, save_error])
	return image.get_pixel(image.get_width() / 2, image.get_height() / 2)


func _is_magenta(color: Color) -> bool:
	return color.r > 0.9 and color.g < 0.1 and color.b > 0.9


func _finish() -> void:
	if failures.is_empty():
		print("POLISH_LEAF_SEAM_DIAGNOSTIC_PASS")
		quit(0)
	else:
		print("POLISH_LEAF_SEAM_DIAGNOSTIC_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
