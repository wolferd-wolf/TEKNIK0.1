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
const LOOK_LEFT_ACTION := StringName("look_left")
const LOOK_RIGHT_ACTION := StringName("look_right")
const LOOK_UP_ACTION := StringName("look_up")
const LOOK_DOWN_ACTION := StringName("look_down")
const LOOK_ACTIONS := [
	LOOK_LEFT_ACTION,
	LOOK_RIGHT_ACTION,
	LOOK_UP_ACTION,
	LOOK_DOWN_ACTION,
]

@export var joystick_radius: float = 84.0
@export var knob_radius: float = 34.0
@export var activation_padding: float = 28.0
@export var deadzone: float = 0.15
@export var left_margin: float = 36.0
@export var bottom_margin: float = 120.0
@export var look_drag_pixels_for_full_strength: float = 64.0
@export var look_deadzone: float = 0.05
@export var look_bottom_reserved_height: float = 120.0
@export var look_hint_margin: float = 24.0

var _touch_root: Control
var _joystick_base: Panel
var _joystick_knob: Panel
var _look_hint: PanelContainer
var _look_hint_label: Label
var _look_hint_normal_style: StyleBoxFlat
var _look_hint_active_style: StyleBoxFlat
var _active_touch_index: int = -1
var _active_look_touch_index: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_vector: Vector2 = Vector2.ZERO
var _look_vector: Vector2 = Vector2.ZERO
var _look_action_frames_remaining: int = 0


func _ready() -> void:
	layer = 30
	process_priority = 100
	_build_touch_controls()
	_update_layout()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.connect(_update_layout)
	set_process_input(true)


func _process(_delta: float) -> void:
	if _look_action_frames_remaining <= 0:
		return
	_look_action_frames_remaining -= 1
	if _look_action_frames_remaining == 0:
		_release_look_actions()


func _exit_tree() -> void:
	_release_movement_actions()
	_release_look_actions()


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


func get_active_look_touch_index() -> int:
	return _active_look_touch_index


func get_look_vector() -> Vector2:
	return _look_vector


func get_look_hint() -> PanelContainer:
	return _look_hint


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _active_touch_index == -1 and _is_joystick_touch(event.position):
			_active_touch_index = event.index
			_update_joystick_from_position(event.position)
			get_viewport().set_input_as_handled()
			return
		if _active_look_touch_index == -1 and _is_look_touch(event.position):
			_active_look_touch_index = event.index
			_set_look_hint_active(true)
			get_viewport().set_input_as_handled()
		return

	var handled := false
	if event.index == _active_touch_index:
		_active_touch_index = -1
		_set_joystick_vector(Vector2.ZERO)
		handled = true
	if event.index == _active_look_touch_index:
		_active_look_touch_index = -1
		_release_look_actions()
		_set_look_hint_active(false)
		handled = true
	if handled:
		get_viewport().set_input_as_handled()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index == _active_touch_index:
		_update_joystick_from_position(event.position)
		get_viewport().set_input_as_handled()
		return
	if event.index == _active_look_touch_index:
		_apply_look_drag(event.relative)
		get_viewport().set_input_as_handled()


func _is_joystick_touch(position: Vector2) -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	if position.x >= viewport_size.x * 0.5:
		return false
	return position.distance_to(_joystick_center) <= joystick_radius + activation_padding


func _is_look_touch(position: Vector2) -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	return (
		position.x >= viewport_size.x * 0.5
		and position.y < viewport_size.y - look_bottom_reserved_height
	)


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


func _apply_look_drag(relative: Vector2) -> void:
	var safe_full_strength := maxf(look_drag_pixels_for_full_strength, 1.0)
	var next_vector := (relative / safe_full_strength).limit_length(1.0)
	if next_vector.length() < look_deadzone:
		next_vector = Vector2.ZERO
	_look_vector = next_vector
	_set_action_strength(LOOK_LEFT_ACTION, maxf(-_look_vector.x, 0.0))
	_set_action_strength(LOOK_RIGHT_ACTION, maxf(_look_vector.x, 0.0))
	_set_action_strength(LOOK_UP_ACTION, maxf(-_look_vector.y, 0.0))
	_set_action_strength(LOOK_DOWN_ACTION, maxf(_look_vector.y, 0.0))
	_look_action_frames_remaining = 2 if not _look_vector.is_zero_approx() else 0


