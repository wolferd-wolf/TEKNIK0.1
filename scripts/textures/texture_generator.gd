extends RefCounted
class_name TextureGenerator

const SIZE := 32
const REGISTRY := preload("res://resources/textures/texture_block_registry.tres")
static var _cache: Dictionary = {}

static func generate(block_type: String, seed: int) -> ImageTexture:
	return generate_face(block_type, "side", seed)

static func generate_face(block_type: String, face: String, seed: int) -> ImageTexture:
	var key := "%s:%s:%d" % [block_type, face, seed]
	if _cache.has(key):
		return _cache[key]
	var config: TextureBlockConfig = REGISTRY.get_config(block_type)
	var image := _generate_face(config, face, seed)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func generate_set(block_type: String, seed: int) -> Dictionary:
	return {"top": generate_face(block_type, "top", seed), "side": generate_face(block_type, "side", seed), "bottom": generate_face(block_type, "bottom", seed)}

static func _generate_face(config: TextureBlockConfig, face: String, seed: int) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if config == null:
		image.fill(Color.MAGENTA)
		return image
	var style := config.top_style if face == "top" else (config.bottom_style if face == "bottom" else config.side_style)
	var s := seed + config.seed_offset + config.variant_offset + _face_offset(face)
	match style:
		"air": image.fill(Color(0, 0, 0, 0))
		"soil": _soil(image, config, s)
		"rock": _rock(image, config, s)
		"sand": _sand(image, config, s)
		"bark": _bark(image, config, s)
		"wood_end": _wood_end(image, config, s)
		"foliage": _foliage(image, config, s)
		"grass_top": _grass_top(image, config, s)
		"grass_side": _grass_side(image, config, s)
		"ore": _ore(image, config, s)
		_: _generic(image, config, s)
	return image

static func _soil(im: Image, c: TextureBlockConfig, s: int) -> void:
	var p := _palette(c.palette, 4); im.fill(p[1])
	_blob(im, 7, 7, 7, 5, p[0], s + 11, 0.60); _blob(im, 21, 8, 6, 5, p[2], s + 23, 0.72)
	_blob(im, 11, 20, 8, 6, p[0], s + 37, 0.66); _blob(im, 25, 23, 7, 6, p[2], s + 51, 0.70)
	for i in range(8):
		var x := 2 + int(_hash(i, 71, s) * 28.0); var y := 2 + int(_hash(i, 89, s) * 28.0)
		_blob(im, x, y, 2 + i % 2, 1 + (i + 1) % 2, p[3] if i % 3 == 0 else p[0], s + 100 + i, 0.55)

static func _rock(im: Image, c: TextureBlockConfig, s: int) -> void:
	var p := _palette(c.palette, 4); im.fill(p[1])
	var plates := [[6,5,7,5],[18,5,7,5],[28,8,5,6],[8,16,7,6],[20,16,7,6],[29,22,5,5],[5,27,6,4],[16,27,7,4],[26,29,5,3]]
	for i in range(plates.size()):
		var q: Array = plates[i]; var x := int(q[0]); var y := int(q[1]); var w := int(q[2]); var h := int(q[3])
		_blob(im, x + 1, y + 1, w, h, p[0], s + 201 + i * 17, 0.52)
		_blob(im, x, y, max(2, w - 1), max(2, h - 1), p[2] if i % 3 == 0 else p[1], s + 241 + i * 17, 0.66)
		if i % 2 == 0: _blob(im, x - 2, y - 2, 2, 1, p[3], s + 281 + i * 17, 0.45)
	for i in range(6):
		_crack(im, 2 + int(_hash(i, 301, s) * 27.0), 3 + int(_hash(i, 331, s) * 25.0), 2 + i % 3, 1 if i % 2 == 0 else -1, p[0], s + 351 + i)

