extends CanvasLayer
class_name HudHotbar

## Rehauled bottom-of-screen hotbar: nine read-only ItemSlotViews plus the
## selected-slot frame. Selection state lives in the player controller; this
## layer only renders snapshots and reports clicks.

signal hotbar_slot_selected(slot_index: int)

const SLOT_COUNT := 9

var _slots: Array[ItemSlotView] = []
var _frames: Array[Panel] = []
var _selected := 0


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bar := HBoxContainer.new()
	bar.name = "Bar"
	bar.add_theme_constant_override("separation", 4)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -14.0
	root.add_child(bar)

	for slot_index in range(SLOT_COUNT):
		var frame := Panel.new()
		frame.name = "Slot%d" % (slot_index + 1)
		frame.custom_minimum_size = Vector2(50, 50)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = Color(0, 0, 0, 0)
		frame_style.border_color = Color(0.95, 0.95, 0.95, 0.9)
		frame_style.set_border_width_all(2)
		frame.add_theme_stylebox_override("panel", frame_style)
		bar.add_child(frame)

		var view := ItemSlotView.new({"kind": "hud", "index": slot_index})
		view.name = "View"
		view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		view.position = Vector2(2, 2)
		view.slot_clicked.connect(_on_slot_clicked)
		frame.add_child(view)

		_frames.append(frame)
		_slots.append(view)


func _on_slot_clicked(view: ItemSlotView, _mouse_button_index: int, _shift_held: bool) -> void:
	hotbar_slot_selected.emit(int(view.context.get("index", 0)))


func refresh(slots: Array[Dictionary], selected_index: int) -> void:
	_selected = clampi(selected_index, 0, SLOT_COUNT - 1)
	for slot_index in range(_slots.size()):
		_slots[slot_index].set_stack(slots[slot_index] if slot_index < slots.size() else {})
	for frame_index in range(_frames.size()):
		var style: StyleBoxFlat = _frames[frame_index].get_theme_stylebox("panel")
		style.border_color = (
			Color(1, 1, 1, 1) if frame_index == _selected else Color(0.95, 0.95, 0.95, 0.25)
		)
