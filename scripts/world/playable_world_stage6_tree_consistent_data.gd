extends "res://scripts/world/playable_world_stage6_optimized_data.gd"

# Stage 6 tree-origin consistency layer. The historical biome/grid helper knew
# only climate/surface context; Stage 5/6 added explicit water topology later.
# Any caller of the helper on the shipping generator must therefore reject wet
# columns before applying the unchanged accepted tree-grid/hash rule.
func is_tree_origin_for_biome(
	x: int,
	z: int,
	surface: int,
	biome: int
) -> bool:
	if water_type_at(x, z) != WATER_NONE:
		return false
	return super.is_tree_origin_for_biome(x, z, surface, biome)
