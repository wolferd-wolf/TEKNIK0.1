extends RefCounted

# Non-shipping prototype only.
# Structural reference: Luanti 5.16.1 Carpathian mapgen.
# This keeps Carpathian's published default scales/seed offsets and terrain
# equations, while using Godot FastNoiseLite for native-speed sampling.
# The exact C++ reference harness in tools/reference/ is the behavioral oracle.

const BASE_LEVEL := 12.0
const WATER_LEVEL := 1
const REFERENCE_Y_MAX := 255
const TEKNIK_SAFE_TOP := 138

class NoiseLayer:
	var noise := FastNoiseLite.new()
	var offset := 0.0
	var scale := 1.0
	var amplitude_sum := 1.0

	func sample_2d(x: float, z: float) -> float:
		return offset + noise.get_noise_2d(x, z) * scale * amplitude_sum

	func sample_3d(x: float, y: float, z: float) -> float:
		return offset + noise.get_noise_3d(x, y, z) * scale * amplitude_sum

var world_seed := 734921
var height1: NoiseLayer
var height2: NoiseLayer
var height3: NoiseLayer
var height4: NoiseLayer
var hills_terrain: NoiseLayer
var ridge_terrain: NoiseLayer
var step_terrain: NoiseLayer
var hills: NoiseLayer
var ridge_mnt: NoiseLayer
var step_mnt: NoiseLayer
var mnt_var: NoiseLayer


func _init(seed_value: int = 734921) -> void:
	world_seed = seed_value
	height1 = _make_layer(0.0, 5.0, 251.0, 9613, 5, 0.50, 2.0)
	height2 = _make_layer(0.0, 5.0, 383.0, 1949, 5, 0.50, 2.0)
	height3 = _make_layer(0.0, 5.0, 509.0, 3211, 5, 0.50, 2.0)
	height4 = _make_layer(0.0, 5.0, 631.0, 1583, 5, 0.50, 2.0)
	hills_terrain = _make_layer(1.0, 1.0, 1301.0, 1692, 5, 0.50, 2.0)
	ridge_terrain = _make_layer(1.0, 1.0, 1889.0, 3568, 5, 0.50, 2.0)
	step_terrain = _make_layer(1.0, 1.0, 1889.0, 4157, 5, 0.50, 2.0)
	hills = _make_layer(0.0, 3.0, 257.0, 6604, 6, 0.50, 2.0)
	ridge_mnt = _make_layer(0.0, 12.0, 743.0, 5520, 6, 0.70, 2.0)
	step_mnt = _make_layer(0.0, 8.0, 509.0, 2590, 6, 0.60, 2.0)
	mnt_var = _make_layer(0.0, 1.0, 499.0, 2490, 5, 0.55, 2.0)


func _make_layer(
	offset_value: float,
	scale_value: float,
	spread: float,
	seed_offset: int,
	octaves: int,
	gain: float,
	lacunarity: float
) -> NoiseLayer:
	var layer := NoiseLayer.new()
	layer.offset = offset_value
	layer.scale = scale_value
	var n := layer.noise
	n.seed = world_seed + seed_offset
	# Luanti's source is scalar lattice/value noise with smooth interpolation.
	# TYPE_VALUE is the closest native FastNoiseLite primitive in Godot 4.3.
	n.noise_type = FastNoiseLite.TYPE_VALUE
	n.frequency = 1.0 / spread
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	n.fractal_lacunarity = lacunarity
	var weight := 1.0
	var total := 0.0
	for _i in range(octaves):
		total += weight
		weight *= gain
	# FastNoiseLite normalizes fBm; Luanti's NoiseFractal* sums amplitudes.
	# Undo the normalization approximately so the published Carpathian scales
	# retain their intended magnitude.
	layer.amplitude_sum = total
	return layer


func _steps(value: float) -> float:
	const width := 0.5
	var k: float = floor(value / width)
	var f: float = (value - k * width) / width
	var s := minf(2.0 * f, 1.0)
	return (k + s) * width


func _sample_static_terms(x: int, z: int) -> PackedFloat32Array:
	var xf := float(x)
	var zf := float(z)
	var h1 := height1.sample_2d(xf, zf)
	var h2 := height2.sample_2d(xf, zf)
	var h3 := height3.sample_2d(xf, zf)
	var h4 := height4.sample_2d(xf, zf)
	var hter := absf(hills_terrain.sample_2d(xf, zf))
	var nhills := hills.sample_2d(xf, zf)
	var hill_mask := hter * hter * hter * nhills * nhills
	var rter := absf(ridge_terrain.sample_2d(xf, zf))
	var nridge := ridge_mnt.sample_2d(xf, zf)
	var ridge_mask := rter * rter * rter * (1.0 - absf(nridge))
	var ster := absf(step_terrain.sample_2d(xf, zf))
	var nstep := step_mnt.sample_2d(xf, zf)
	var step_mask := ster * ster * ster * _steps(nstep)
	return PackedFloat32Array([h1, h2, h3, h4, hill_mask, ridge_mask, step_mask])


func _mountain_terms_at_y(x: int, z: int, y: int, terms: PackedFloat32Array) -> Vector4:
	var variation := mnt_var.sample_3d(float(x), float(y), float(z))
	var hill1 := lerpf(terms[0], terms[1], variation)
	var hill2 := lerpf(terms[2], terms[3], variation)
	var hill3 := lerpf(terms[2], terms[1], variation)
	var hill4 := lerpf(terms[0], terms[3], variation)
	var hilliness := maxf(minf(hill1, hill2), minf(hill3, hill4))
	var hill_value := terms[4] * hilliness
	var ridge_value := terms[5] * hilliness
	var step_value := terms[6] * hilliness
	return Vector4(hill_value, ridge_value, step_value, hill_value + ridge_value + step_value)


func _is_solid_at_y(x: int, z: int, y: int, terms: PackedFloat32Array) -> bool:
	var mountain := _mountain_terms_at_y(x, z, y, terms).w
	var gradient := (
		float(1 - WATER_LEVEL) + float(WATER_LEVEL - y) * 3.0
		if y < WATER_LEVEL
		else 1.0 - float(y)
	)
	var surface_level := BASE_LEVEL + mountain + gradient
	return float(y) < surface_level


func surface_height_raw(x: int, z: int) -> int:
	var terms := _sample_static_terms(x, z)
	# For y >= water level, the Carpathian solid test is approximately a fixed
	# point around y=(BASE_LEVEL+mountain(y)+1)/2. Iterate to that neighborhood,
	# then scan a bounded window for the exact highest solid in that neighborhood.
	var candidate := 6
	for _i in range(7):
		var mountain := _mountain_terms_at_y(x, z, candidate, terms).w
		var threshold := (BASE_LEVEL + mountain + 1.0) * 0.5
		candidate = clampi(ceili(threshold) - 1, 0, REFERENCE_Y_MAX)
	var scan_min := maxi(0, candidate - 16)
	var scan_max := mini(REFERENCE_Y_MAX, candidate + 16)
	var best := 0
	for y in range(scan_min, scan_max + 1):
		if _is_solid_at_y(x, z, y, terms):
			best = y
	return best


func surface_height_teknik(x: int, z: int) -> int:
	return clampi(surface_height_raw(x, z), 3, TEKNIK_SAFE_TOP)


func mountain_contribution_at_surface(x: int, z: int) -> float:
	var terms := _sample_static_terms(x, z)
	var y := surface_height_raw(x, z)
	return _mountain_terms_at_y(x, z, y, terms).w
