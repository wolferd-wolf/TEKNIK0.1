class_name CaveFieldReference
extends RefCounted

## Deterministic cave-field contract (build plan step 8).
## Pure functions of (seed, world coordinates). i64/f64 semantics only.
## This GDScript implementation is the behavioral reference. The Rust port in
## native/rust_fields/src/lib.rs must match it bit-for-bit (verified live by
## tests/cave_field_parity_gate.gd with exact double equality).
##
## All integer arithmetic wraps at 64 bits; shifts are arithmetic; the hash
## fraction uses exactly 53 mantissa bits so values land in [0, 1).

const CAVE_C1 := -7046029254386353131
const CAVE_C2 := -4417276556811493921
const CAVE_C3 := 5504942323413186691
const CAVE_C4 := -6321507891823812219
const CAVE_C5 := 6321507891823812219

const TUNNEL_SEED_A := 1372009017
const TUNNEL_SEED_B := 729942611
const CHEESE_SEED := 2048153539
const ENTRANCE_SEED := 491651065

const TUNNEL_SCALE := 1.0 / 28.0
const CHEESE_SCALE := 1.0 / 48.0
const ENTRANCE_SCALE := 1.0 / 16.0
const TUNNEL_BAND := 0.058
const CHEESE_THRESHOLD := 0.72
const ENTRANCE_THRESHOLD := 0.78
const FBM_GAIN := 0.5
const FBM_LACUNARITY := 2.0


static func hash01_3d(x: int, y: int, z: int, seed: int) -> float:
	var h: int = seed
	h = h ^ (x * CAVE_C1)
	h = h ^ (y * CAVE_C2)
	h = h ^ (z * CAVE_C3)
	h = (h ^ (h >> 30)) * CAVE_C4
	h = (h ^ (h >> 27)) * CAVE_C5
	h = h ^ (h >> 31)
	return float((h >> 11) & 0x1FFFFFFFFFFFFF) * (1.0 / 9007199254740992.0)


static func value_noise_3d(fx: float, fy: float, fz: float, seed: int) -> float:
	var ix := floori(fx)
	var iy := floori(fy)
	var iz := floori(fz)
	var tx := fx - float(ix)
	var ty := fy - float(iy)
	var tz := fz - float(iz)
	var sx := tx * tx * (3.0 - 2.0 * tx)
	var sy := ty * ty * (3.0 - 2.0 * ty)
	var sz := tz * tz * (3.0 - 2.0 * tz)
	var c000 := hash01_3d(ix, iy, iz, seed)
	var c100 := hash01_3d(ix + 1, iy, iz, seed)
	var c001 := hash01_3d(ix, iy, iz + 1, seed)
	var c101 := hash01_3d(ix + 1, iy, iz + 1, seed)
	var c010 := hash01_3d(ix, iy + 1, iz, seed)
	var c110 := hash01_3d(ix + 1, iy + 1, iz, seed)
	var c011 := hash01_3d(ix, iy + 1, iz + 1, seed)
	var c111 := hash01_3d(ix + 1, iy + 1, iz + 1, seed)
	var n00 := c000 + (c100 - c000) * sx
	var n10 := c001 + (c101 - c001) * sx
	var n01 := c010 + (c110 - c010) * sx
	var n11 := c011 + (c111 - c011) * sx
	var n0 := n00 + (n10 - n00) * sy
	var n1 := n01 + (n11 - n01) * sy
	return n0 + (n1 - n0) * sz


static func fbm3(fx: float, fy: float, fz: float, seed: int, octaves: int, scale: float) -> float:
	var total := 0.0
	var amp := 1.0
	var norm := 0.0
	var x := fx * scale
	var y := fy * scale
	var z := fz * scale
	for octave in range(octaves):
		total += value_noise_3d(x, y, z, seed + octave * 1013) * amp
		norm += amp
		amp *= FBM_GAIN
		x *= FBM_LACUNARITY
		y *= FBM_LACUNARITY
		z *= FBM_LACUNARITY
	if norm <= 0.0:
		return 0.5
	return total / norm


static func tunnel_a(wx: int, wy: int, wz: int) -> float:
	return fbm3(
		float(wx), float(wy), float(wz),
		TUNNEL_SEED_A, 2, TUNNEL_SCALE
	)


static func tunnel_b(wx: int, wy: int, wz: int) -> float:
	return fbm3(
		float(wx), float(wy), float(wz),
		TUNNEL_SEED_B, 2, TUNNEL_SCALE
	)


static func cheese_field(wx: int, wy: int, wz: int) -> float:
	return fbm3(
		float(wx), float(wy), float(wz),
		CHEESE_SEED, 3, CHEESE_SCALE
	)


static func entrance_value(wx: int, wy: int, wz: int) -> float:
	return value_noise_3d(
		float(wx) * ENTRANCE_SCALE, float(wy) * ENTRANCE_SCALE,
		float(wz) * ENTRANCE_SCALE, ENTRANCE_SEED
	)


static func is_cave_cell(
	wx: int,
	wy: int,
	wz: int,
	surface_y: int,
	sea_level: int,
	water_column: bool,
	min_y: int = 0
) -> bool:
	if wy < min_y + 2:
		return false
	if water_column and wy > surface_y - 8:
		return false
	var depth_below := surface_y - wy
	var entrance_ok := false
	if not water_column and surface_y > sea_level + 3:
		entrance_ok = entrance_value(wx, wy, wz) > ENTRANCE_THRESHOLD
	if depth_below < 4 and not entrance_ok:
		return false
	var ta := tunnel_a(wx, wy, wz)
	var tb := tunnel_b(wx, wy, wz)
	if absf(ta - 0.5) < TUNNEL_BAND and absf(tb - 0.5) < TUNNEL_BAND:
		return true
	if depth_below >= 12 and cheese_field(wx, wy, wz) > CHEESE_THRESHOLD:
		return true
	return false
