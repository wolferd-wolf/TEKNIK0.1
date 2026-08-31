extends CanvasLayer
class_name InventoryHotbar

const THEME := preload("res://scripts/ui/teknik_theme.gd")

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
var _slot_swatches: Array[Panel] = []
var _slot_counts: Array[Label] = []
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
		_slot_labels[slot_index].text = str(slot_index + 1)
		_slot_swatches[slot_index].add_theme_stylebox_override(
			"panel", THEME.block_swatch_style(THEME.block_color(block_id))
		)
		_slot_swatches[slot_index].tooltip_text = block_name
		_slot_counts[slot_index].text = str(count) if count > 0 else ""
		_slot_panels[slot_index].add_theme_stylebox_override(
			"panel",
			_selected_style if slot_index == selected_slot else _normal_style
		)


func _build_styles() -> void:
	_normal_style = THEME.panel_style()
	_selected_style = THEME.selected_panel_style()


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

		# Layered content: block-color swatch fills most of the slot, with the
		# slot number pinned top-left and stack count pinned bottom-right --
		# replaces the old stacked "1\nGRASS x3" text block.
		var content := Control.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.custom_minimum_size = Vector2(96.0, 70.0)
		panel.add_child(content)

		var swatch := Panel.new()
		swatch.name = "Swatch"
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.set_anchors_preset(Control.PRESET_CENTER)
		swatch.offset_left = -22.0
		swatch.offset_top = -22.0
		swatch.offset_right = 22.0
		swatch.offset_bottom = 22.0
		swatch.add_theme_stylebox_override("panel", THEME.block_swatch_style(THEME.block_color(0)))
		content.add_child(swatch)
		_slot_swatches.append(swatch)

		var number_label := Label.new()
		number_label.name = "SlotNumber"
		number_label.text = str(slot_index + 1)
		number_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		number_label.offset_left = 4.0
		number_label.offset_top = 2.0
		number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		THEME.style_label(number_label, 13, THEME.COLOR_TEXT_SECONDARY)
		content.add_child(number_label)
		_slot_labels.append(number_label)

		var count_label := Label.new()
		count_label.name = "Count"
		count_label.text = ""
		count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count_label.offset_left = -34.0
		count_label.offset_top = -22.0
		count_label.offset_right = -4.0
		count_label.offset_bottom = -2.0
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		THEME.style_label(count_label, 16, THEME.COLOR_TEXT_PRIMARY)
		content.add_child(count_label)
		_slot_counts.append(count_label)
