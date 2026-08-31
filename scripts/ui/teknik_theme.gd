extends RefCounted
class_name TeknikTheme

# Shared visual language for TEKNIK's UI. Industrial/engineering palette:
# dark graphite panels, safety-amber accent, steel-gray borders. Every UI
# script builds its own Controls in code (there's no shared .tscn UI), so
# this is a set of style-builder helpers rather than a Theme resource --
# call these instead of hand-rolling StyleBoxFlat/font overrides inline.

const COLOR_PANEL_BG := Color(0.075, 0.086, 0.098, 0.92)
const COLOR_PANEL_BG_RAISED := Color(0.11, 0.125, 0.145, 0.94)
const COLOR_BORDER := Color(0.34, 0.38, 0.43, 0.9)
const COLOR_ACCENT := Color(1.0, 0.62, 0.13, 1.0)
const COLOR_ACCENT_DIM := Color(1.0, 0.62, 0.13, 0.5)
const COLOR_TEXT_PRIMARY := Color(0.93, 0.95, 0.97, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.66, 0.71, 0.77, 1.0)
const COLOR_TEXT_ON_ACCENT := Color(0.1, 0.07, 0.02, 1.0)
const COLOR_DIM_BACKDROP := Color(0.02, 0.03, 0.04, 0.82)

const CORNER_RADIUS := 6
const BORDER_WIDTH := 2
const BORDER_WIDTH_ACTIVE := 3


static func panel_style(
	bg: Color = COLOR_PANEL_BG,
	border: Color = COLOR_BORDER,
	border_width: int = BORDER_WIDTH,
	corner_radius: int = CORNER_RADIUS
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style


static func selected_panel_style() -> StyleBoxFlat:
	return panel_style(COLOR_PANEL_BG_RAISED, COLOR_ACCENT, BORDER_WIDTH_ACTIVE)


# Applies normal/hover/pressed/focus styleboxes to a real Button control.
# Buttons that are invisible touch-hitboxes (flat=true, no visible panel)
# should not call this.
static func style_button(button: Button, accent_on_press: bool = true) -> void:
	button.add_theme_stylebox_override("normal", panel_style())
	button.add_theme_stylebox_override("hover", panel_style(COLOR_PANEL_BG_RAISED, COLOR_BORDER))
	button.add_theme_stylebox_override(
		"pressed",
		panel_style(COLOR_PANEL_BG_RAISED, COLOR_ACCENT, BORDER_WIDTH_ACTIVE) if accent_on_press else panel_style(COLOR_PANEL_BG_RAISED)
	)
	button.add_theme_stylebox_override("focus", panel_style())
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT_PRIMARY)


static func style_label(
	label: Label,
	font_size: int = 16,
	color: Color = COLOR_TEXT_PRIMARY,
	with_outline: bool = false
) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if with_outline:
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		label.add_theme_constant_override("outline_size", 5)
	else:
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)


# Small flat color swatch used as a stand-in block icon in the hotbar/
# inventory until real item art exists. Not a texture -- a styled Panel.
static func block_swatch_style(block_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = block_color
	style.set_corner_radius_all(3)
	style.border_color = Color(0.0, 0.0, 0.0, 0.35)
	style.set_border_width_all(1)
	return style


# Approximate representative color per block id, used for block_swatch_style.
const BLOCK_COLORS := {
	0: Color(0.2, 0.21, 0.23, 0.4),   # empty
	1: Color(0.36, 0.62, 0.24, 1.0),  # grass
	2: Color(0.46, 0.33, 0.21, 1.0),  # dirt
	3: Color(0.55, 0.55, 0.57, 1.0),  # stone
	4: Color(0.82, 0.74, 0.52, 1.0),  # sand
	5: Color(0.42, 0.29, 0.16, 1.0),  # log
	6: Color(0.24, 0.5, 0.22, 1.0),   # leaves
}


static func block_color(block_id: int) -> Color:
	return BLOCK_COLORS.get(block_id, Color(0.5, 0.5, 0.5, 1.0))
