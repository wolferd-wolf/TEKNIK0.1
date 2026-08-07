extends "res://scripts/world/playable_world_stage6_cache_aware_data.gd"

# Final Stage 6 shipping data layer. It keeps the cache-aware candidate reuse
# and also makes the historical biome/grid tree helper respect explicit water
# topology. Public/static queries and the threaded runtime therefore share the
# same lake/pond/river/ocean-aware tree-origin rule.
func is_tree_origin_for_biome(
	x: int,
	z: int,
	surface: int,
	biome: int
) -> bool:
	if water_type_at(x, z) != WATER_NONE:
		return false
	return super.is_tree_origin_for_biome(x, z, surface, biome)
