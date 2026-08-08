extends RefCounted

const STAGE11_CACHE := preload("res://scripts/world/playable_world_stage11_cache_fast.gd")


static func build_transition_codes(cache: Dictionary, sampler) -> PackedByteArray:
	# Stage 12 does not change climate-region math. Reuse the exact accepted
	# Stage 10/11 transition preparation so output remains byte-identical.
	return STAGE11_CACHE.build_transition_codes(cache, sampler)


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
	var hydro_coast: int = sampler.HYDROLOGY_MODIFIER_COAST
	var hydro_river: int = sampler.HYDROLOGY_MODIFIER_RIVERBANK
	var hydro_lake: int = sampler.HYDROLOGY_MODIFIER_LAKESIDE
	var hydro_pond: int = sampler.HYDROLOGY_MODIFIER_PONDSIDE

	# Exact Stage 11 one-cell neighborhood and priority, expressed as eight fixed
	# packed-array reads rather than two interpreted nested loops plus per-neighbor
	# code/priority bookkeeping. Priority remains river > lake > pond > ocean.
	for z in range(1, width - 1):
		var row: int = z * width
		for x in range(1, width - 1):
			var index: int = row + x
			if int(water_types[index]) != water_none:
				continue

			var nw: int = int(water_types[index - width - 1])
			var n: int = int(water_types[index - width])
			var ne: int = int(water_types[index - width + 1])
			var w: int = int(water_types[index - 1])
			var e: int = int(water_types[index + 1])
			var sw: int = int(water_types[index + width - 1])
			var s: int = int(water_types[index + width])
			var se: int = int(water_types[index + width + 1])

			if (
				nw == water_river or n == water_river or ne == water_river
				or w == water_river or e == water_river
				or sw == water_river or s == water_river or se == water_river
			):
				codes[index] = hydro_river
			elif (
				nw == water_lake or n == water_lake or ne == water_lake
				or w == water_lake or e == water_lake
				or sw == water_lake or s == water_lake or se == water_lake
			):
				codes[index] = hydro_lake
			elif (
				nw == water_pond or n == water_pond or ne == water_pond
				or w == water_pond or e == water_pond
				or sw == water_pond or s == water_pond or se == water_pond
			):
				codes[index] = hydro_pond
			elif (
				nw == water_ocean or n == water_ocean or ne == water_ocean
				or w == water_ocean or e == water_ocean
				or sw == water_ocean or s == water_ocean or se == water_ocean
			):
				codes[index] = hydro_coast
	return codes


static func build_expression_codes(cache: Dictionary, sampler) -> Dictionary:
	return {
		"transition_codes": build_transition_codes(cache, sampler),
		"hydrology_codes": build_hydrology_codes(cache, sampler),
	}