func _set_action_strength(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_movement_actions() -> void:
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)
	_joystick_vector = Vector2.ZERO


func _release_look_actions() -> void:
	for action in LOOK_ACTIONS:
		Input.action_release(action)
	_look_vector = Vector2.ZERO
	_look_action_frames_remaining = 0


func _build_touch_controls() -> void:
	_touch_root = Control.new()
	_touch_root.name = "TouchRoot"
	_touch_root.anchor_right = 1.0
	_touch_root.anchor_bottom = 1.0
	_touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_touch_root)

	_build_joystick()
	_build_look_hint()


func _build_joystick() -> void:
	_joystick_base = Panel.new()
	_joystick_base.name = "MoveJoystickBase"
	_joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_base.add_theme_stylebox_override("panel", _create_rounded_style(
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
	_joystick_knob.add_theme_stylebox_override("panel", _create_rounded_style(
		Color(0.72, 0.78, 0.88, 0.72),
		Color(1.0, 1.0, 1.0, 0.9),
		2,
		ceili(knob_radius)
	))
	_touch_root.add_child(_joystick_knob)


func _build_look_hint() -> void:
	_look_hint_normal_style = _create_rounded_style(
		Color(0.05, 0.07, 0.1, 0.34),
		Color(0.86, 0.9, 0.96, 0.62),
		2,
		12
	)
	_look_hint_active_style = _create_rounded_style(
		Color(0.16, 0.18, 0.22, 0.68),
		Color(1.0, 0.82, 0.12, 0.96),
		4,
		12
	)
	_look_hint = PanelContainer.new()
	_look_hint.name = "LookHint"
	_look_hint.custom_minimum_size = Vector2(220.0, 54.0)
	_look_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_look_hint.add_theme_stylebox_override("panel", _look_hint_normal_style)
	_touch_root.add_child(_look_hint)

	_look_hint_label = Label.new()
	_look_hint_label.name = "Label"
	_look_hint_label.text = "DRAG TO LOOK"
	_look_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_look_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_look_hint_label.add_theme_font_size_override("font_size", 18)
	_look_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.78))
	_look_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_look_hint.add_child(_look_hint_label)


func _set_look_hint_active(active: bool) -> void:
	if not is_instance_valid(_look_hint):
		return
	_look_hint.add_theme_stylebox_override(
		"panel",
		_look_hint_active_style if active else _look_hint_normal_style
	)


func _create_rounded_style(
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
	if (
		not is_instance_valid(_joystick_base)
		or not is_instance_valid(_joystick_knob)
		or not is_instance_valid(_look_hint)
	):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_joystick_center = Vector2(
		left_margin + joystick_radius,
		maxf(joystick_radius + 20.0, viewport_size.y - bottom_margin - joystick_radius)
	)
	_joystick_base.position = _joystick_center - Vector2.ONE * joystick_radius
	_joystick_base.size = Vector2.ONE * joystick_radius * 2.0
	_joystick_knob.size = Vector2.ONE * knob_radius * 2.0
	_look_hint.position = Vector2(
		viewport_size.x - look_hint_margin - 220.0,
		look_hint_margin
	)
	_look_hint.size = Vector2(220.0, 54.0)
	_update_knob_position()


func _update_knob_position() -> void:
	if not is_instance_valid(_joystick_knob):
		return
	var travel_radius := maxf(joystick_radius - knob_radius, 0.0)
	var knob_center := _joystick_center + _joystick_vector * travel_radius
	_joystick_knob.position = knob_center - Vector2.ONE * knob_radius
