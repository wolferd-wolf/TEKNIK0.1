extends RefCounted

const SIZE = 32
static var _registry = null
static var _cache = {}

static func generate(block_type: String, seed: int) -> ImageTexture:
	return generate_face(block_type, "side", seed)

static func generate_face(block_type: String, face: String, seed: int) -> ImageTexture:
	var key = "%s:%s:%d" % [block_type, face, seed]
	if _cache.has(key):
		return _cache[key]
	var registry = _get_registry()
	var config = registry.get_config(block_type)
	var image = _make_face(config, face, seed)
	var texture = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func generate_set(block_type: String, seed: int) -> Dictionary:
	var result = {}
	result["top"] = generate_face(block_type, "top", seed)
	result["side"] = generate_face(block_type, "side", seed)
	result["bottom"] = generate_face(block_type, "bottom", seed)
	return result

static func _get_registry():
	if _registry == null:
		_registry = load("res://resources/textures/texture_block_registry.tres")
	return _registry

static func _make_face(config, face: String, seed: int) -> Image:
	var image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if config == null:
		image.fill(Color(1, 0, 1, 1))
		return image
	var style = config.side_style
	if face == "top":
		style = config.top_style
	elif face == "bottom":
		style = config.bottom_style
	var s = seed + config.seed_offset + config.variant_offset + _face_offset(face)
	if style == "air":
		image.fill(Color(0, 0, 0, 0))
	elif style == "soil":
		_soil(image, config, s)
	elif style == "rock":
		_rock(image, config, s)
	elif style == "sand":
		_sand(image, config, s)
	elif style == "bark":
		_bark(image, config, s)
	elif style == "wood_end":
		_wood_end(image, config, s)
	elif style == "foliage":
		_foliage(image, config, s)
	elif style == "grass_top":
		_foliage(image, config, s)
	elif style == "grass_side":
		_grass_side(image, config, s)
	elif style == "ore":
		_ore(image, config, s)
	else:
		_generic(image, config, s)
	return image

static func _soil(image: Image, config, seed: int) -> void:
	var palette = _palette(config.palette, 4)
	image.fill(palette[1])
	_blob(image, 7, 7, 7, 5, palette[0], seed + 11, 0.60)
	_blob(image, 21, 8, 6, 5, palette[2], seed + 23, 0.72)
	_blob(image, 11, 20, 8, 6, palette[0], seed + 37, 0.66)
	_blob(image, 25, 23, 7, 6, palette[2], seed + 51, 0.70)
	var i = 0
	while i < 8:
		var x = 2 + int(_hash(i, 71, seed) * 28.0)
		var y = 2 + int(_hash(i, 89, seed) * 28.0)
		var color = palette[0]
		if i % 3 == 0:
			color = palette[3]
		_blob(image, x, y, 2 + i % 2, 1 + (i + 1) % 2, color, seed + 100 + i, 0.55)
		i += 1

static func _rock(image: Image, config, seed: int) -> void:
	var palette = _palette(config.palette, 4)
	image.fill(palette[1])
	var plates = [[6,5,7,5],[18,5,7,5],[28,8,5,6],[8,16,7,6],[20,16,7,6],[29,22,5,5],[5,27,6,4],[16,27,7,4],[26,29,5,3]]
	var i = 0
	while i < plates.size():
		var q = plates[i]
		var x = int(q[0])
		var y = int(q[1])
		var width = int(q[2])
		var height = int(q[3])
		_blob(image, x + 1, y + 1, width, height, palette[0], seed + 201 + i * 17, 0.52)
		var face_color = palette[1]
		if i % 3 == 0:
			face_color = palette[2]
		_blob(image, x, y, max(2, width - 1), max(2, height - 1), face_color, seed + 241 + i * 17, 0.66)
		if i % 2 == 0:
			_blob(image, x - 2, y - 2, 2, 1, palette[3], seed + 281 + i * 17, 0.45)
		i += 1
	i = 0
	while i < 6:
		_crack(image, 2 + int(_hash(i, 301, seed) * 27.0), 3 + int(_hash(i, 331, seed) * 25.0), 2 + i % 3, 1 if i % 2 == 0 else -1, palette[0], seed + 351 + i)
		i += 1

