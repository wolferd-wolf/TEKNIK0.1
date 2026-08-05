extends Node
class_name MobileCameraSensitivity

@export var player_path: NodePath = NodePath("../Player")
@export var blocking_touch_controls_path: NodePath = NodePath("../TouchControls")
@export_range(0.0005, 0.01, 0.0001) var radians_per_drag_pixel: float = 0.0035
@export var right_half_only: bool = true
@export var bottom_reserved_height: float = 120.0
@export var force_enabled_for_tests: bool = false

var _player: Node
var _active_look_touch_index: int = -1
var _enabled: bool = false


func _ready() -> void:
	if not has_input_precedence():
		call_deferred("_move_to_input_front")
	_player = get_node_or_null(player_path)
	_enabled = force_enabled_for_tests or DisplayServer.is_touchscreen_available()
	if not _enabled or _player == null:
		return
	if not _player.has_method("apply_look_delta"):
		push_error("MobileCameraSensitivity player does not implement apply_look_delta().")
		_enabled = false
		return
	_player.set("action_look_speed", 0.0)
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not _enabled or _player == null:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _active_look_touch_index == -1 and _is_look_position(event.position):
			_active_look_touch_index = event.index
	elif event.index == _active_look_touch_index:
		_active_look_touch_index = -1


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _active_look_touch_index:
		return
	_player.call("apply_look_delta", event.relative * radians_per_drag_pixel)


func _is_look_position(position: Vector2) -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var viewport_size := viewport.get_visible_rect().size
	if right_half_only and position.x < viewport_size.x * 0.5:
		return false
	return position.y < viewport_size.y - bottom_reserved_height


func _move_to_input_front() -> void:
	var parent := get_parent()
	if parent == null or has_input_precedence():
		return
	# Viewport dispatches `_input` in reverse scene-tree order. Dynamic hosts
	# must keep this adapter after the legacy touch overlay that marks drags handled.
	parent.move_child(self, parent.get_child_count() - 1)


func get_active_look_touch_index() -> int:
	return _active_look_touch_index


func is_mobile_look_enabled() -> bool:
	return _enabled


func has_input_precedence() -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	var blocker := get_node_or_null(blocking_touch_controls_path)
	return blocker == null or get_index() > blocker.get_index()
