extends CanvasLayer
class_name InventoryHotbar

## Hotbar HUD (rewritten): visual item swatches + count badges instead of
## text-only rows. Names/colors come from ItemRegistry so the UI can never
## drift out of sync with the world blocks again.

const HOTBAR_SLOT_COUNT := 9
const ITEM_REGISTRY := preload("res://scripts/items/item_registry.gd")

const SLOT_SIZE := Vector2(104.0, 78.0)
const SWATCH_SIZE := Vector2(54.0, 54.0)
const SLOT_GAP := 6.0

var _slot_panels: Array[PanelContainer] = []
var _swatch_panels: Array[PanelContainer] = []
var _icon_rects: Array[TextureRect] = []
var _swatch_styles: Array[StyleBoxFlat] = []
var _count_labels: Array[Label] = []
var _key_labels: Array[Label] = []
var _normal_style: StyleBoxFlat
var _selected_style: StyleBoxFlat


func _ready() -> void:
	layer = 20
	_build_styles()
	_build_hotbar()


func refresh(slots: Array[Dictionary], selected_slot: int) -> void:
	if _swatch_panels.size() != HOTBAR_SLOT_COUNT:
		return
	for slot_index in range(HOTBAR_SLOT_COUNT):
		var stack := {"block_id": 0, "count": 0}
		if slot_index < slots.size():
			stack = slots[slot_index]
		var block_id := int(stack.get("block_id", 0))
		var count := int(stack.get("count", 0))
		var has_item := block_id > 0 and count > 0

		var visible := has_item
		_swatch_panels[slot_index].visible = visible
		var icon_rect := _icon_rects[slot_index]
		if visible:
			_swatch_styles[slot_index].bg_color = ITEM_REGISTRY.swatch_color(block_id)
			_swatch_panels[slot_index].tooltip_text = ITEM_REGISTRY.display_name(block_id)
			icon_rect.texture = ITEM_REGISTRY.icon(block_id)
			icon_rect.modulate = ITEM_REGISTRY.icon_tint(block_id)

		var count_label := _count_labels[slot_index]
		count_label.text = "x%d" % count if has_item else ""

		_key_labels[slot_index].add_theme_color_override(
			"font_color",
			Color(1, 1, 1, 0.95) if slot_index == selected_slot else Color(1, 1, 1, 0.35)
		)
		var style := _selected_style if slot_index == selected_slot else _normal_style
		_slot_panels[slot_index].add_theme_stylebox_override("panel", style)


func get_slot_panel(slot_index: int) -> PanelContainer:
	return _panel_at(_slot_panels, slot_index)


func get_count_label(slot_index: int) -> Label:
	if slot_index < 0 or slot_index >= _count_labels.size():
		return null
	return _count_labels[slot_index]


func get_swatch(slot_index: int) -> PanelContainer:
	return _panel_at(_swatch_panels, slot_index)


func _panel_at(pool: Array[PanelContainer], slot_index: int) -> PanelContainer:
	if slot_index < 0 or slot_index >= pool.size():
		return null
	return pool[slot_index]


func _build_styles() -> void:
	_normal_style = _slot_box(Color(0.08, 0.09, 0.11, 0.85), Color(1, 1, 1, 0.10), 2)
	_selected_style = _slot_box(Color(0.10, 0.11, 0.14, 0.95), Color(0.98, 0.80, 0.20), 3)


func _slot_box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	return style


func _swatch_box() -> StyleBoxFlat:
	var style := _slot_box(Color.WHITE, Color(0, 0, 0, 0.40), 2)
	style.set_corner_radius_all(4)
	return style


func _build_hotbar() -> void:
	var total_width := SLOT_SIZE.x * HOTBAR_SLOT_COUNT + SLOT_GAP * (HOTBAR_SLOT_COUNT - 1)
	var hotbar_root := MarginContainer.new()
	hotbar_root.name = "HotbarRoot"
	hotbar_root.anchor_left = 0.5
	hotbar_root.anchor_top = 1.0
	hotbar_root.anchor_right = 0.5
	hotbar_root.anchor_bottom = 1.0
	hotbar_root.offset_left = -total_width * 0.5 - 6.0
	hotbar_root.offset_top = -(SLOT_SIZE.y + 28.0)
	hotbar_root.offset_right = total_width * 0.5 + 6.0
	hotbar_root.offset_bottom = -16.0
	hotbar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hotbar_root)

	var row := HBoxContainer.new()
	row.name = "Slots"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(SLOT_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar_root.add_child(row)

	for slot_index in range(HOTBAR_SLOT_COUNT):
		var panel := PanelContainer.new()
		panel.name = "Slot%d" % (slot_index + 1)
		panel.custom_minimum_size = SLOT_SIZE
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _normal_style)
		row.add_child(panel)
		_slot_panels.append(panel)

		var swatch := PanelContainer.new()
		swatch.name = "Swatch"
		swatch.set_anchors_preset(Control.PRESET_CENTER)
		swatch.offset_left = -SWATCH_SIZE.x * 0.5
		swatch.offset_top = -SWATCH_SIZE.y * 0.5
		swatch.offset_right = SWATCH_SIZE.x * 0.5
		swatch.offset_bottom = SWATCH_SIZE.y * 0.5
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.visible = false
		var swatch_style := _swatch_box()
		swatch.add_theme_stylebox_override("panel", swatch_style)

		var icon_rect := TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.offset_left = 4
		icon_rect.offset_top = 4
		icon_rect.offset_right = -4
		icon_rect.offset_bottom = -4
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.add_child(icon_rect)
		_icon_rects.append(icon_rect)

		panel.add_child(swatch)
		_swatch_panels.append(swatch)
		_swatch_styles.append(swatch_style)

		var key_label := Label.new()
		key_label.name = "KeyNumber"
		key_label.text = str(slot_index + 1)
		key_label.position = Vector2(4, 2)
		key_label.add_theme_font_size_override("font_size", 11)
		key_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		key_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		key_label.add_theme_constant_override("shadow_offset_x", 1)
		key_label.add_theme_constant_override("shadow_offset_y", 1)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(key_label)
		_key_labels.append(key_label)

		var count_label := Label.new()
		count_label.name = "Count"
		count_label.text = ""
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.anchor_left = 0.0
		count_label.anchor_right = 1.0
		count_label.anchor_top = 1.0
		count_label.anchor_bottom = 1.0
		count_label.offset_left = -SLOT_SIZE.x + 8.0
		count_label.offset_top = -18.0
		count_label.offset_right = -4.0
		count_label.offset_bottom = -3.0
		count_label.add_theme_font_size_override("font_size", 12)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		count_label.add_theme_constant_override("shadow_offset_x", 1)
		count_label.add_theme_constant_override("shadow_offset_y", 1)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(count_label)
		_count_labels.append(count_label)
