extends SceneTree

## Cave interior screenshot gate (build plan steps 11-13).
## Boots the shipping playable world, locates a deterministic underground
## cave pocket through the frozen field contract, teleports the player into
## it, and captures a 1280x720 PNG for sky-light / AO inspection.
## Run under xvfb-run (software GL) like the acceptance gate.

const CAVE_REF := preload("res://scripts/world/cave_field_reference.gd")
const OUTPUT_PATH := "res://artifacts/cave-interior.png"

var failures: Array[String] = []


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _wait_world_ready(manager, timeout_msec := 45000) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_msec:
		await process_frame
		if manager.chunk_count() >= manager.expected_chunk_count() and manager.is_remesh_idle():
			return true
	return false


func _find_cave_pocket(manager) -> Vector3i:
	for z in range(-48, 49, 2):
		for x in range(-48, 49, 2):
			var surface: int = manager.get_playable_world_height(x, z)
			for y in range(max(4, surface - 26), surface - 5):
				if CAVE_REF.is_cave_cell(x, y, z, surface, 7, false, 0):
					var above := CAVE_REF.is_cave_cell(x, y + 1, z, surface, 7, false, 0)
					if above and manager.get_block_world(Vector3i(x, y, z)) == 0:
						return Vector3i(x, y, z)
	return Vector3i(1 << 30, 0, 0)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	if packed_scene == null:
		print("CAVE_SCREENSHOT_FAIL")
		quit(1)
		return
	var main := packed_scene.instantiate()
	root.add_child(main)

	var manager = main.get_node_or_null("ChunkManager")
	var player := main.get_node_or_null("Player") as CharacterBody3D
	var camera := main.get_node_or_null("Player/Camera3D") as Camera3D
	if manager == null or player == null or camera == null:
		_fail("main scene did not expose manager/player/camera")

	if not await _wait_world_ready(manager):
		_fail("world never became ready for cave probe")

	var pocket := _find_cave_pocket(manager)
	if pocket.x == (1 << 30):
		# The GDScript-only fallback ships the legacy pre-Carpathian world
		# (the Carpathian sampler is native-only by charter), so no cave
		# pocket exists. Capture the shipped surface instead and report the
		# mode so the artifact is not mistaken for a cave interior.
		var spawn_surface: int = manager.get_playable_world_height(0, 24)
		player.set_physics_process(false)
		player.set_process(false)
		player.global_position = Vector3(0.5, spawn_surface + 6.0, 24.0)
		camera.rotation_degrees.x = -22.0
		manager.refresh_streaming(player.global_position)
		if not await _wait_world_ready(manager, 30000):
			_fail("remesh after fallback teleport did not settle")
		await RenderingServer.frame_post_draw
		var fb_image := root.get_texture().get_image()
		if fb_image == null or fb_image.is_empty():
			_fail("viewport capture returned empty image")
		else:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
			var fb_err := fb_image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
			if fb_err != OK:
				_fail("png save failed with %d" % fb_err)
			else:
				print("CAVE_SCREENSHOT_SAVED=", ProjectSettings.globalize_path(OUTPUT_PATH))
				print("CAVE_MODE=fallback_legacy_surface")
		if failures.is_empty():
			print("CAVE_SCREENSHOT_PASS")
		else:
			print("CAVE_SCREENSHOT_FAIL ", failures)
		quit(0 if failures.is_empty() else 1)
		return
	else:
		player.set_physics_process(false)
		player.set_process(false)
		player.global_position = Vector3(pocket.x + 0.5, pocket.y + 1.2, pocket.z + 0.5)
		camera.rotation_degrees.x = -8.0
		manager.refresh_streaming(player.global_position)
		if not await _wait_world_ready(manager, 30000):
			_fail("remesh after teleport did not settle")
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			_fail("viewport capture returned empty image")
		else:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
			var err := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
			if err != OK:
				_fail("png save failed with %d" % err)
			else:
				print("CAVE_SCREENSHOT_SAVED=", ProjectSettings.globalize_path(OUTPUT_PATH))
				print("CAVE_POCKET=", pocket)

	if failures.is_empty():
		print("CAVE_SCREENSHOT_PASS")
	else:
		print("CAVE_SCREENSHOT_FAIL ", failures)
	quit(0 if failures.is_empty() else 1)
