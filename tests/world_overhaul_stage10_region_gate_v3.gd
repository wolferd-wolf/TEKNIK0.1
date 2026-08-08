extends "res://tests/world_overhaul_stage10_region_gate_v2.gd"

# Stage 10 v3 keeps every behavioral/performance assertion from v2 and replaces
# only the source-architecture assertion: shipping now starts from the accepted
# Stage 7 fused geography cache, then recreates Stage 8 ecology + Stage 9 terrain
# modifiers with an exact optimized decision tree. v2's byte-equivalence checks
# against frozen Stage 9 remain the authority for output preservation.
func _validate_contract() -> Dictionary:
	if DATA.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("Stage 10 lost the 150-block legal world height")
	if DATA.STAGE8_ACTIVE_BIOME_COUNT != 6:
		_fail("Stage 10 changed the six accepted Stage 8 ecology IDs")
	if DATA.STAGE9_TERRAIN_MODIFIER_COUNT != 5:
		_fail("Stage 10 changed the accepted Stage 9 terrain modifier contract")
	if DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY != 0.0012:
		_fail("Stage 10 changed the broad temperature field frequency")
	if DATA.BIOME_MOISTURE_NOISE_FREQUENCY != 0.0014:
		_fail("Stage 10 changed the broad moisture field frequency")
	if DATA.STAGE10_TRANSITION_SCORE_WIDTH <= 0.0:
		_fail("Stage 10 transition score width is not positive")

	var data_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage10_region_data.gd"
	)
	var cache_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/playable_world_stage10_cache_fast.gd"
	)
	if data_source.contains("FastNoiseLite.new") or cache_source.contains("FastNoiseLite.new"):
		_fail("Stage 10 added a new noise stack")
	if cache_source.contains("get_noise_2d"):
		_fail("Stage 10 resamples noise instead of reusing cached geography/climate fields")
	if not cache_source.contains("STAGE7_CACHE.build"):
		_fail("Stage 10 optimized cache no longer starts from the accepted fused Stage 7 geography cache")
	if not cache_source.contains("build_transition_codes"):
		_fail("Stage 10 no longer separates expression transition preparation")

	return {
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"base_ecology_count": DATA.STAGE8_ACTIVE_BIOME_COUNT,
		"terrain_modifier_count": DATA.STAGE9_TERRAIN_MODIFIER_COUNT,
		"temperature_frequency": DATA.BIOME_TEMPERATURE_NOISE_FREQUENCY,
		"moisture_frequency": DATA.BIOME_MOISTURE_NOISE_FREQUENCY,
		"transition_score_width": DATA.STAGE10_TRANSITION_SCORE_WIDTH,
		"transition_levels": DATA.STAGE10_TRANSITION_LEVELS,
		"generation_base": "Stage 7 fused geography; exact Stage 8/9 recreation",
		"transition_prep_phase": "post-cache mesh preparation",
	}