static func _sand(image: Image, config, seed: int) -> void:
	var palette = _palette(config.palette, 4)
	image.fill(palette[1])
	var i = 0
	while i < 13:
		var x = 2 + int(_hash(i, 841, seed) * 28.0)
		var y = 2 + int(_hash(i, 859, seed) * 28.0)
		var color = palette[2]
		if i % 4 == 0:
			color = palette[0]
		_blob(image, x, y, 2 + i % 2, 1 + i % 2, color, seed + 877 + i, 0.56)
		i += 1
	i = 0
	while i < 7:
		image.set_pixel(1 + int(_hash(i, 901, seed) * 30.0), 1 + int(_hash(i, 919, seed) * 30.0), palette[3])
		i += 1

static func _bark(image: Image, config, seed: int) -> void:
	var palette = _palette(config.palette, 4)
	image.fill(palette[1])
	var band = 0
	while band < 7:
		var x0 = band * 5 + int(_hash(band, 401, seed) * 3.0) - 1
		var y = 0
		while y < SIZE:
			var x = x0 + int(round(sin(y * 0.24 + band * 1.7 + _hash(band, 407, seed) * 5.0)))
			if x >= 0 and x < SIZE:
				image.set_pixel(x, y, palette[0])
				if x + 1 < SIZE:
					image.set_pixel(x + 1, y, palette[2])
				if y % 7 == 0 and x + 2 < SIZE:
					image.set_pixel(x + 2, y, palette[3])
			y += 1
		band += 1
	var i = 0
	while i < 5:
		_blob(image, 3 + int(_hash(i, 451, seed) * 26.0), 4 + int(_hash(i, 463, seed) * 24.0), 2, 3, palette[0], seed + 471 + i, 0.65)
		i += 1

static func _wood_end(image: Image, config, seed: int) -> void:
	var palette = _palette(config.palette, 4)
	image.fill(palette[1])
	var y = 0
	while y < SIZE:
		var x = 0
		while x < SIZE:
			var dx = x - 16
			var dy = y - 16
			var radius = sqrt(float(dx * dx + dy * dy))
			var ring = int(radius / 2.7) % 3
			var color = palette[1]
			if ring == 0:
				color = palette[0]
			elif ring == 1:
				color = palette[2]
			image.set_pixel(x, y, color)
			x += 1
		y += 1
	var i = 0
	while i < 5:
		_blob(image, 6 + int(_hash(i, 503, seed) * 20.0), 6 + int(_hash(i, 521, seed) * 20.0), 2, 1, palette[3], seed + 541 + i, 0.5)
		i += 1

static func _foliage(image: Image, config, seed: int) -> void:
	var palette = _palette(config.palette, 4)
	image.fill(palette[1])
	_blob(image, 7, 8, 7, 6, palette[0], seed + 601, 0.58)
	_blob(image, 20, 7, 8, 7, palette[2], seed + 619, 0.62)
	_blob(image, 12, 21, 8, 7, palette[2], seed + 633, 0.60)
	_blob(image, 27, 24, 6, 5, palette[0], seed + 651, 0.62)
	var i = 0
	while i < 8:
		var color = palette[0]
		if i % 3 == 0:
			color = palette[3]
		_blob(image, 2 + int(_hash(i, 671, seed) * 28.0), 2 + int(_hash(i, 683, seed) * 28.0), 1 + i % 2, 2, color, seed + 701 + i, 0.52)
		i += 1

static func _grass_side(image: Image, config, seed: int) -> void:
	var soil = _palette(config.palette, 4)
	var grass = _palette(config.secondary_palette, 4)
	image.fill(soil[1])
	var y = 0
	while y < SIZE:
		var boundary = 9 + int(_hash(y, 739, seed) * 5.0)
		if y < boundary:
			var x = 0
			while x < SIZE:
				var color = grass[1]
				if _hash(x, y, seed + 751) < 0.25:
					color = grass[0]
				elif _hash(x, y, seed + 761) > 0.84:
					color = grass[2]
				image.set_pixel(x, y, color)
				x += 1
		elif y == boundary:
			var x = 0
			while x < SIZE:
				if _hash(x, y, seed + 771) > 0.30:
					image.set_pixel(x, y, grass[0])
				x += 1
		y += 1
	_blob(image, 6, 19, 6, 5, soil[0], seed + 781, 0.62)
	_blob(image, 21, 23, 7, 5, soil[2], seed + 797, 0.68)
	var i = 0
	while i < 6:
		var color = soil[0]
		if i % 3 == 0:
			color = soil[3]
		_blob(image, 3 + int(_hash(i, 811, seed) * 26.0), 13 + int(_hash(i, 827, seed) * 17.0), 1 + i % 2, 1, color, seed + 839 + i, 0.5)
		i += 1

