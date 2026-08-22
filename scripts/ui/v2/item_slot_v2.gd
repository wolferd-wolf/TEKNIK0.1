extends Button
class_name ItemSlotV2

## Dumb slot widget (v2 UI). Knows nothing about BlockInventory or any
## backend: it receives a view payload via bind_view() and emits raw
## gesture signals. Mouse input is handled here; touch routing stays in
## the screen (proven pattern on Android, avoids emulated-mouse doubles).

signal slot_tapped(slot_id: int)
signal slot_long_pressed(slot_id: int)
signal slot_secondary(slot_id: int)

const SLOT_SIZE := Vector2(104.0, 78.0)
const SWATCH_SIZE := Vector2(54.0, 54.0)
const LONG_PRESS_SECONDS := 0.45

var _slot_id := -1
var _swatch_style: StyleBoxFlat
var _icon_rect: TextureRect
var _count_label: Label
var _key_label: Label
var _long_press_timer: Timer
var _long_press_consumed := false
var _display_only := false
var _key_number := ""


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	focus_mode = Control.FOCUS_NONE

	var normal := _box(Color(0.55, 0.55, 0.62))
	var hover := _box(Color(0.85, 0.85, 0.92))
	var pressed := _box(Color(0.40, 0.40, 0.46))
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)

	_swatch_style = _flat_box(Color(0.13, 0.13, 0.16), Color(0, 0, 0, 0.45), 4)
	var swatch := PanelContainer.new()
	swatch.name = "Swatch"
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.set_anchors_preset(Control.PRESET_CENTER)
	swatch.offset_left = -SWATCH_SIZE.x * 0.5
	swatch.offset_top = -SWATCH_SIZE.y * 0.5
	swatch.offset_right = SWATCH_SIZE.x * 0.5
	swatch.offset_bottom = SWATCH_SIZE.y * 0.5
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.visible = false
	swatch.add_theme_stylebox_override("panel", _swatch_style)
	add_child(swatch)

	_icon_rect = TextureRect.new()
	_icon_rect.name = "Icon"
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.offset_left = 4
	_icon_rect.offset_top = 4
	_icon_rect.offset_right = -4
	_icon_rect.offset_bottom = -4
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_child(_icon_rect)

	_count_label = Label.new()
	_count_label.name = "Count"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.anchor_left = 0.0
	_count_label.anchor_right = 1.0
	_count_label.anchor_top = 1.0
	_count_label.anchor_bottom = 1.0
	_count_label.offset_left = -SLOT_SIZE.x + 8.0
	_count_label.offset_top = -20.0
	_count_label.offset_right = -6.0
	_count_label.offset_bottom = -4.0
	_count_label.add_theme_font_size_override("font_size", 14)
	_count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 1)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	_key_label = Label.new()
	_key_label.name = "KeyNumber"
	_key_label.text = _key_number
	_key_label.position = Vector2(5, 3)
	_key_label.add_theme_font_size_override("font_size", 12)
	_key_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_key_label)

	_long_press_timer = Timer.new()
	_long_press_timer.one_shot = true
	_long_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_long_press_timer)

	gui_input.connect(_on_gui_input)


func configure(slot_id: int, key_number := "", display_only := false) -> void:
	_slot_id = slot_id
	_display_only = display_only
	_key_number = key_number # applied in _ready; configure may run pre-tree


func get_slot_id() -> int:
	return _slot_id


func is_display_only() -> bool:
	return _display_only


## The only write path into this widget: a prebuilt immutable view payload.
## Keys: texture, tint, swatch_color, count_text, tooltip, dimmed.
func bind_view(view: Dictionary) -> void:
	var texture: Texture2D = view.get("texture")
	var has_item := texture != null
	var swatch := get_node("Swatch") as PanelContainer
	swatch.visible = has_item
	if has_item:
		_swatch_style.bg_color = view.get("swatch_color", Color.WHITE)
		var tint: Color = view.get("tint", Color.WHITE)
		_icon_rect.texture = texture
		_icon_rect.modulate = tint
		tooltip_text = String(view.get("tooltip", ""))
	count_label_set_text(String(view.get("count_text", "")))
	modulate = Color(1, 1, 1, 0.55) if bool(view.get("dimmed", false)) else Color.WHITE


func count_label_set_text(text: String) -> void:
	_count_label.text = text


func get_swatch() -> PanelContainer:
	return get_node("Swatch") as PanelContainer


func get_count_label() -> Label:
	return _count_label


func set_selected(selected: bool) -> void:
	if selected:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.30, 0.28, 0.16)
		style.set_border_width_all(3)
		style.border_color = Color(0.98, 0.80, 0.20)
		style.set_corner_radius_all(6)
		add_theme_stylebox_override("normal", style)
		add_theme_stylebox_override("hover", style)
		if not has_theme_stylebox_override("pressed"):
			add_theme_stylebox_override("pressed", style)
	else:
		add_theme_stylebox_override("normal", _box(Color(0.55, 0.55, 0.62)))
		add_theme_stylebox_override("hover", _box(Color(0.85, 0.85, 0.92)))


func _flat_box(bg: Color, border := Color.TRANSPARENT, width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if width > 0:
		style.set_border_width_all(width)
		style.border_color = border
	style.set_corner_radius_all(4)
	return style


func _box(tint: Color) -> StyleBoxTexture:
	var tex := load("res://assets/textures/icons/default_obsidian.png") as Texture2D
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.modulate_color = tint
	style.texture_margin_left = 2
	style.texture_margin_top = 2
	style.texture_margin_right = 2
	style.texture_margin_bottom = 2
	return style


func _on_gui_input(event: InputEvent) -> void:
	if _display_only:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			slot_secondary.emit(_slot_id)
			accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_long_press_consumed = false
				_long_press_timer.start(LONG_PRESS_SECONDS)
			else:
				_long_press_timer.stop()
				if not _long_press_consumed:
					slot_tapped.emit(_slot_id)
			accept_event()


func _on_long_press_timeout() -> void:
	if _display_only or _long_press_consumed:
		return
	_long_press_consumed = true
	slot_long_pressed.emit(_slot_id)
