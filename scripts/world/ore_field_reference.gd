class_name OreFieldReference
extends RefCounted

## Deterministic depth-weighted ore placement (build plan step 14).
## Policy layer over the frozen hash primitive from CaveFieldReference.
## One owner: GDScript owns placement policy; the native side owns field math
## only, so no separate Rust port is required here. Placement runs after the
## cave carve decision: carved cells never receive ore.

const ORE_SEED_TYPE := 918273611
const ORE_SEED_FILL := 425771093

const ORE_VEIN_CELL_SHIFT := 1 # veins live on a 2x2x2 lattice
const ORE_RAGGEDNESS := 0.75   # fraction of vein-cube blocks actually filled

const ORE_WEIGHT_COAL_BASE := 0.010
const ORE_WEIGHT_COAL_DEPTH := 0.014 # extra coal at max practical depth
const ORE_WEIGHT_IRON_MAX := 0.012
const ORE_IRON_START_DEPTH := 10.0
const ORE_IRON_RAMP_DEPTH := 26.0
const ORE_WEIGHT_COPPER_MAX := 0.010
const ORE_COPPER_PEAK_Y := 14.0
const ORE_COPPER_FALLOFF := 18.0


static func _clamp01(value: float) -> float:
	return clampf(value, 0.0, 1.0)


## Depth-weighted ore weights for one world column position.
static func ore_weights(x: int, y: int, z: int, height: int) -> Vector3:
	var depth := float(height - y)
	var coal := ORE_WEIGHT_COAL_BASE + ORE_WEIGHT_COAL_DEPTH * _clamp01(depth / 48.0)
	var iron := ORE_WEIGHT_IRON_MAX * _clamp01((depth - ORE_IRON_START_DEPTH) / ORE_IRON_RAMP_DEPTH)
	var copper := ORE_WEIGHT_COPPER_MAX * _clamp01(
		(ORE_COPPER_FALLOFF - absf(float(y) - ORE_COPPER_PEAK_Y)) / ORE_COPPER_FALLOFF
	)
	return Vector3(coal, iron, copper)


## Block id for one stone cell, or BLOCK_AIR (=0) when no ore replaces it.
static func ore_block_for_cell(x: int, y: int, z: int, height: int) -> int:
	var vx := x >> ORE_VEIN_CELL_SHIFT
	var vy := y >> ORE_VEIN_CELL_SHIFT
	var vz := z >> ORE_VEIN_CELL_SHIFT
	var weights := ore_weights(x, y, z, height)
	var total := weights.x + weights.y + weights.z
	if total <= 0.0:
		return 0
	var vein_roll := CaveFieldReference.hash01_3d(vx, vy, vz, ORE_SEED_TYPE)
	if vein_roll >= total:
		return 0
	var pick := vein_roll / total
	var ore_id := 10 # coal
	if pick >= (weights.x + weights.y) / total:
		ore_id = 12 # copper band sits above iron in the normalized window
	elif pick >= weights.x / total:
		ore_id = 11 # iron
	var fill := CaveFieldReference.hash01_3d(x, y, z, ORE_SEED_FILL)
	if fill >= ORE_RAGGEDNESS:
		return 0
	return ore_id
