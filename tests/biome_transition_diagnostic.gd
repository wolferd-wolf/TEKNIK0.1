extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SCREENSHOT_PATH := "res://artifacts/biome-transition.png"
const BIOME_PLAINS := 0
const BIOME_FOREST := 1
const BIOME_DESERT := 2
const BLOCK_AIR := 0

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _biome_at(manager, point: Vector2i) -> int:
	var sample: float = manager._biome_noise.get_noise_2d(point.x, point.y)
	if sample < -0.25:
		return BIOME_DESERT
	if sample > 0.25:
		return BIOME_FOREST
	return BIOME_PLAINS


func _find_nearest_desert_edge(manager) -> Array[Vector2i]:
	var best_pair: Array[Vector2i] = []
	var best_distance_squared: int = 9223372036854775807
	var coarse_step: int = 32
	var directions: Array[Vector2i] = [
		Vector2i(coarse_step, 0),
		Vector2i(0, coarse_step),
	]

	for sample_x in range(-2048, 2049, coarse_step):
		for sample_z in range(-2048, 2049, coarse_step):
			var start: Vector2i = Vector2i(sample_x, sample_z)
			var start_biome: int = _biome_at(manager, start)
			for direction: Vector2i in directions:
				var finish: Vector2i = start + direction
				var finish_biome: int = _biome_at(manager, finish)
				var crosses_desert: bool = (
					start_biome == BIOME_DESERT and finish_biome != BIOME_DESERT
				) or (
					start_biome != BIOME_DESERT and finish_biome == BIOME_DESERT
				)
				if not crosses_desert:
					continue

				var previous: Vector2i = start
				var previous_biome: int = start_biome
				var unit_direction: Vector2i = Vector2i(signi(direction.x), signi(direction.y))
				for offset in range(1, coarse_step + 1):
					var current: Vector2i = start + unit_direction * offset
					var current_biome: int = _biome_at(manager, current)
					if current_biome != previous_biome:
						var edge_midpoint: Vector2 = Vector2(
							(previous.x + current.x) * 0.5,
							(previous.y + current.y) * 0.5
						)
						var distance_squared: int = int(edge_midpoint.length_squared())
						if distance_squared < best_distance_squared:
							best_distance_squared = distance_squared
							best_pair = [previous, current]
						break
					previous = current
					previous_biome = current_biome

	return best_pair


func _surface_block(manager, point: Vector2i) -> int:
	for world_y in range(31, -17, -1):
		var block_id: int = manager.get_block_world(Vector3i(point.x, world_y, point.y))
		if block_id != BLOCK_AIR:
			return block_id
	return BLOCK_AIR


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
	if manager == null or player == null or camera == null:
		_fail("Required scene nodes are missing")
		_finish()
		return

	player.set_physics_process(false)
	player.set_process(false)

	var edge: Array[Vector2i] = _find_nearest_desert_edge(manager)
	if edge.size() != 2:
		_fail("No desert/non-desert transition found in diagnostic search area")
		_finish()
		return

	var point_a: Vector2i = edge[0]
	var point_b: Vector2i = edge[1]
	var midpoint: Vector2i = Vector2i(
		floori((point_a.x + point_b.x) * 0.5),
		floori((point_a.y + point_b.y) * 0.5)
	)

	player.global_position = Vector3(midpoint.x + 0.5, 18.0, midpoint.y + 0.5)
	manager.refresh_streaming(player.global_position)
	await _wait_frames(20)

	var biome_a: int = _biome_at(manager, point_a)
	var biome_b: int = _biome_at(manager, point_b)
	var block_a: int = _surface_block(manager, point_a)
	var block_b: int = _surface_block(manager, point_b)

	var counts: Dictionary = {
		BIOME_PLAINS: 0,
		BIOME_FOREST: 0,
		BIOME_DESERT: 0,
	}
	for offset_x in range(-32, 33):
		for offset_z in range(-32, 33):
			var biome_id: int = _biome_at(manager, midpoint + Vector2i(offset_x, offset_z))
			counts[biome_id] = int(counts[biome_id]) + 1

	print("TRANSITION_A=%s BIOME=%d SURFACE_BLOCK=%d" % [point_a, biome_a, block_a])
	print("TRANSITION_B=%s BIOME=%d SURFACE_BLOCK=%d" % [point_b, biome_b, block_b])
	print("REGION_BIOME_COUNTS PLAINS=%d FOREST=%d DESERT=%d" % [
		counts[BIOME_PLAINS],
		counts[BIOME_FOREST],
		counts[BIOME_DESERT],
	])

	camera.global_position = Vector3(midpoint.x + 30.0, 34.0, midpoint.y + 30.0)
	camera.look_at(Vector3(midpoint.x, 8.0, midpoint.y), Vector3.UP)
	await _wait_frames(30)
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Biome transition screenshot was empty")
	else:
		var save_error: Error = image.save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
		if save_error != OK:
			_fail("Biome transition screenshot failed with error %d" % save_error)
		else:
			print("BIOME_TRANSITION_SCREENSHOT=%s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("BIOME_TRANSITION_DIAGNOSTIC_PASS")
		quit(0)
	else:
		print("BIOME_TRANSITION_DIAGNOSTIC_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
