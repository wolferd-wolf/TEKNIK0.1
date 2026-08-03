extends CanvasLayer
class_name TouchActionControls

const ACTION_BUTTONS := {
	"JumpButton": StringName("jump"),
	"MineButton": StringName("mine_block"),
	"PlaceButton": StringName("place_block"),
	"CraftButton": StringName("craft_test_recipe"),
}
const HOTBAR_SLOT_COUNT := 9
const HOTBAR_ACTION_PREFIX := "select_hotbar_"

@export var action_button_size := Vector2(112.0, 68.0)
@export var action_button_gap: float = 12.0
@export var action_right_margin: float = 28.0
@export var action_bottom_margin: float = 128.0

var _root: Control
var _action_buttons: Dictionary = {}
var _hotbar_buttons: Array[Button] = []
var _pressed_actions: Dictionary = {}


func _ready() -> void:
	layer = 40
	_build_controls()
	_update_layout()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.connect(_update_layout)


func _exit_tree() -> void:
	for action in _pressed_actions.keys():
		Input.action_release(action)
	_pressed_actions.clear()


func get_action_button(button_name: StringName) -> Button:
	return _action_buttons.get(String(button_name)) as Button


func get_hotbar_button(slot_index: int) -> Button:
	if slot_index < 0 or slot_index >= _hotbar_buttons.size():
		return null
	return _hotbar_buttons[slot_index]


func _build_controls() -> void:
	_root = Control.new()
	_root.name = "TouchActionRoot"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	for button_name in ACTION_BUTTONS.keys():
		var action: StringName = ACTION_BUTTONS[button_name]
		var button := _create_action_button(String(button_name), _label_for_action(action))
		button.button_down.connect(_press_action.bind(action))
		button.button_up.connect(_release_action.bind(action))
		_root.add_child(button)
		_action_buttons[String(button_name)] = button

	for slot_index in range(HOTBAR_SLOT_COUNT):
		var hotbar_button := Button.new()
		hotbar_button.name = "HotbarTouch%d" % (slot_index + 1)
		hotbar_button.flat = true
		hotbar_button.text = ""
		hotbar_button.focus_mode = Control.FOCUS_NONE
		hotbar_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var action := StringName(HOTBAR_ACTION_PREFIX + str(slot_index + 1))
		hotbar_button.button_down.connect(_press_action.bind(action))
		hotbar_button.button_up.connect(_release_action.bind(action))
		_root.add_child(hotbar_button)
		_hotbar_buttons.append(hotbar_button)


func _create_action_button(button_name: String, label_text: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label_text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = action_button_size
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.84, 0.18, 1.0))
	return button


func _label_for_action(action: StringName) -> String:
	match action:
		StringName("jump"):
			return "JUMP"
		StringName("mine_block"):
			return "MINE"
		StringName("place_block"):
			return "PLACE"
		StringName("craft_test_recipe"):
			return "CRAFT"
		_:
			return String(action).to_upper()


func _press_action(action: StringName) -> void:
	if _pressed_actions.has(action):
		return
	_pressed_actions[action] = true
	Input.action_press(action)


func _release_action(action: StringName) -> void:
	_pressed_actions.erase(action)
	Input.action_release(action)


func _update_layout() -> void:
	if not is_instance_valid(_root):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var names := ["JumpButton", "MineButton", "PlaceButton", "CraftButton"]
	for index in range(names.size()):
		var button := _action_buttons.get(names[index]) as Button
		if button == null:
			continue
		var column := index % 2
		var row := index / 2
		button.size = action_button_size
		button.position = Vector2(
			viewport_size.x - action_right_margin - action_button_size.x * float(2 - column) - action_button_gap * float(1 - column),
			viewport_size.y - action_bottom_margin - action_button_size.y * float(2 - row) - action_button_gap * float(1 - row)
		)

	var hotbar_left := viewport_size.x * 0.5 - 498.0
	var hotbar_top := viewport_size.y - 106.0
	for slot_index in range(_hotbar_buttons.size()):
		var hotbar_button := _hotbar_buttons[slot_index]
		hotbar_button.position = Vector2(hotbar_left + float(slot_index) * 110.0, hotbar_top)
		hotbar_button.size = Vector2(104.0, 78.0)
