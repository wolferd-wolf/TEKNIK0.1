extends RefCounted
class_name TextureGenerator

const SIZE := 32
const REGISTRY = preload("res://resources/textures/texture_block_registry.tres")
static var _texture_cache: Dictionary = {}

static func generate(block_type: String, seed: int) -> ImageTexture:
	var key := "%s:%d" % [block_type, seed]
	if _texture_cache.has(key): return _texture_cache[key]
	var config: TextureBlockConfig = REGISTRY.get_config(block_type)
	var texture := ImageTexture.create_from_image(_generate_image(config, seed))
	_texture_cache[key] = texture
	return texture

static func get_block_types() -> Array[String]: return REGISTRY.get_block_types()

static func _generate_image(config: TextureBlockConfig, seed: int) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if config == null:
		image.fill(Color.MAGENTA)
		return image
	for y in range(SIZE):
		for x in range(SIZE):
			var value := _cellular_value(x, y, config.frequency, seed + config.seed_offset) if config.noise_mode == "cellular" else _value_noise(x, y, config.frequency, seed + config.seed_offset)
			image.set_pixel(x, y, _palette_sample(config.palette, value))
	_apply_material_detail(image, config, seed)
	if config.overlay_mode == "speckle": _apply_speckles(image, config, seed)
	elif config.overlay_mode == "vein": _apply_veins(image, config, seed)
	return image

static func _apply_material_detail(image: Image, config: TextureBlockConfig, seed: int) -> void:
	match config.material_style:
		"grass": _apply_grass_detail(image, config, seed)
		"soil": _apply_cluster_detail(image, config, seed, 1.0)
		"rock": _apply_rock_detail(image, config, seed)
		"sand": _apply_cluster_detail(image, config, seed, 0.65)
		"wood_grain": _apply_wood_grain(image, config, seed)
		"foliage": _apply_cluster_detail(image, config, seed, 0.8)

static func _apply_grass_detail(image: Image, config: TextureBlockConfig, seed: int) -> void:
	if config.palette.size() < 2: return
	var dark := config.palette[0]
	var light := config.palette[config.palette.size() - 1]
	for y in range(SIZE):
		for x in range(SIZE):
			if _hash_2d(x / 2, y / 2, seed + 911) < config.detail_density * 0.22: image.set_pixel(x, y, dark)
			elif _hash_2d(x, y, seed + 1217) < config.detail_density * 0.08: image.set_pixel(x, y, light)

static func _apply_cluster_detail(image: Image, config: TextureBlockConfig, seed: int, strength: float) -> void:
	if config.palette.size() < 2: return
	var dark := config.palette[0]
	var light := config.palette[config.palette.size() - 1]
	var chance := config.detail_density * strength
	for cell_y in range(0, SIZE, 2):
		for cell_x in range(0, SIZE, 2):
			var value := _value_noise(cell_x, cell_y, config.detail_frequency * 0.72, seed + 1701)
			if value > 0.70 and _hash_2d(cell_x / 2, cell_y / 2, seed + 1811) < chance:
				_stamp_pixel_cluster(image, cell_x, cell_y, light, seed + cell_x * 31 + cell_y * 17)
			elif value < 0.30 and _hash_2d(cell_x / 2, cell_y / 2, seed + 1913) < chance * 0.72:
				_stamp_pixel_cluster(image, cell_x, cell_y, dark, seed + cell_x * 47 + cell_y * 23)

static func _stamp_pixel_cluster(image: Image, cx: int, cy: int, color: Color, seed: int) -> void:
	var shape := int(floor(_hash_2d(cx, cy, seed) * 3.0))
	image.set_pixel(cx, cy, color)
	if cx + 1 < SIZE:
		image.set_pixel(cx + 1, cy, color)
	if shape >= 1 and cy + 1 < SIZE:
		image.set_pixel(cx, cy + 1, color)
	if shape == 2 and cx + 1 < SIZE and cy + 1 < SIZE:
		image.set_pixel(cx + 1, cy + 1, color)

static func _apply_rock_detail(image: Image, config: TextureBlockConfig, seed: int) -> void:
	if config.palette.size() < 3: return
	var dark := config.palette[0]
	var mid := config.palette[1]
	var light := config.palette[config.palette.size() - 1]
	for y in range(SIZE):
		for x in range(SIZE):
	for cell_y in range(0, SIZE, 2):
		for cell_x in range(0, SIZE, 2):
			var face := _cellular_value(cell_x, cell_y, config.detail_frequency, seed + 2201)
			var micro := _hash_2d(cell_x / 2, cell_y / 2, seed + 2299)
			if face < 0.18 and micro < config.detail_density * 0.65: _stamp_pixel_cluster(image, cell_x, cell_y, dark, seed + 2201)
			elif face > 0.84 and micro < config.detail_density * 0.5: _stamp_pixel_cluster(image, cell_x, cell_y, light, seed + 2303)
			elif micro < config.detail_density * 0.18: image.set_pixel(cell_x, cell_y, mid)