static func _sand(im: Image, c: TextureBlockConfig, s: int) -> void:
	var p := _palette(c.palette, 4); im.fill(p[1])
	for i in range(13):
		var x := 2 + int(_hash(i, 841, s) * 28.0); var y := 2 + int(_hash(i, 859, s) * 28.0)
		_blob(im, x, y, 2 + i % 2, 1 + i % 2, p[2] if i % 4 != 0 else p[0], s + 877 + i, 0.56)
	for i in range(7):
		im.set_pixel(1 + int(_hash(i, 901, s) * 30.0), 1 + int(_hash(i, 919, s) * 30.0), p[3])

static func _bark(im: Image, c: TextureBlockConfig, s: int) -> void:
	var p := _palette(c.palette, 4); im.fill(p[1])
	for band in range(7):
		var x0 := band * 5 + int(_hash(band, 401, s) * 3.0) - 1
		for y in range(SIZE):
			var x := x0 + int(round(sin(y * 0.24 + band * 1.7 + _hash(band, 407, s) * 5.0)))
			if x >= 0 and x < SIZE:
				im.set_pixel(x, y, p[0]);
				if x + 1 < SIZE: im.set_pixel(x + 1, y, p[2])
				if y % 7 == 0 and x + 2 < SIZE: im.set_pixel(x + 2, y, p[3])
	for i in range(5): _blob(im, 3 + int(_hash(i, 451, s) * 26.0), 4 + int(_hash(i, 463, s) * 24.0), 2, 3, p[0], s + 471 + i, 0.65)

static func _wood_end(im: Image, c: TextureBlockConfig, s: int) -> void:
	var p := _palette(c.palette, 4); im.fill(p[1]); var cx := 16; var cy := 16
	for y in range(SIZE):
		for x in range(SIZE):
			var r := sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy))); var ring := int(r / 2.7) % 3
			im.set_pixel(x, y, p[0] if ring == 0 else (p[2] if ring == 1 else p[1]))
	for i in range(5): _blob(im, cx - 10 + int(_hash(i, 503, s) * 20.0), cy - 10 + int(_hash(i, 521, s) * 20.0), 2, 1, p[3], s + 541 + i, 0.5)

static func _foliage(im: Image, c: TextureBlockConfig, s: int) -> void:
	var p := _palette(c.palette, 4); im.fill(p[1])
	_blob(im, 7, 8, 7, 6, p[0], s + 601, 0.58); _blob(im, 20, 7, 8, 7, p[2], s + 619, 0.62)
	_blob(im, 12, 21, 8, 7, p[2], s + 633, 0.60); _blob(im, 27, 24, 6, 5, p[0], s + 651, 0.62)
	for i in range(8): _blob(im, 2 + int(_hash(i, 671, s) * 28.0), 2 + int(_hash(i, 683, s) * 28.0), 1 + i % 2, 2, p[3] if i % 3 == 0 else p[0], s + 701 + i, 0.52)

static func _grass_top(im: Image, c: TextureBlockConfig, s: int) -> void:
	_foliage(im, c, s)

static func _grass_side(im: Image, c: TextureBlockConfig, s: int) -> void:
	var soil := _palette(c.palette, 4); var grass := _palette(c.secondary_palette, 4); im.fill(soil[1])
	for y in range(SIZE):
		var boundary := 9 + int(_hash(y, 739, s) * 5.0)
		if y < boundary:
			for x in range(SIZE):
				var col := grass[1]
				if _hash(x, y, s + 751) < 0.25: col = grass[0]
				elif _hash(x, y, s + 761) > 0.84: col = grass[2]
				im.set_pixel(x, y, col)
		elif y == boundary:
			for x in range(SIZE):
				if _hash(x, y, s + 771) > 0.30: im.set_pixel(x, y, grass[0])
	_blob(im, 6, 19, 6, 5, soil[0], s + 781, 0.62); _blob(im, 21, 23, 7, 5, soil[2], s + 797, 0.68)
	for i in range(6): _blob(im, 3 + int(_hash(i, 811, s) * 26.0), 13 + int(_hash(i, 827, s) * 17.0), 1 + i % 2, 1, soil[3] if i % 3 == 0 else soil[0], s + 839 + i, 0.5)

