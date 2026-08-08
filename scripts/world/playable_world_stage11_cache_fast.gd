extends RefCounted

const STAGE10_CACHE := preload("res://scripts/world/playable_world_stage10_cache_fast.gd")


static func build_transition_codes(cache: Dictionary, sampler) -> PackedByteArray:
	return STAGE10_CACHE.build_transition_codes(cache, sampler)


static func build_hydrology_codes(cache: Dictionary, sampler) -> PackedByteArray:
	var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
	var count: int = water_types.size()
	var codes := PackedByteArray()
	codes.resize(count)
	if count == 0:
		return codes
	var width: int = roundi(sqrt(float(count)))
	if width * width != count or width < 3:
		return codes

	var water_none: int = sampler.WATER_NONE
	var water_ocean: int = sampler.WATER_OCEAN
	var water_river: int = sampler.WATER_RIVER
	var water_lake: int = sampler.WATER_LAKE
	var water_pond: int = sampler.WATER_POND
	var hydro_none: int = sampler.HYDROLOGY_MODIFIER_NONE
	var hydro_coast: int = sampler.HYDROLOGY_MODIFIER_COAST
	var hydro_river: int = sampler.HYDROLOGY_MODIFIER_RIVERBANK
	var hydro_lake: int = sampler.HYDROLOGY_MODIFIER_LAKESIDE
	var hydro_pond: int = sampler.HYDROLOGY_MODIFIER_PONDSIDE

	# One-cell margin is deliberate: it is wide enough to read beside the existing
	# multi-block water bodies and exactly supported by Stage 10's padded cache for
	# every column the mesher needs, including the one-block tree-origin halo.
	for z in range(1, width - 1):
		var row: int = z * width
		for x in range(1, width - 1):
			var index: int = row + x
			if int(water_types[index]) != water_none:
				codes[index] = hydro_none
				continue

			var best_code: int = hydro_none
			var best_priority: int = 0
			for dz in range(-1, 2):
				var neighbor_row: int = (z + dz) * width
				for dx in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					var water_type: int = int(water_types[neighbor_row + x + dx])
					var code: int = hydro_none
					var priority: int = 0
					if water_type == water_river:
						code = hydro_river
						priority = 4
					elif water_type == water_lake:
						code = hydro_lake
						priority = 3
					elif water_type == water_pond:
						code = hydro_pond
						priority = 2
					elif water_type == water_ocean:
						code = hydro_coast
						priority = 1
					if priority > best_priority:
						best_priority = priority
						best_code = code
			codes[index] = best_code
	return codes
