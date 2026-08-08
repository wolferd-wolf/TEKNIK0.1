extends CanvasLayer
class_name WorldMapOverlay

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const MAP_PIXEL_DIAMETER := 49
const MAP_SAMPLE_SPACING := 2
const MAP_HALF_PIXELS := 24
const MAP_BUTTON_SIZE := Vector2(94.0, 46.0)
const MAP_BUTTON_MARGIN := Vector2(18.0, 18.0)
const BIOME_REFRESH_SECONDS := 0.25
const WATER_NONE := 0
const WATER_OCEAN := 1
const WATER_RIVER := 2
const WATER_LAKE := 3
const WATER_POND := 4
const GAMEPLAY_ACTIONS := [
	StringName("move_left"),
	StringName("move_right"),
	StringName("move_forward"),
	StringName("move_backward"),
	StringName("jump"),
	StringName("look_left"),
	StringName("look_right"),
	StringName("look_up"),
	StringName("look_down"),
	StringName("mine_block"),
	StringName("place_block"),
]

@export var player_path := NodePath("../Player")
@export var world_path := NodePath("../ChunkManager")

var _player: Node3D
var _world
var _root: Control
var _map_button: Button
var _biome_label: Label
var _overlay: Control
var _map_panel: PanelContainer
var _map_texture_rect: TextureRect
var _coordinates_label: Label
var _close_button: Button
var _is_open := false
var _biome_refresh_elapsed := BIOME_REFRESH_SECONDS


func _ready() -> void:
	layer = 70
	process_priority = -1000
	_player = get_node_or_null(player_path) as Node3D
	_world = get_node_or_null(world_path)
	_build_screen()
	_hide_drag_look_hint()
	_refresh_biome_label()
	_set_open(false)
	set_process_input(true)
	set_process(true)


func _process(delta: float) -> void:
	_biome_refresh_elapsed += delta
	if _biome_refresh_elapsed < BIOME_REFRESH_SECONDS:
		return
	_biome_refresh_elapsed = 0.0
	_refresh_biome_label()


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _control_contains(_map_button, touch.position):
			toggle_map()
			get_viewport().set_input_as_handled()
			return
		if _is_open and touch.pressed and _control_contains(_close_button, touch.position):
			close_map()
			get_viewport().set_input_as_handled()
			return
	if _is_open:
		get_viewport().set_input_as_handled()


func is_map_open() -> bool:
	return _is_open


func get_map_button() -> Button:
	return _map_button


func get_biome_label() -> Label:
	return _biome_label


func get_map_panel() -> PanelContainer:
	return _map_panel


func get_map_texture_rect() -> TextureRect:
	return _map_texture_rect


func get_close_button() -> Button:
	return _close_button


func toggle_map() -> void:
	if _is_open:
		close_map()
	else:
		open_map()


func open_map() -> void:
	_refresh_map()
	_refresh_biome_label()
	_release_gameplay_actions()
	_set_open(true)


func close_map() -> void:
	_set_open(false)


func _set_open(value: bool) -> void:
	_is_open = value
	if is_instance_valid(_overlay):
		_overlay.visible = value
	if is_instance_valid(_map_button):
		_map_button.text = "CLOSE" if value else "MAP"


