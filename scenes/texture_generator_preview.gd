extends Control
const TextureGenerator = preload("res://scripts/textures/texture_generator.gd")
const LABELS := {"air":"Air","grass":"Grass","dirt":"Dirt","stone":"Stone","sand":"Sand","log":"Wood / Log","leaves":"Leaves","iron_ore":"Iron Ore (preview config)"}
const PREVIEW_SEED := 734921
func _ready() -> void:
	var title := Label.new(); title.text="TEKNIK 0.1 — Procedural 16×16 Block Texture Preview"; title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size",22); $Margin/VBox.add_child(title)
	var grid := GridContainer.new(); grid.columns=4; grid.add_theme_constant_override("h_separation",20); grid.add_theme_constant_override("v_separation",20); $Margin/VBox.add_child(grid)
	for block_id in TextureGenerator.get_block_types():
		var item:=VBoxContainer.new(); item.custom_minimum_size=Vector2(180,220)
		var label:=Label.new(); label.text=LABELS.get(block_id,block_id); label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; item.add_child(label)
		var rect:=TextureRect.new(); rect.custom_minimum_size=Vector2(160,160); rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; rect.texture=TextureGenerator.generate(block_id,PREVIEW_SEED); item.add_child(rect); grid.add_child(item)
