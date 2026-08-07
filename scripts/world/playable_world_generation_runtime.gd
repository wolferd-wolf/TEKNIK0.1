extends "res://scripts/world/playable_world_stage3_generation_runtime.gd"

const STAGE3_RUNTIME_BASE := preload("res://scripts/world/playable_world_stage3_generation_runtime.gd")

# Stable public runtime path. Stage 2's compatibility contract remains present
# through the inherited `_stage2_build_column_caches_for_sampler` entry point,
# while Stage 3's shipping cache still calls
# `sampler.build_provisional_terrain(terrain_fields)` after warped-structure
# lattice interpolation.
#
# WorkerThreadPool resolves static callables against get_script(), which is this
# public compatibility wrapper on the shipping instance. Forward the Stage 3
# worker explicitly so threaded chunk results cannot disappear at the wrapper
# boundary.
static func _stage3_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	STAGE3_RUNTIME_BASE._stage3_worker_build_chunk(
		coord,
		overrides_snapshot,
		revision,
		result_sink,
		result_mutex,
		result_key
	)
