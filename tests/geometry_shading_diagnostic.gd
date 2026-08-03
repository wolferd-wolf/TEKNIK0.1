extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/unshaded-geometry.png"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run() -> void:
	var packed_scene: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Main scene failed to load")
		_finish()
		return

	var main: Node = packed_scene.instantiate()
	root.add_child(main)
	await _wait_frames(20)

	var manager: Node = main.get_node_or_null("ChunkManager")
	var player: CharacterBody3D = main.get_node_or_null("Player") as CharacterBody3D
	var camera: Camera3D = main.get_node_or_null("Player/Camera3D") as Camera3D
	var world_environment: WorldEnvironment = main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if manager == null or player == null or camera == null or world_environment == null:
		_fail("Required scene nodes are missing")
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector3(0.5, 18.0, 24.0)
	player.rotation = Vector3.ZERO
	camera.rotation_degrees.x = -22.0
	manager.refresh_streaming(player.global_position)
	await _wait_frames(20)

	world_environment.environment.background_mode = Environment.BG_COLOR
	world_environment.environment.background_color = Color(1.0, 0.0, 1.0, 1.0)
	world_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.environment.ambient_light_color = Color.WHITE
	world_environment.environment.ambient_light_energy = 1.0

	var chunk_count: int = 0
	for chunk in manager.chunks.values():
		if not is_instance_valid(chunk) or chunk.mesh_instance == null:
			continue
		var material := chunk.mesh_instance.material_override as StandardMaterial3D
		if material == null:
			continue
		var diagnostic_material := material.duplicate() as StandardMaterial3D
		diagnostic_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		chunk.mesh_instance.material_override = diagnostic_material
		chunk_count += 1

	print("UNSHADED_CHUNKS=%d" % chunk_count)
	await _wait_frames(10)
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Unshaded geometry screenshot was empty")
	else:
		var save_error: Error = image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
		if save_error != OK:
			_fail("Unshaded screenshot failed with error %d" % save_error)
		else:
			print("UNSHADED_GEOMETRY_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("GEOMETRY_SHADING_DIAGNOSTIC_PASS")
		quit(0)
	else:
		print("GEOMETRY_SHADING_DIAGNOSTIC_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
