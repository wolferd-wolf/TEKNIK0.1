extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage10_region_data.gd")
const SAMPLE_MIN := -128
const SAMPLE_MAX := 128
const MAX_TREE_PARTNER_RATE := 0.15
const MIN_GROUND_PARTNER_RATE := 0.45
const MAX_GROUND_PARTNER_RATE := 0.55


func _init() -> void:
	var data = DATA.new()
	var code: int = data.stage10_pack_transition(
		DATA.BIOME_FOREST,
		DATA.STAGE10_TRANSITION_LEVELS
	)
	var total := 0
	var tree_partner_uses := 0
	var ground_partner_uses := 0
	for z in range(SAMPLE_MIN, SAMPLE_MAX):
		for x in range(SAMPLE_MIN, SAMPLE_MAX):
			total += 1
			if data.stage10_uses_partner(x, z, code, DATA.STAGE10_TREE_BLEND_SALT):
				tree_partner_uses += 1
			if data.stage10_uses_partner(x, z, code, DATA.STAGE10_GROUND_BLEND_SALT):
				ground_partner_uses += 1

	var tree_rate := float(tree_partner_uses) / float(total)
	var ground_rate := float(ground_partner_uses) / float(total)
	print("PLAINS_TRANSITION_TREE_BLEED tree_partner_rate=%.6f ground_partner_rate=%.6f samples=%d max_tree_rate=%.6f" % [
		tree_rate,
		ground_rate,
		total,
		MAX_TREE_PARTNER_RATE,
	])

	if tree_rate > MAX_TREE_PARTNER_RATE:
		push_error("Plains/Forest max-strength transition leaks too much partner tree eligibility: %.6f" % tree_rate)
		quit(1)
		return
	if ground_rate < MIN_GROUND_PARTNER_RATE or ground_rate > MAX_GROUND_PARTNER_RATE:
		push_error("Ground ecotone no longer preserves the accepted near-50/50 boundary expression: %.6f" % ground_rate)
		quit(1)
		return
	print("PLAINS_TRANSITION_TREE_BLEED_PASS")
	quit(0)