static func _ore(image: Image, config, seed: int) -> void:
	_rock(image, config, seed)
	var ore = _palette(config.accent_palette, 3)
	var id = 0
	while id < max(1, config.vein_count):
		var stream_seed = seed + 809 + id * 104729
		var x = 3 + int(_hash(id, 17, stream_seed) * 26.0)
		var y = 3 + int(_hash(id, 53, stream_seed + 97) * 26.0)
		var angle = _hash(id, 89, stream_seed + 193) * TAU
		var length = 6 + int(_hash(id, 107, stream_seed + 233) * 6.0)
		var step = 0
		while step < length:
			angle += (_hash(step, id, stream_seed + 313) - 0.5) * 0.7
			x += int(round(cos(angle)))
			y += int(round(sin(angle)))
			_stamp_vein(image, x, y, max(config.vein_width, 1), ore, stream_seed + step * 17)
			if step > 2 and _hash(step, id, stream_seed + 617) < config.vein_density:
				var branch = angle + (PI * 0.5 if _hash(step, id, stream_seed + 911) > 0.5 else -PI * 0.5)
				var b = 2
				while b < 5:
					_stamp_vein(image, x + int(round(cos(branch) * b)), y + int(round(sin(branch) * b)), max(config.vein_width - 1, 1), ore, stream_seed + b * 31)
					b += 1
			step += 1
		id += 1

static func _generic(image: Image, config, seed: int) -> void:
	var palette = _palette(config.palette, 3)
	image.fill(palette[1])
	var i = 0
	while i < 9:
		_blob(image, 2 + int(_hash(i, 901, seed) * 28.0), 2 + int(_hash(i, 919, seed) * 28.0), 1 + i % 3, 1 + (i + 1) % 2, palette[i % palette.size()], seed + 937 + i, 0.6)
		i += 1

static func _stamp_vein(image: Image, cx: int, cy: int, width: int, palette: Array, seed: int) -> void:
	var oy = -width
	while oy <= width:
		var ox = -width
		while ox <= width:
			var x = cx + ox
			var y = cy + oy
			if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
				var distance = abs(ox) + abs(oy)
				var keep = 1.0
				if distance == 1:
					keep = 0.78
				elif distance > 1:
					keep = 0.35
				if _hash(x, y, seed) < keep:
					image.set_pixel(x, y, palette[int(_hash(x + 7, y - 13, seed + 4243) * palette.size())])
			ox += 1
		oy += 1

static func _blob(image: Image, cx: int, cy: int, rx: int, ry: int, color: Color, seed: int, edge_keep: float) -> void:
	rx = max(rx, 1)
	ry = max(ry, 1)
	var row = -ry
	while row <= ry:
		var span = max(1, int(round(float(rx) * (1.0 - abs(float(row) / ry) * 0.55))))
		var offset = int(_hash(row + 101, cy + 103, seed) * 3.0) - 1
		var column = -span
		while column <= span:
			var x = cx + column + offset
			var y = cy + row
			if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
				if abs(float(column) / span) <= 0.70 or _hash(x, y, seed + 17) <= edge_keep:
					image.set_pixel(x, y, color)
			column += 1
		row += 1

static func _crack(image: Image, x: int, y: int, length: int, direction: int, color: Color, seed: int) -> void:
	var cx = x
	var cy = y
	var step = 0
	while step < length:
		if cx >= 0 and cx < SIZE and cy >= 0 and cy < SIZE:
			image.set_pixel(cx, cy, color)
		cx += 1
		if _hash(step, y, seed) > 0.55:
			cy += direction
		step += 1

static func _palette(source: Array, count: int) -> Array:
	var result = []
	var i = 0
	while i < min(count, source.size()):
		result.append(source[i])
		i += 1
	if result.is_empty():
		result.append(Color(1, 0, 1, 1))
	return result

static func _face_offset(face: String) -> int:
	if face == "top":
		return 1009
	if face == "bottom":
		return 2017
	return 3011

static func _hash(x: int, y: int, seed: int) -> float:
	var value: int = x * 374761393 + y * 668265263 + seed * 1442695041
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0x7fffffff) / 2147483647.0
