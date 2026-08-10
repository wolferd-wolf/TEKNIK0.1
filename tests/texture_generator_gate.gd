extends SceneTree

const TextureGenerator = preload("res://scripts/textures/texture_generator.gd")
const SEED := 734921
const BLOCKS := ["grass", "dirt", "stone", "sand", "log", "leaves", "iron_ore"]
const FACES := ["top", "side", "bottom"]

func _init() -> void:
	var failures: Array[String] = []
	var preview := Image.create(1024, 2240, false, Image.FORMAT_RGBA8)
	preview.fill(Color(0.055, 0.06, 0.07, 1))
	for i in range(BLOCKS.size()):
		var block_id: String = BLOCKS[i]
		var row_y := i * 320
		for face_index in range(FACES.size()):
			var face: String = FACES[face_index]
			var a: Image = TextureGenerator.generate_face(block_id, face, SEED).get_image()
			var b: Image = TextureGenerator.generate_face(block_id, face, SEED).get_image()
			if a.get_width() != 32 or a.get_height() != 32: failures.append("WRONG_SIZE %s/%s" % [block_id, face])
			if a.get_data() != b.get_data(): failures.append("NON_DETERMINISTIC %s/%s" % [block_id, face])
			var metrics := _metrics(a)
			print("METRIC %s/%s colors=%d dominant=%.3f same_h=%.3f same_v=%.3f" % [block_id, face, metrics["colors"], metrics["dominant"], metrics["same_h"], metrics["same_v"]])
			var enlarged := a.duplicate(); enlarged.resize(320, 320, Image.INTERPOLATE_NEAREST)
			preview.blit_rect(enlarged, Rect2i(0, 0, 320, 320), Vector2i(64 + face_index * 320, row_y))
		preview.fill_rect(Rect2i(0, row_y, 64, 320), Color(0.10, 0.11, 0.12, 1))
		preview.fill_rect(Rect2i(60, row_y, 4, 320), Color(0.35, 0.36, 0.38, 1))
		preview.fill_rect(Rect2i(64, row_y + 316, 960, 4), Color(0.20, 0.21, 0.22, 1))
	var same: PackedByteArray = TextureGenerator.generate_face("dirt", "side", SEED).get_image().get_data()
	var different: PackedByteArray = TextureGenerator.generate_face("dirt", "side", SEED + 1).get_image().get_data()
	if same == different: failures.append("SEED_HAS_NO_EFFECT dirt/side")
	if TextureGenerator.generate_face("grass", "top", SEED).get_image().get_data() == TextureGenerator.generate_face("grass", "side", SEED).get_image().get_data(): failures.append("FACE_SET_COLLAPSED grass")
	if TextureGenerator.generate_face("log", "top", SEED).get_image().get_data() == TextureGenerator.generate_face("log", "side", SEED).get_image().get_data(): failures.append("FACE_SET_COLLAPSED log")
	var ore: Image = TextureGenerator.generate_face("iron_ore", "side", SEED).get_image(); var ore_pixels := 0
	for y in range(32):
		for x in range(32):
			var c: Color = ore.get_pixel(x, y)
			if c.r > 0.40 and c.g < 0.65 and c.r > c.g * 1.15: ore_pixels += 1
	if ore_pixels < 20: failures.append("ORE_TOO_SPARSE %d" % ore_pixels)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("artifacts"))
	var save_error := preview.save_png("artifacts/texture_generator_preview.png")
	if save_error != OK: failures.append("PREVIEW_SAVE_FAILED %d" % save_error)
	if failures.is_empty():
		print("TEXTURE_SET_GATE_PASS")
		print("DETERMINISM_PASS blocks=%d seed=%d" % [BLOCKS.size(), SEED])
		print("SEED_VARIATION_PASS")
		print("FACE_SET_PASS top_side_bottom")
		print("ORE_VEIN_PASS pixels=%d" % ore_pixels)
		quit(0)
	for failure in failures: push_error(failure)
	quit(1)

func _metrics(im: Image) -> Dictionary:
	var counts: Dictionary = {}; var same_h := 0; var same_v := 0; var total_h := 32 * 31; var total_v := 32 * 31
	for y in range(32):
		for x in range(32):
			var key := im.get_pixel(x, y).to_html(false); counts[key] = int(counts.get(key, 0)) + 1
			if x < 31 and im.get_pixel(x, y) == im.get_pixel(x + 1, y): same_h += 1
			if y < 31 and im.get_pixel(x, y) == im.get_pixel(x, y + 1): same_v += 1
	var dominant := 0
	for value in counts.values(): dominant = max(dominant, int(value))
	return {"colors": counts.size(), "dominant": float(dominant) / 1024.0, "same_h": float(same_h) / total_h, "same_v": float(same_v) / total_v}
