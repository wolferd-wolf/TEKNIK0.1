extends SceneTree
const TextureGenerator = preload("res://scripts/textures/texture_generator.gd")
const SEED := 734921
func _init() -> void:
	var failures: Array[String] = []
	var blocks = TextureGenerator.get_block_types()
	for block_id in blocks:
		var a: Image = TextureGenerator.generate(block_id, SEED).get_image(); var b: Image = TextureGenerator.generate(block_id, SEED).get_image()
		if a.get_width() != 32 or a.get_height() != 32: failures.append("WRONG_SIZE %s" % block_id)
		if a.get_data() != b.get_data(): failures.append("NON_DETERMINISTIC %s" % block_id)
	var same_seed = TextureGenerator.generate("dirt", SEED).get_image().get_data(); var other_seed = TextureGenerator.generate("dirt", SEED + 1).get_image().get_data()
	if same_seed == other_seed: failures.append("SEED_HAS_NO_EFFECT dirt")
	var ore = TextureGenerator.generate("iron_ore", SEED).get_image(); var ore_mask := {}
	var ore_pixels := 0
	for y in range(32):
		for x in range(32):
			var c = ore.get_pixel(x, y)
			if c.r > 0.58 and c.g < 0.5:
				ore_mask[Vector2i(x, y)] = true
				ore_pixels += 1
	if ore_pixels < 20 or ore_pixels > 180: failures.append("ORE_VEIN_PIXEL_COUNT=%d" % ore_pixels)
	var largest_cluster := _largest_ore_cluster(ore_mask)
	if largest_cluster < 4: failures.append("ORE_VEIN_CLUSTER_TOO_SMALL=%d" % largest_cluster)
	var isolated := 0
	for p in ore_mask:
		var has_neighbor := false
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == 0 and oy == 0: continue
				if ore_mask.has(p + Vector2i(ox, oy)):
					has_neighbor = true
		if not has_neighbor: isolated += 1
	if isolated > maxi(2, int(ceil(ore_pixels * 0.08))): failures.append("ORE_ISOLATED_PIXELS=%d" % isolated)
	var preview := Image.create(128, 64, false, Image.FORMAT_RGBA8); preview.fill(Color(0.08, 0.08, 0.08, 1))
	for i in range(blocks.size()): preview.blit_rect(TextureGenerator.generate(blocks[i], SEED).get_image(), Rect2i(0, 0, 32, 32), Vector2i((i % 4) * 32, (i / 4) * 32))
	var dir = ProjectSettings.globalize_path("res://artifacts"); DirAccess.make_dir_recursive_absolute(dir); preview.resize(1024, 512, Image.INTERPOLATE_NEAREST); preview.save_png(dir + "/texture_generator_preview.png")
	if failures.is_empty():
		print("TEXTURE_GENERATOR_GATE_PASS"); print("DETERMINISM_PASS blocks=%d seed=%d" % [blocks.size(), SEED]); print("SEED_VARIATION_PASS"); print("ORE_VEIN_PIXELS=%d" % ore_pixels); print("ORE_LARGEST_CLUSTER=%d" % largest_cluster); quit(0)
	for failure in failures: push_error(failure)
	quit(1)

static func _largest_ore_cluster(mask: Dictionary) -> int:
	var visited := {}
	var largest := 0
	for start in mask:
		if visited.has(start): continue
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		var size := 0
		var head := 0
		while head < queue.size():
			var p: Vector2i = queue[head]; head += 1; size += 1
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0: continue
					var next := p + Vector2i(ox, oy)
					if mask.has(next) and not visited.has(next):
						visited[next] = true; queue.append(next)
		largest = maxi(largest, size)
	return largest