static func _ore(im: Image, c: TextureBlockConfig, s: int) -> void:
	_rock(im, c, s); var ore := _palette(c.accent_palette, 3)
	for id in range(max(1, c.vein_count)):
		var cs := s + 809 + id * 104729; var x := 3 + int(_hash(id, 17, cs) * 26.0); var y := 3 + int(_hash(id, 53, cs + 97) * 26.0)
		var angle := _hash(id, 89, cs + 193) * TAU; var length := 6 + int(_hash(id, 107, cs + 233) * 6.0)
		for step in range(length):
			angle += (_hash(step, id, cs + 313) - 0.5) * 0.7; x += int(round(cos(angle))); y += int(round(sin(angle))); _stamp_vein(im, x, y, max(c.vein_width, 1), ore, cs + step * 17)
			if step > 2 and _hash(step, id, cs + 617) < c.vein_density:
				var branch := angle + (PI * 0.5 if _hash(step, id, cs + 911) > 0.5 else -PI * 0.5)
				for b in range(2, 5): _stamp_vein(im, x + int(round(cos(branch) * b)), y + int(round(sin(branch) * b)), max(c.vein_width - 1, 1), ore, cs + b * 31)

static func _generic(im: Image, c: TextureBlockConfig, s: int) -> void:
	var p := _palette(c.palette, 3); im.fill(p[1])
	for i in range(9): _blob(im, 2 + int(_hash(i, 901, s) * 28.0), 2 + int(_hash(i, 919, s) * 28.0), 1 + i % 3, 1 + (i + 1) % 2, p[i % p.size()], s + 937 + i, 0.6)

static func _stamp_vein(im: Image, cx: int, cy: int, width: int, palette: Array[Color], s: int) -> void:
	for oy in range(-width, width + 1):
		for ox in range(-width, width + 1):
			var x := cx + ox; var y := cy + oy
			if x < 0 or x >= SIZE or y < 0 or y >= SIZE: continue
			var d := abs(ox) + abs(oy); var keep := 1.0 if d == 0 else (0.78 if d == 1 else 0.35)
			if _hash(x, y, s) < keep: im.set_pixel(x, y, palette[int(_hash(x + 7, y - 13, s + 4243) * palette.size())])

static func _blob(im: Image, cx: int, cy: int, rx: int, ry: int, col: Color, s: int, edge_keep: float) -> void:
	rx = max(rx, 1); ry = max(ry, 1)
	for row in range(-ry, ry + 1):
		var span := max(1, int(round(float(rx) * (1.0 - abs(float(row) / ry) * 0.55))); var off := int(_hash(row + 101, cy + 103, s) * 3.0) - 1
		for col_idx in range(-span, span + 1):
			var x := cx + col_idx + off; var y := cy + row
			if x < 0 or x >= SIZE or y < 0 or y >= SIZE: continue
			if abs(float(col_idx) / span) > 0.70 and _hash(x, y, s + 17) > edge_keep: continue
			im.set_pixel(x, y, col)

static func _crack(im: Image, x: int, y: int, length: int, direction: int, col: Color, s: int) -> void:
	var cx := x; var cy := y
	for step in range(length):
		if cx >= 0 and cx < SIZE and cy >= 0 and cy < SIZE: im.set_pixel(cx, cy, col)
		cx += 1
		if _hash(step, y, s) > 0.55: cy += direction

static func _palette(source: Array[Color], count: int) -> Array[Color]:
	var result: Array[Color] = []
	for i in range(min(count, source.size())): result.append(source[i])
	if result.is_empty(): result.append(Color.MAGENTA)
	return result

static func _face_offset(face: String) -> int:
	match face:
		"top": return 1009
		"bottom": return 2017
		_: return 3011

static func _hash(x: int, y: int, s: int) -> float:
	var n: int = x * 374761393 + y * 668265263 + s * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0x7fffffff) / 2147483647.0
