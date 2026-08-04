extends SceneTree

# Locks the mobile-friendly hard-edged directional shadow contract used by the main scene.
const MAIN_SCENE := preload("res://scenes/main.tscn")

func _initialize() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame

	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	_assert(sun != null, "Main scene must contain a DirectionalLight3D named Sun")
	_assert(sun.shadow_enabled, "Sun shadows must be enabled")
	_assert(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Sun must use four cascaded shadow splits")
	_assert(not sun.directional_shadow_blend_splits, "Split blending must remain disabled for crisp block-style transitions")
	_assert(sun.directional_shadow_max_distance <= 72.0, "Shadow distance must stay bounded for mobile resolution and stability")
	_assert(sun.directional_shadow_fade_start >= 0.85, "Shadows must retain contrast through most of the configured range")
	_assert(sun.shadow_blur <= 0.2, "Shadow blur must remain low for Minecraft-style hard edges")
	_assert(sun.shadow_bias >= 0.02 and sun.shadow_bias <= 0.06, "Shadow bias must stay in the acne-safe tuned range")
	_assert(sun.shadow_normal_bias >= 0.5 and sun.shadow_normal_bias <= 1.0, "Normal bias must stay in the tuned voxel-safe range")
	_assert(sun.directional_shadow_split_1 < sun.directional_shadow_split_2, "First cascade split must precede second")
	_assert(sun.directional_shadow_split_2 < sun.directional_shadow_split_3, "Second cascade split must precede third")

	print("POLISH_MINECRAFT_SHADOWS_GATE_PASS")
	main.queue_free()
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
