extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const MAP_PIXEL_DIAMETER := 49
const MAP_PIXEL_CENTER := 24

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
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("Main scene failed to load")
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _wait_frames(30)

	var player := main.get_node_or_null("Player") as Node3D
	var manager := main.get_node_or_null("ChunkManager")
	var overlay := main.get_node_or_null("WorldMapOverlay")
	if player == null:
		_fail("Player missing")
	if manager == null:
		_fail("ChunkManager missing")
	if overlay == null:
		_fail("WorldMapOverlay missing")
	if not failures.is_empty():
		_finish()
		return

	for method_name in [
		"get_playable_world_height",
		"get_playable_world_biome_name",
		"get_playable_world_water_info",
		"get_playable_world_water_name",
		"get_playable_world_sea_level",
		"get_playable_world_height_limit",
	]:
		if not manager.has_method(method_name):
			_fail("ChunkManager missing map/HUD world API %s" % method_name)
	if not overlay.has_method("get_biome_label"):
		_fail("WorldMapOverlay missing biome-label accessor")
	if not failures.is_empty():
		_finish()
		return

	var biome_label := overlay.get_biome_label() as Label
	if biome_label == null:
		_fail("Biome label was not created")
	else:
		if not biome_label.is_visible_in_tree():
			_fail("Biome label is not visible during gameplay")
		if not biome_label.text.begins_with("BIOME: "):
			_fail("Biome label text is malformed: %s" % biome_label.text)
		var player_x := floori(player.global_position.x)
		var player_z := floori(player.global_position.z)
		var expected_biome := String(manager.get_playable_world_biome_name(player_x, player_z))
		expected_biome = expected_biome.replace("_", " ").to_upper()
		if biome_label.text.find(expected_biome) < 0:
			_fail("Biome label %s does not match current world biome %s" % [biome_label.text, expected_biome])

	var sea_level := int(manager.get_playable_world_sea_level())
	var height_limit := int(manager.get_playable_world_height_limit())
	if height_limit < 150:
		_fail("Map world-height API regressed below Stage 13 legal height: %d" % height_limit)

	# Regression for the old minimap bug: elevation alone must never decide water.
	# The same low height is green land when water_type=none and blue only when
	# explicit Stage 13 hydrology says ocean.
	var dry_low: Color = overlay._map_color(
		WORLD_DATA.BLOCK_GRASS,
		0,
		sea_level - 2,
		-1,
		sea_level,
		height_limit,
		1.0
	)
	var ocean_low: Color = overlay._map_color(
		WORLD_DATA.BLOCK_GRASS,
		1,
		sea_level - 2,
		sea_level,
		sea_level,
		height_limit,
		1.0
	)
	if dry_low.g <= dry_low.b:
		_fail("Low dry terrain is still map-colored like water: %s" % dry_low)
	if ocean_low.b <= ocean_low.g:
		_fail("Explicit ocean column is not map-colored blue: %s" % ocean_low)

	var shaded: Color = overlay._map_color(
		WORLD_DATA.BLOCK_GRASS, 0, sea_level + 24, -1, sea_level, height_limit, 0.72
	)
	var lit: Color = overlay._map_color(
		WORLD_DATA.BLOCK_GRASS, 0, sea_level + 24, -1, sea_level, height_limit, 1.20
	)
	if lit.r + lit.g + lit.b <= shaded.r + shaded.g + shaded.b:
		_fail("Terrain relief shading does not distinguish lit and shaded slopes")

	overlay.open_map()
	await _wait_frames(2)
	var texture_rect := overlay.get_map_texture_rect() as TextureRect
	if texture_rect == null or texture_rect.texture == null:
		_fail("Opening map did not generate a terrain texture")
	else:
		var texture := texture_rect.texture as ImageTexture
		if texture == null:
			_fail("Map texture is not ImageTexture")
		else:
			var image := texture.get_image()
			if image.get_width() != MAP_PIXEL_DIAMETER or image.get_height() != MAP_PIXEL_DIAMETER:
				_fail("Map dimensions changed unexpectedly: %dx%d" % [image.get_width(), image.get_height()])
			var marker := image.get_pixel(MAP_PIXEL_CENTER, MAP_PIXEL_CENTER)
			if marker.r < 0.9 or marker.g < 0.7 or marker.b > 0.3:
				_fail("Player marker is not yellow at map center: %s" % marker)
			var unique_colors: Dictionary = {}
			for y in range(image.get_height()):
				for x in range(image.get_width()):
					unique_colors[image.get_pixel(x, y).to_html()] = true
			if unique_colors.size() < 6:
				_fail("Upgraded terrain map lacks relief/material variation: %d colors" % unique_colors.size())

	overlay.close_map()
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("WORLD_MAP_BIOME_GATE_PASS")
		print("WORLD_MAP_WATER=explicit Stage13 water topology; low dry terrain remains land")
		print("WORLD_MAP_RELIEF=shipping height limit plus directional terrain shading")
		print("WORLD_BIOME_HUD=always-visible current biome label")
	_finish()


func _finish() -> void:
	if failures.is_empty():
		quit(0)
	else:
		print("WORLD_MAP_BIOME_GATE_FAIL count=%d" % failures.size())
		for failure in failures:
			print("WORLD_MAP_BIOME_FAILURE=%s" % failure)
		quit(1)
