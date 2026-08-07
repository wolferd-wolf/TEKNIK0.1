extends "res://scripts/world/playable_world_stage6_generation_data.gd"

# Shipping-only Stage 6 lookup optimization. The accepted Stage 6 topology stays
# in playable_world_stage6_generation_data.gd; this subclass preserves that
# exact behavior while avoiding full lake-candidate evaluation for lake cells
# that are geometrically incapable of overlapping a pond.

func _stage6_pond_overlaps_lake(
	center: Vector2i,
	radius_x: float,
	radius_z: float
) -> bool:
	var lake_cell_x := floori(float(center.x) * STAGE6_LAKE_CELL_RECIPROCAL)
	var lake_cell_z := floori(float(center.y) * STAGE6_LAKE_CELL_RECIPROCAL)
	var pond_radius := maxf(radius_x, radius_z)
	var maximum_separation := (
		pond_radius
		+ STAGE6_LAKE_RADIUS_MAX
		+ STAGE6_FEATURE_SEPARATION_MARGIN
	)
	var maximum_separation_squared := maximum_separation * maximum_separation
	for offset_z in range(-1, 2):
		for offset_x in range(-1, 2):
			var candidate_cell_x := lake_cell_x + offset_x
			var candidate_cell_z := lake_cell_z + offset_z
			var candidate_center := _stage6_candidate_center(
				candidate_cell_x,
				candidate_cell_z,
				STAGE6_LAKE_CELL_SPACING,
				STAGE6_LAKE_CELL_HALF,
				STAGE6_LAKE_JITTER,
				STAGE6_LAKE_SALT_X,
				STAGE6_LAKE_SALT_Z
			)
			var coarse_dx := float(center.x - candidate_center.x)
			var coarse_dz := float(center.y - candidate_center.y)
			if coarse_dx * coarse_dx + coarse_dz * coarse_dz >= maximum_separation_squared:
				continue
			var lake := stage6_lake_candidate(candidate_cell_x, candidate_cell_z)
			if lake.is_empty():
				continue
			var dx := float(center.x - int(lake["center_x"]))
			var dz := float(center.y - int(lake["center_z"]))
			var lake_radius := maxf(float(lake["radius_x"]), float(lake["radius_z"]))
			var separation := pond_radius + lake_radius + STAGE6_FEATURE_SEPARATION_MARGIN
			if dx * dx + dz * dz < separation * separation:
				return true
	return false