func _build_screen() -> void:
	_root = Control.new()
	_root.name = "WorldMapRoot"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_overlay)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	_map_panel = PanelContainer.new()
	_map_panel.name = "MapPanel"
	_map_panel.anchor_left = 0.5
	_map_panel.anchor_top = 0.5
	_map_panel.anchor_right = 0.5
	_map_panel.anchor_bottom = 0.5
	_map_panel.offset_left = -270.0
	_map_panel.offset_top = -330.0
	_map_panel.offset_right = 270.0
	_map_panel.offset_bottom = 330.0
	_map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_map_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_map_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.text = "LOCAL MAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)

	_coordinates_label = Label.new()
	_coordinates_label.name = "Coordinates"
	_coordinates_label.text = "X 0   Z 0"
	_coordinates_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coordinates_label.add_theme_font_size_override("font_size", 16)
	column.add_child(_coordinates_label)

	var map_frame := PanelContainer.new()
	map_frame.name = "MapFrame"
	map_frame.custom_minimum_size = Vector2(460.0, 460.0)
	map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(map_frame)

	_map_texture_rect = TextureRect.new()
	_map_texture_rect.name = "MapTexture"
	_map_texture_rect.custom_minimum_size = Vector2(444.0, 444.0)
	_map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_child(_map_texture_rect)

	var legend := Label.new()
	legend.name = "Legend"
	legend.text = "NORTH UP   •   YELLOW = PLAYER   •   SHADE = TERRAIN RELIEF"
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 14)
	column.add_child(legend)

	_close_button = Button.new()
	_close_button.name = "CloseMapButton"
	_close_button.text = "CLOSE MAP"
	_close_button.custom_minimum_size = Vector2(0.0, 42.0)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.add_theme_font_size_override("font_size", 17)
	_close_button.pressed.connect(close_map)
	column.add_child(_close_button)

	_map_button = Button.new()
	_map_button.name = "MapToggle"
	_map_button.text = "MAP"
	_map_button.position = MAP_BUTTON_MARGIN
	_map_button.size = MAP_BUTTON_SIZE
	_map_button.focus_mode = Control.FOCUS_NONE
	_map_button.add_theme_font_size_override("font_size", 17)
	_map_button.pressed.connect(toggle_map)
	_root.add_child(_map_button)

	# Always-visible current-biome readout. It intentionally lives outside the
	# modal map overlay so the player can identify biome transitions in gameplay.
	_biome_label = Label.new()
	_biome_label.name = "BiomeLabel"
	_biome_label.anchor_left = 0.5
	_biome_label.anchor_right = 0.5
	_biome_label.offset_left = -190.0
	_biome_label.offset_top = 18.0
	_biome_label.offset_right = 190.0
	_biome_label.offset_bottom = 58.0
	_biome_label.text = "BIOME: UNKNOWN"
	_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_biome_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_biome_label.add_theme_font_size_override("font_size", 18)
	_biome_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_biome_label.add_theme_constant_override("outline_size", 6)
	_biome_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_biome_label)


func _refresh_biome_label() -> void:
	if not is_instance_valid(_biome_label):
		return
	if not is_instance_valid(_player) or _world == null:
		_biome_label.text = "BIOME: UNKNOWN"
		return
	var world_x := floori(_player.global_position.x)
	var world_z := floori(_player.global_position.z)
	var biome_name := "unknown"
	if _world.has_method("get_playable_world_biome_name"):
		biome_name = String(_world.get_playable_world_biome_name(world_x, world_z))
	var label := "BIOME: %s" % _display_name(biome_name)
	if _world.has_method("get_playable_world_water_name"):
		var water_name := String(_world.get_playable_world_water_name(world_x, world_z))
		if water_name != "none" and water_name != "unknown":
			label += "  •  %s" % _display_name(water_name)
	_biome_label.text = label


func _display_name(value: String) -> String:
	return value.replace("_", " ").to_upper()


func _refresh_map() -> void:
	if not is_instance_valid(_player) or _world == null:
		return
	var center_x := floori(_player.global_position.x)
	var center_z := floori(_player.global_position.z)
	var sample_count := MAP_PIXEL_DIAMETER * MAP_PIXEL_DIAMETER
	var heights := PackedInt32Array()
	var water_types := PackedByteArray()
	var water_surfaces := PackedInt32Array()
	var surface_blocks := PackedByteArray()
	heights.resize(sample_count)
	water_types.resize(sample_count)
	water_surfaces.resize(sample_count)
	surface_blocks.resize(sample_count)

	# First pass samples the real Stage 13 world. Water classification is explicit;
	# low dry terrain is no longer incorrectly painted as ocean just because its
	# elevation is near sea level.
	for pixel_z in range(MAP_PIXEL_DIAMETER):
		var world_z := center_z + (pixel_z - MAP_HALF_PIXELS) * MAP_SAMPLE_SPACING
		var row := pixel_z * MAP_PIXEL_DIAMETER
		for pixel_x in range(MAP_PIXEL_DIAMETER):
			var world_x := center_x + (pixel_x - MAP_HALF_PIXELS) * MAP_SAMPLE_SPACING
			var index := row + pixel_x
			var height := int(_world.get_playable_world_height(world_x, world_z))
			heights[index] = height
			var info := Vector2i(WATER_NONE, -1)
			if _world.has_method("get_playable_world_water_info"):
				info = _world.get_playable_world_water_info(world_x, world_z)
			water_types[index] = clampi(info.x, 0, 255)
			water_surfaces[index] = info.y
			surface_blocks[index] = clampi(
				int(_world.get_block_world(Vector3i(world_x, height, world_z))),
				0,
				255
			)

	var sea_level := 0
	if _world.has_method("get_playable_world_sea_level"):
		sea_level = int(_world.get_playable_world_sea_level())
	var world_height := 150
	if _world.has_method("get_playable_world_height_limit"):
		world_height = int(_world.get_playable_world_height_limit())

	var image := Image.create(MAP_PIXEL_DIAMETER, MAP_PIXEL_DIAMETER, false, Image.FORMAT_RGBA8)
	for pixel_z in range(MAP_PIXEL_DIAMETER):
		for pixel_x in range(MAP_PIXEL_DIAMETER):
			var index := pixel_z * MAP_PIXEL_DIAMETER + pixel_x
			var west_x := maxi(0, pixel_x - 1)
			var east_x := mini(MAP_PIXEL_DIAMETER - 1, pixel_x + 1)
			var north_z := maxi(0, pixel_z - 1)
			var south_z := mini(MAP_PIXEL_DIAMETER - 1, pixel_z + 1)
			var west_height := int(heights[pixel_z * MAP_PIXEL_DIAMETER + west_x])
			var east_height := int(heights[pixel_z * MAP_PIXEL_DIAMETER + east_x])
			var north_height := int(heights[north_z * MAP_PIXEL_DIAMETER + pixel_x])
			var south_height := int(heights[south_z * MAP_PIXEL_DIAMETER + pixel_x])
			var directional_relief := float(
				(west_height - east_height) + (north_height - south_height)
			) * 0.035
			var terrain_light := clampf(1.0 + directional_relief, 0.72, 1.20)
			image.set_pixel(
				pixel_x,
				pixel_z,
				_map_color(
					int(surface_blocks[index]),
					int(water_types[index]),
					int(heights[index]),
					int(water_surfaces[index]),
					sea_level,
					world_height,
					terrain_light
				)
			)

	for marker_z in range(MAP_HALF_PIXELS - 1, MAP_HALF_PIXELS + 2):
		for marker_x in range(MAP_HALF_PIXELS - 1, MAP_HALF_PIXELS + 2):
			image.set_pixel(marker_x, marker_z, Color(1.0, 0.84, 0.12, 1.0))
	_map_texture_rect.texture = ImageTexture.create_from_image(image)
	_coordinates_label.text = "X %d   Z %d" % [center_x, center_z]


