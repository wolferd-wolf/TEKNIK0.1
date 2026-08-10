extends RefCounted
class_name TextureGenerator

const SIZE := 32
const REGISTRY = preload("res://resources/textures/texture_block_registry.tres")
static var _texture_cache: Dictionary = {}

static func generate(block_type: String, seed: int) -> ImageTexture:
	var key := "%s:%d" % [block_type, seed]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var config: TextureBlockConfig = REGISTRY.get_config(block_type)
	var image := _generate_image(config, seed)
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[key] = texture
	return texture

static func get_block_types() -> Array[String]:
	return REGISTRY.get_block_types()

static func _generate_image(config: TextureBlockConfig, seed: int) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if config == null:
		image.fill(Color.MAGENTA)
		return image
	for y in range(SIZE):
		for x in range(SIZE):
			var value := _cellular_value(x,y,config.frequency,seed+config.seed_offset) if config.noise_mode == "cellular" else _value_noise(x,y,config.frequency,seed+config.seed_offset)
			image.set_pixel(x,y,_palette_sample(config.palette,value))
	if config.overlay_mode == "speckle":
		for y in range(SIZE):
			for x in range(SIZE):
				if _hash_2d(x,y,seed+config.overlay_seed_offset) < config.overlay_density:
					var i := clampi(int(floor(_hash_2d(x+17,y-11,seed+271)*config.overlay_palette.size())),0,config.overlay_palette.size()-1)
					image.set_pixel(x,y,config.overlay_palette[i])
	return image

static func _palette_sample(palette: Array[Color], value: float) -> Color:
	if palette.is_empty(): return Color.WHITE
	return palette[clampi(int(floor(value*palette.size())),0,palette.size()-1)]

static func _value_noise(x:int,y:int,f:float,seed:int)->float:
	var fx=x*f; var fy=y*f; var x0=int(floor(fx)); var y0=int(floor(fy)); var tx=fx-x0; var ty=fy-y0
	tx=tx*tx*(3.0-2.0*tx); ty=ty*ty*(3.0-2.0*ty)
	return clampf(lerpf(lerpf(_hash_2d(x0,y0,seed),_hash_2d(x0+1,y0,seed),tx),lerpf(_hash_2d(x0,y0+1,seed),_hash_2d(x0+1,y0+1,seed),tx),ty),0.0,0.999999)

static func _cellular_value(x:int,y:int,f:float,seed:int)->float:
	var fx=x*f; var fy=y*f; var cx=int(floor(fx)); var cy=int(floor(fy)); var nearest=999.0
	for oy in range(-1,2):
		for ox in range(-1,2):
			var gx=cx+ox; var gy=cy+oy; var px=gx+_hash_2d(gx,gy,seed); var py=gy+_hash_2d(gx,gy,seed+7919); var dx=px-fx; var dy=py-fy
			nearest=minf(nearest,dx*dx+dy*dy)
	return 1.0-clampf(sqrt(nearest)/0.7071,0.0,1.0)

static func _hash_2d(x:int,y:int,seed:int)->float:
	var n:int=x*374761393+y*668265263+seed*1442695041
	n=(n^(n>>13))*1274126177; n=n^(n>>16)
	return float(n&0x7fffffff)/2147483647.0
