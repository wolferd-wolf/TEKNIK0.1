extends SceneTree

const MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const ARTIFACT_DIR := "res://artifacts/carpathian-shipping"
const GRID_PATH := "res://artifacts/carpathian-shipping/playable-world-face-winding-grid.png"
const CELL_SIZE := Vector2i(320, 180)
const FACE_NAMES := ["top", "bottom", "right", "left", "back", "forward"]
const CULL_NAMES := ["culling-on", "culling-off"]
const MAGENTA := Color(1.0, 0.0, 1.0, 1.0)
const FACE_COLOR := Color(0.15, 0.85, 0.25, 1.0)
const CAMERA_DISTANCE := 2.5
const DEFAULT_INDICES := [0, 2, 1, 0, 3, 2]
const FLIPPED_INDICES := [0, 3, 1, 1, 3, 2]

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
	_setup_scene()
	await _wait_frames(5)

	var grid := Image.create(CELL_SIZE.x * 2, CELL_SIZE.y * FACE_NAMES.size(), false, Image.FORMAT_RGBA8)
	grid.fill(MAGENTA)

	for face_index in range(FACE_NAMES.size()):
		_validate_winding(face_index, DEFAULT_INDICES, "default")
		_validate_winding(face_index, FLIPPED_INDICES, "ao-flipped")
		mesh_instance.mesh = _build_face_mesh(face_index, DEFAULT_INDICES)
		_position_camera(face_index)

		for cull_index in range(CULL_NAMES.size()):
			var cull_mode := BaseMaterial3D.CULL_BACK if cull_index == 0 else BaseMaterial3D.CULL_DISABLED
			mesh_instance.material_override = _create_material(cull_mode)
			await _wait_frames(3)
			await RenderingServer.frame_post_draw

			var image: Image = root.get_texture().get_image()
			if image == null or image.is_empty():
				_fail("%s/%s capture was empty" % [FACE_NAMES[face_index], CULL_NAMES[cull_index]])
				continue

			var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
			if _is_magenta(center):
				_fail("%s face disappeared with %s" % [FACE_NAMES[face_index], CULL_NAMES[cull_index]])

			var path := "%s/face-%s-%s.png" % [ARTIFACT_DIR, FACE_NAMES[face_index], CULL_NAMES[cull_index]]
			var save_error := image.save_png(ProjectSettings.globalize_path(path))
			if save_error != OK:
				_fail("Failed to save %s with error %d" % [path, save_error])

			var thumbnail := image.duplicate()
			thumbnail.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_NEAREST)
			grid.blit_rect(
				thumbnail,
				Rect2i(Vector2i.ZERO, CELL_SIZE),
				Vector2i(cull_index * CELL_SIZE.x, face_index * CELL_SIZE.y)
			)
			print("PLAYABLE_FACE_RENDER face=%s mode=%s center=%s" % [
				FACE_NAMES[face_index],
				CULL_NAMES[cull_index],
				center,
			])

	var grid_error := grid.save_png(ProjectSettings.globalize_path(GRID_PATH))
	if grid_error != OK:
		_fail("Failed to save face winding grid with error %d" % grid_error)
	else:
		print("PLAYABLE_FACE_WINDING_GRID=%s" % ProjectSettings.globalize_path(GRID_PATH))

	_finish()


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
	camera.far = 10.0
	scene_root.add_child(camera)


func _validate_winding(face_index: int, indices: Array, label: String) -> void:
	var face_vertices: Array = MESHER.FACE_VERTICES[face_index]
	var outward_normal: Vector3 = MESHER.FACE_NORMALS[face_index]
	for triangle in range(0, indices.size(), 3):
		var vertex_a: Vector3 = face_vertices[indices[triangle]]
		var vertex_b: Vector3 = face_vertices[indices[triangle + 1]]
		var vertex_c: Vector3 = face_vertices[indices[triangle + 2]]
		var cross_normal := (vertex_b - vertex_a).cross(vertex_c - vertex_a).normalized()
		var winding_dot := cross_normal.dot(outward_normal)
		# Godot's clockwise front face means the right-hand cross product points
		# opposite the outward normal for an exterior-facing triangle.
		if winding_dot > -0.99:
			_fail("%s/%s triangle %d winding is inward (dot %.3f)" % [
				FACE_NAMES[face_index], label, triangle / 3, winding_dot
			])
		print("PLAYABLE_FACE_WINDING face=%s diagonal=%s triangle=%d dot=%.3f" % [
			FACE_NAMES[face_index], label, triangle / 3, winding_dot
		])


func _build_face_mesh(face_index: int, indices: Array) -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_vertices: Array = MESHER.FACE_VERTICES[face_index]
	var outward_normal: Vector3 = MESHER.FACE_NORMALS[face_index]
	var centered_origin := Vector3(-0.5, -0.5, -0.5)

	for vertex_index in indices:
		surface_tool.set_normal(outward_normal)
		surface_tool.set_color(FACE_COLOR)
		surface_tool.add_vertex(centered_origin + face_vertices[vertex_index])

	return surface_tool.commit()


func _create_material(cull_mode: BaseMaterial3D.CullMode) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = cull_mode
	return material


func _position_camera(face_index: int) -> void:
	var outward_normal: Vector3 = MESHER.FACE_NORMALS[face_index]
	camera.global_position = outward_normal * CAMERA_DISTANCE
	var up_vector := Vector3.FORWARD if absf(outward_normal.y) > 0.5 else Vector3.UP
	camera.look_at(Vector3.ZERO, up_vector)


func _is_magenta(color: Color) -> bool:
	return color.r > 0.9 and color.g < 0.1 and color.b > 0.9


func _finish() -> void:
	if failures.is_empty():
		print("PLAYABLE_FACE_WINDING_DIAGNOSTIC_PASS")
		quit(0)
	else:
		print("PLAYABLE_FACE_WINDING_DIAGNOSTIC_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
