extends CanvasLayer
class_name InventoryHotbar

const HOTBAR_SLOT_COUNT := 9
const BLOCK_NAMES := {
	0: "EMPTY",
	1: "GRASS",
	2: "DIRT",
	3: "STONE",
	4: "SAND",
	5: "LOG",
	6: "LEAVES",
}

var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _normal_style: StyleBoxFlat
var _selected_style: StyleBoxFlat


func _ready() -> void:
	layer = 20
	_build_styles()
	_build_hotbar()


func refresh(slots: Array[Dictionary], selected_slot: int) -> void:
	if _slot_labels.size() != HOTBAR_SLOT_COUNT:
		return

	for slot_index in range(HOTBAR_SLOT_COUNT):
		var slot := {"block_id": 0, "count": 0}
		if slot_index < slots.size():
			slot = slots[slot_index]
		var block_id := int(slot.get("block_id", 0))
		var count := int(slot.get("count", 0))
		var block_name := String(BLOCK_NAMES.get(block_id, "BLOCK %d" % block_id))
		_slot_labels[slot_index].text = "%d\n%s x%d" % [slot_index + 1, block_name, count]
		_slot_panels[slot_index].add_theme_stylebox_override(
			"panel",
			_selected_style if slot_index == selected_slot else _normal_style
		)


func _build_styles() -> void:
	# Use theme's default PanelContainer style (shadcn dark theme provides one)
	# Just add corner radius and selection highlight
	_normal_style = StyleBoxFlat.new()
	_normal_style.corner_radius_top_left = 4
	_normal_style.corner_radius_top_right = 4
	_normal_style.corner_radius_bottom_left = 4
	_normal_style.corner_radius_bottom_right = 4

	_selected_style = StyleBoxFlat.new()
	_selected_style.corner_radius_top_left = 4
	_selected_style.corner_radius_top_right = 4
	_selected_style.corner_radius_bottom_left = 4
	_selected_style.corner_radius_bottom_right = 4
	_selected_style.border_color = Color(1.0, 0.82, 0.12, 1.0)
	_set_border_width(_selected_style, 4)


func _set_border_width(style: StyleBoxFlat, width: int) -> void:
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width


func _build_hotbar() -> void:
	var hotbar_root := MarginContainer.new()
	hotbar_root.name = "HotbarRoot"
	hotbar_root.anchor_left = 0.5
	hotbar_root.anchor_top = 1.0
	hotbar_root.anchor_right = 0.5
	hotbar_root.anchor_bottom = 1.0
	hotbar_root.offset_left = -504.0
	hotbar_root.offset_top = -112.0
	hotbar_root.offset_right = 504.0
	hotbar_root.offset_bottom = -20.0
	hotbar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar_root.add_theme_constant_override("margin_left", 6)
	hotbar_root.add_theme_constant_override("margin_top", 6)
	hotbar_root.add_theme_constant_override("margin_right", 6)
	hotbar_root.add_theme_constant_override("margin_bottom", 6)
	add_child(hotbar_root)

	var row := HBoxContainer.new()
	row.name = "Slots"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	hotbar_root.add_child(row)

	for slot_index in range(HOTBAR_SLOT_COUNT):
		var panel := PanelContainer.new()
		panel.name = "Slot%d" % (slot_index + 1)
		panel.custom_minimum_size = Vector2(104.0, 78.0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _normal_style)
		row.add_child(panel)
		_slot_panels.append(panel)

		var label := Label.new()
		label.name = "Content"
		label.text = "%d\nEMPTY x0" % (slot_index + 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)
		_slot_labels.append(label)
