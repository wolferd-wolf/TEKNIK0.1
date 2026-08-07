extends "res://tests/multi_noise_step1_gate.gd"

# The consolidated threaded streamer can temporarily retain completed chunks
# from the previous center while a distant fixture becomes ready. The modern
# acceptance contract therefore requires at least the expected active set,
# collision-ring readiness, and an idle remesh queue instead of exact equality.
func _wait_for_world(manager: Variant, label: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_TIMEOUT_MSEC:
		if (
			manager.chunk_count() >= manager.expected_chunk_count()
			and manager.is_playable_world_collision_ring_ready()
			and manager.is_remesh_idle()
		):
			return true
		await process_frame
	_fail("Timed out waiting for %s" % label)
	return false
