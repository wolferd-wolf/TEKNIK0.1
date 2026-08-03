extends CanvasLayer
class_name TouchControls

const MOVE_LEFT_ACTION := StringName("move_left")
const MOVE_RIGHT_ACTION := StringName("move_right")
const MOVE_FORWARD_ACTION := StringName("move_forward")
const MOVE_BACKWARD_ACTION := StringName("move_backward")
const MOVEMENT_ACTIONS := [
	MOVE_LEFT_ACTION,
	MOVE_RIGHT_ACTION,
	MOVE_FORWARD_ACTION,
	MOVE_BACKWARD_ACTION,
]

@export var joystick_radius: float = 84.0
@export var knob_radius: float = 34.0
@export var activation_padding: float = 28.0
@export var deadzone: float = 0.15
@export var left_margin: float = 36.0
@export var bottom_margin: float = 120.0

var _touch_root: Control
var _joystick_base: Panel
var _joystick_knob: Panel
var _active_touch_index: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_vector: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = 30
	_build_joystick()
	_update_layout()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.connect(_update_layout)
	set_process_input(true)


func _exit_tree() -> void:
	_release_movement_actions()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)


func get_joystick_center() -> Vector2:
	return _joystick_center


func get_joystick_vector() -> Vector2:
	return _joystick_vector


func get_joystick_base() -> Panel:
	return _joystick_base


func get_joystick_knob() -> Panel:
	return _joystick_knob


func get_active_touch_index() -> int:
	return _active_touch_index


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _active_touch_index != -1 or not _is_joystick_touch(event.position):
			return
		_active_touch_index = event.index
		_update_joystick_from_position(event.position)
		get_viewport().set_input_as_handled()
		return

	if event.index != _active_touch_index:
		return
	_active_touch_index = -1
	_set_joystick_vector(Vector2.ZERO)
	get_viewport().set_input_as_handled()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index != _active_touch_index:
		return
	_update_joystick_from_position(event.position)
	get_viewport().set_input_as_handled()


func _is_joystick_touch(position: Vector2) -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	if position.x >= viewport_size.x * 0.5:
		return false
	return position.distance_to(_joystick_center) <= joystick_radius + activation_padding


func _update_joystick_from_position(position: Vector2) -> void:
	var requested_vector := (position - _joystick_center) / joystick_radius
	_set_joystick_vector(requested_vector.limit_length(1.0))


func _set_joystick_vector(value: Vector2) -> void:
	var next_vector := value.limit_length(1.0)
	if next_vector.length() < deadzone:
		next_vector = Vector2.ZERO
	_joystick_vector = next_vector
	_apply_movement_actions()
	_update_knob_position()


func _apply_movement_actions() -> void:
	_set_action_strength(MOVE_LEFT_ACTION, maxf(-_joystick_vector.x, 0.0))
	_set_action_strength(MOVE_RIGHT_ACTION, maxf(_joystick_vector.x, 0.0))
	_set_action_strength(MOVE_FORWARD_ACTION, maxf(-_joystick_vector.y, 0.0))
	_set_action_strength(MOVE_BACKWARD_ACTION, maxf(_joystick_vector.y, 0.0))


func _set_action_strength(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_movement_actions() -> void:
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)
	_joystick_vector = Vector2.ZERO


func _build_joystick() -> void:
	_touch_root = Control.new()
	_touch_root.name = "TouchRoot"
	_touch_root.anchor_right = 1.0
	_touch_root.anchor_bottom = 1.0
	_touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_touch_root)

	_joystick_base = Panel.new()
	_joystick_base.name = "MoveJoystickBase"
	_joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_base.add_theme_stylebox_override("panel", _create_circle_style(
		Color(0.05, 0.07, 0.1, 0.42),
		Color(0.86, 0.9, 0.96, 0.7),
		3,
		ceili(joystick_radius)
	))
	_touch_root.add_child(_joystick_base)

	var move_label := Label.new()
	move_label.name = "MoveLabel"
	move_label.anchor_right = 1.0
	move_label.anchor_bottom = 1.0
	move_label.text = "MOVE"
	move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	move_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	move_label.add_theme_font_size_override("font_size", 18)
	move_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.62))
	move_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_base.add_child(move_label)

	_joystick_knob = Panel.new()
	_joystick_knob.name = "MoveJoystickKnob"
	_joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_knob.add_theme_stylebox_override("panel", _create_circle_style(
		Color(0.72, 0.78, 0.88, 0.72),
		Color(1.0, 1.0, 1.0, 0.9),
		2,
		ceili(knob_radius)
	))
	_touch_root.add_child(_joystick_knob)


func _create_circle_style(
	background: Color,
	border: Color,
	border_width: int,
	corner_radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	return style


func _update_layout() -> void:
	if not is_instance_valid(_joystick_base) or not is_instance_valid(_joystick_knob):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_joystick_center = Vector2(
		left_margin + joystick_radius,
		maxf(joystick_radius + 20.0, viewport_size.y - bottom_margin - joystick_radius)
	)
	_joystick_base.position = _joystick_center - Vector2.ONE * joystick_radius
	_joystick_base.size = Vector2.ONE * joystick_radius * 2.0
	_joystick_knob.size = Vector2.ONE * knob_radius * 2.0
	_update_knob_position()


func _update_knob_position() -> void:
	if not is_instance_valid(_joystick_knob):
		return
	var travel_radius := maxf(joystick_radius - knob_radius, 0.0)
	var knob_center := _joystick_center + _joystick_vector * travel_radius
	_joystick_knob.position = knob_center - Vector2.ONE * knob_radius
