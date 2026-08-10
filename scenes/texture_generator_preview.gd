extends Control

const TextureGenerator = preload("res://scripts/textures/texture_generator.gd")
const PREVIEW_SEED := 734921
const BLOCK_IDS := ["grass", "dirt", "stone", "sand", "log", "leaves", "iron_ore"]

func _ready() -> void:
	var title := Label.new()
	title.text = "TEKNIK 0.1 — Procedural 32×32 Texture Sets"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	$Margin/VBox.add_child(title)
	for block_id in BLOCK_IDS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 170)
		var label := Label.new()
		label.text = block_id.replace("_", " ").capitalize()
		label.custom_minimum_size = Vector2(130, 0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		for face in ["top", "side", "bottom"]:
			var rect := TextureRect.new()
			rect.custom_minimum_size = Vector2(150, 150)
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.texture = TextureGenerator.generate_face(block_id, face, PREVIEW_SEED)
			row.add_child(rect)
		$Margin/VBox.add_child(row)