static func _apply_wood_grain(image: Image, config: TextureBlockConfig, seed: int) -> void:
	if config.palette.size() < 2: return
	var dark := config.palette[0]
	var light := config.palette[config.palette.size() - 1]
	for y in range(SIZE):
		for x in range(SIZE):
			var grain_x := int(floor(x * config.detail_frequency + sin(y * 0.55 + seed * 0.013) * 1.4))
			var grain := _value_noise(grain_x, y, 0.22, seed + 2701)
			if grain < 0.25 and _hash_2d(x, y / 2, seed + 2711) < config.detail_density * 0.45: image.set_pixel(x, y, dark)
			elif grain > 0.78 and _hash_2d(x, y / 2, seed + 2729) < config.detail_density * 0.32: image.set_pixel(x, y, light)

static func _apply_speckles(image: Image, config: TextureBlockConfig, seed: int) -> void:
	if config.overlay_palette.is_empty(): return
	for y in range(SIZE):
		for x in range(SIZE):
			if _hash_2d(x, y, seed + config.overlay_seed_offset) < config.overlay_density:
				var i := clampi(int(floor(_hash_2d(x + 17, y - 11, seed + 271) * config.overlay_palette.size())), 0, config.overlay_palette.size() - 1)
				image.set_pixel(x, y, config.overlay_palette[i])

static func _apply_veins(image: Image, config: TextureBlockConfig, seed: int) -> void:
	if config.overlay_palette.is_empty(): return
	var mask := PackedByteArray(); mask.resize(SIZE * SIZE)
	for cluster in range(maxi(config.overlay_cluster_count, 1)):
		var cluster_seed := seed + config.overlay_seed_offset + cluster * 104729
		var px := int(floor(_hash_2d(cluster, 17, cluster_seed) * SIZE))
		var py := int(floor(_hash_2d(cluster, 53, cluster_seed + 97) * SIZE))
		var angle := _hash_2d(cluster, 89, cluster_seed + 193) * TAU
		for step in range(maxi(config.overlay_vein_length, 2)):
			var jitter := (_hash_2d(step, cluster, cluster_seed + 313) - 0.5) * 0.9
			var dx := cos(angle + jitter) * float(step)
			var dy := sin(angle + jitter) * float(step)
			_apply_vein_stamp(mask, int(round(px + dx)), int(round(py + dy)), maxi(config.overlay_vein_width, 1), cluster_seed + step * 17)
			if step > 1 and _hash_2d(step, cluster, cluster_seed + 617) < config.overlay_density * 0.18:
				var branch_angle := angle + (PI * 0.45 if _hash_2d(step, cluster, cluster_seed + 911) > 0.5 else -PI * 0.45)
				for branch_step in range(2, 5): _apply_vein_stamp(mask, int(round(px + dx + cos(branch_angle) * branch_step)), int(round(py + dy + sin(branch_angle) * branch_step)), maxi(config.overlay_vein_width, 1), cluster_seed + branch_step * 31)
	for y in range(SIZE):
		for x in range(SIZE):
			if mask[y * SIZE + x] == 0: continue
			var i := clampi(int(floor(_hash_2d(x + 7, y - 13, seed + config.overlay_seed_offset + 4243) * config.overlay_palette.size())), 0, config.overlay_palette.size() - 1)
			image.set_pixel(x, y, config.overlay_palette[i])

static func _apply_vein_stamp(mask: PackedByteArray, cx: int, cy: int, width: int, seed: int) -> void:
	for oy in range(-width, width + 1):
		for ox in range(-width, width + 1):
			var x := cx + ox; var y := cy + oy
			if x < 0 or x >= SIZE or y < 0 or y >= SIZE: continue
			var distance := abs(ox) + abs(oy)
			var keep_chance := 1.0 if distance == 0 else (0.78 if distance == 1 else 0.45)
			if _hash_2d(x, y, seed) < keep_chance: mask[y * SIZE + x] = 1

static func _palette_sample(palette: Array[Color], value: float) -> Color:
	if palette.is_empty(): return Color.WHITE
	return palette[clampi(int(floor(value * palette.size())), 0, palette.size() - 1)]

static func _value_noise(x: int, y: int, f: float, seed: int) -> float:
	var fx := x * f; var fy := y * f; var x0 := int(floor(fx)); var y0 := int(floor(fy)); var tx := fx - x0; var ty := fy - y0
	tx = tx * tx * (3.0 - 2.0 * tx); ty = ty * ty * (3.0 - 2.0 * ty)
	return clampf(lerpf(lerpf(_hash_2d(x0, y0, seed), _hash_2d(x0 + 1, y0, seed), tx), lerpf(_hash_2d(x0, y0 + 1, seed), _hash_2d(x0 + 1, y0 + 1, seed), tx), ty), 0.0, 0.999999)

static func _cellular_value(x: int, y: int, f: float, seed: int) -> float:
	var fx := x * f; var fy := y * f; var cx := int(floor(fx)); var cy := int(floor(fy)); var nearest := 999.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var gx := cx + ox; var gy := cy + oy; var px := gx + _hash_2d(gx, gy, seed); var py := gy + _hash_2d(gx, gy, seed + 7919); var dx := px - fx; var dy := py - fy
			nearest = minf(nearest, dx * dx + dy * dy)
	return 1.0 - clampf(sqrt(nearest) / 0.7071, 0.0, 1.0)

static func _hash_2d(x: int, y: int, seed: int) -> float:
	var n: int = x * 374761393 + y * 668265263 + seed * 1442695041
	n = (n ^ (n >> 13)) * 1274126177; n = n ^ (n >> 16)
	return float(n & 0x7fffffff) / 2147483647.0
