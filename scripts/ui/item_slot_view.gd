extends Button
class_name ItemSlotView

## Dumb visual slot for the rehauled UI: renders one stack snapshot and
## reports clicks. All container logic lives in the data layer / screen;
## this widget never mutates anything itself.

signal slot_clicked(view: ItemSlotView, mouse_button_index: int, shift_held: bool)

var context := {} # tags the slot: kind, container, index
var _count_label: Label


static func slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.54, 0.54, 0.58)
	style.border_color = Color(0.24, 0.24, 0.28)
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	return style


func _init(slot_context: Dictionary = {}) -> void:
	context = slot_context
	custom_minimum_size = Vector2(46, 46)
	focus_mode = Control.FOCUS_NONE
	add_theme_stylebox_override("normal", slot_style())
	add_theme_stylebox_override("hover", slot_style())
	add_theme_stylebox_override("pressed", slot_style())
	_count_label = Label.new()
	_count_label.name = "Count"
	_count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_label.offset_left = -26.0
	_count_label.offset_top = -20.0
	_count_label.offset_right = -3.0
	_count_label.offset_bottom = -2.0
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_count_label.add_theme_constant_override("outline_size", 4)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			slot_clicked.emit(self, mb.button_index, mb.shift_pressed)


# Persistent visual children, created once and reused: re-adding same-named
# children per refresh collides with not-yet-freed nodes (Godot renames the
# newcomer), which broke lookups by name.
var _icon_rect: TextureRect
var _swatch_rect: ColorRect
var _glyph_label: Label


func set_stack(stack: Dictionary) -> void:
	var block_id := int(stack.get("block_id", 0))
	var count := int(stack.get("count", 0))
	var icon_tex := ItemRegistry.icon(block_id)
	if icon_tex != null:
		if _icon_rect == null:
			_icon_rect = TextureRect.new()
			_icon_rect.name = "Icon"
			_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
			_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			_icon_rect.offset_left = 5.0
			_icon_rect.offset_top = 5.0
			_icon_rect.offset_right = -5.0
			_icon_rect.offset_bottom = -5.0
			_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_icon_rect)
		_icon_rect.texture = icon_tex
		_icon_rect.modulate = ItemRegistry.icon_tint(block_id)
	if _icon_rect != null:
		_icon_rect.visible = icon_tex != null

	var show_swatch := icon_tex == null and block_id > 0
	if show_swatch:
		if _swatch_rect == null:
			_swatch_rect = ColorRect.new()
			_swatch_rect.name = "Swatch"
			_swatch_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			_swatch_rect.offset_left = 6.0
			_swatch_rect.offset_top = 6.0
			_swatch_rect.offset_right = -6.0
			_swatch_rect.offset_bottom = -6.0
			_swatch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_swatch_rect)
		_swatch_rect.color = ItemRegistry.swatch_color(block_id)
		if _glyph_label == null:
			_glyph_label = Label.new()
			_glyph_label.name = "Glyph"
			_glyph_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_glyph_label.add_theme_font_size_override("font_size", 18)
			_glyph_label.add_theme_color_override("font_outline_color", Color.BLACK)
			_glyph_label.add_theme_constant_override("outline_size", 4)
			_glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_glyph_label)
		_glyph_label.text = ItemRegistry.glyph(block_id)
	if _swatch_rect != null:
		_swatch_rect.visible = show_swatch
	if _glyph_label != null:
		_glyph_label.visible = show_swatch

	_count_label.text = "" if block_id <= 0 or count <= 0 else "x%d" % count
	tooltip_text = "" if block_id <= 0 else ItemRegistry.display_name(block_id)