func _map_color(
	block_id: int,
	water_type: int,
	height: int,
	water_surface: int,
	sea_level: int,
	world_height: int,
	terrain_light: float
) -> Color:
	if water_type != WATER_NONE:
		return _water_map_color(water_type, maxi(1, water_surface - height))

	var base := Color(0.31, 0.58, 0.20, 1.0)
	match block_id:
		WORLD_DATA.BLOCK_SAND:
			base = Color(0.83, 0.74, 0.46, 1.0)
		WORLD_DATA.BLOCK_STONE:
			base = Color(0.48, 0.49, 0.50, 1.0)
		WORLD_DATA.BLOCK_DIRT:
			base = Color(0.42, 0.27, 0.13, 1.0)
		WORLD_DATA.BLOCK_LOG:
			base = Color(0.32, 0.18, 0.08, 1.0)
		WORLD_DATA.BLOCK_LEAVES:
			base = Color(0.12, 0.48, 0.10, 1.0)

	var usable_height := maxf(1.0, float(world_height - sea_level - 1))
	var elevation := clampf(float(height - sea_level) / usable_height, 0.0, 1.0)
	var elevation_shade := lerpf(0.82, 1.14, elevation)
	var shade := clampf(elevation_shade * terrain_light, 0.62, 1.24)
	return Color(
		clampf(base.r * shade, 0.0, 1.0),
		clampf(base.g * shade, 0.0, 1.0),
		clampf(base.b * shade, 0.0, 1.0),
		1.0
	)


func _water_map_color(water_type: int, depth: int) -> Color:
	var base := Color(0.11, 0.37, 0.72, 1.0)
	match water_type:
		WATER_OCEAN:
			base = Color(0.07, 0.27, 0.63, 1.0)
		WATER_RIVER:
			base = Color(0.10, 0.44, 0.82, 1.0)
		WATER_LAKE:
			base = Color(0.10, 0.38, 0.75, 1.0)
		WATER_POND:
			base = Color(0.11, 0.47, 0.66, 1.0)
	var depth_shade := clampf(1.02 - float(depth - 1) * 0.035, 0.72, 1.02)
	return Color(base.r * depth_shade, base.g * depth_shade, base.b * depth_shade, 1.0)


func _hide_drag_look_hint() -> void:
	var touch_controls := get_node_or_null("../TouchControls")
	if touch_controls == null or not touch_controls.has_method("get_look_hint"):
		return
	var look_hint := touch_controls.get_look_hint() as CanvasItem
	if look_hint != null:
		look_hint.modulate.a = 0.0


func _release_gameplay_actions() -> void:
	for action in GAMEPLAY_ACTIONS:
		Input.action_release(action)


func _control_contains(control: Control, position: Vector2) -> bool:
	return control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(position)
