extends CanvasLayer
class_name WorldMapOverlay

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const MAP_PIXEL_DIAMETER := 49
const MAP_SAMPLE_SPACING := 2
const MAP_HALF_PIXELS := 24
const MAP_BUTTON_SIZE := Vector2(94.0, 46.0)
const MAP_BUTTON_MARGIN := Vector2(18.0, 18.0)
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
var _overlay: Control
var _map_panel: PanelContainer
var _map_texture_rect: TextureRect
var _coordinates_label: Label
var _close_button: Button
var _is_open := false


func _ready() -> void:
	layer = 70
	process_priority = -1000
	_player = get_node_or_null(player_path) as Node3D
	_world = get_node_or_null(world_path)
	_build_screen()
	_hide_drag_look_hint()
	_set_open(false)
	set_process_input(true)


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
	legend.text = "NORTH UP   •   YELLOW = PLAYER   •   BRIGHTER = HIGHER"
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


func _refresh_map() -> void:
	if not is_instance_valid(_player) or _world == null:
		return
	var center_x := floori(_player.global_position.x)
	var center_z := floori(_player.global_position.z)
	var image := Image.create(MAP_PIXEL_DIAMETER, MAP_PIXEL_DIAMETER, false, Image.FORMAT_RGBA8)
	for pixel_z in range(MAP_PIXEL_DIAMETER):
		var world_z := center_z + (pixel_z - MAP_HALF_PIXELS) * MAP_SAMPLE_SPACING
		for pixel_x in range(MAP_PIXEL_DIAMETER):
			var world_x := center_x + (pixel_x - MAP_HALF_PIXELS) * MAP_SAMPLE_SPACING
			var height: int = int(_world.get_playable_world_height(world_x, world_z))
			var block_id: int = int(_world.get_block_world(Vector3i(world_x, height, world_z)))
			image.set_pixel(pixel_x, pixel_z, _map_color(block_id, height))
	for marker_z in range(MAP_HALF_PIXELS - 1, MAP_HALF_PIXELS + 2):
		for marker_x in range(MAP_HALF_PIXELS - 1, MAP_HALF_PIXELS + 2):
			image.set_pixel(marker_x, marker_z, Color(1.0, 0.84, 0.12, 1.0))
	_map_texture_rect.texture = ImageTexture.create_from_image(image)
	_coordinates_label.text = "X %d   Z %d" % [center_x, center_z]


func _map_color(block_id: int, height: int) -> Color:
	if height <= WORLD_DATA.SEA_LEVEL:
		return Color(0.12, 0.38, 0.78, 1.0)
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
	var usable_height := maxf(
		1.0,
		float(WORLD_DATA.WORLD_HEIGHT - WORLD_DATA.SEA_LEVEL - 3)
	)
	var elevation := clampf(
		float(height - WORLD_DATA.SEA_LEVEL) / usable_height,
		0.0,
		1.0
	)
	var shade := lerpf(0.78, 1.12, elevation)
	return Color(
		clampf(base.r * shade, 0.0, 1.0),
		clampf(base.g * shade, 0.0, 1.0),
		clampf(base.b * shade, 0.0, 1.0),
		1.0
	)


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
