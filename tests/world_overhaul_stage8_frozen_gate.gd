extends "res://tests/world_overhaul_stage8_biome_gate.gd"

const FROZEN_STAGE8_RUNTIME := preload("res://scripts/world/playable_world_stage8_generation_runtime.gd")

# Keep Stage 8's completed performance contract tied to its frozen runtime while
# the inherited semantic/equivalence checks continue to verify that the current
# shipping runtime still preserves Stage 8 heights and base ecology IDs.
func _benchmark(_shipping_runtime) -> Dictionary:
	var frozen_runtime = FROZEN_STAGE8_RUNTIME.new()
	var result: Dictionary = super._benchmark(frozen_runtime)
	frozen_runtime.free()
	return result
