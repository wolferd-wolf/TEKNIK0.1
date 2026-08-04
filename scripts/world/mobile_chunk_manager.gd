extends "res://scripts/world/chunk_manager.gd"
class_name MobileChunkManager

const MOBILE_REMESH_APPLIES_PER_PHYSICS_FRAME := 1
const MOBILE_SHADOW_DISTANCE := 48.0

@export_range(1, 2, 1) var mobile_render_radius: int = 1
@export var force_mobile_profile: bool = false

var _mobile_profile_active: bool = false


func _ready() -> void:
	_mobile_profile_active = (
		force_mobile_profile
		or OS.has_feature("android")
		or OS.has_feature("mobile")
	)
	if _mobile_profile_active:
		render_radius = mini(render_radius, mobile_render_radius)
	_apply_mobile_render_profile()
	super._ready()


func _physics_process(delta: float) -> void:
	if not _mobile_profile_active:
		super._physics_process(delta)
		return

	var started_usec := Time.get_ticks_usec()
	_collect_completed_remesh_tasks()
	_apply_completed_remeshes(MOBILE_REMESH_APPLIES_PER_PHYSICS_FRAME)
	_max_remesh_pump_usec = maxi(
		_max_remesh_pump_usec,
		Time.get_ticks_usec() - started_usec
	)


func is_mobile_profile_active() -> bool:
	return _mobile_profile_active


func get_mobile_profile_diagnostics() -> Dictionary:
	return {
		"active": _mobile_profile_active,
		"render_radius": render_radius,
		"expected_chunk_count": expected_chunk_count(),
		"remesh_applies_per_physics_frame": (
			MOBILE_REMESH_APPLIES_PER_PHYSICS_FRAME
			if _mobile_profile_active
			else MAX_REMESH_APPLIES_PER_PHYSICS_FRAME
		),
	}


func _apply_mobile_render_profile() -> void:
	if not _mobile_profile_active:
		return
	var main_root := get_parent()
	if main_root == null:
		return
	var sun := main_root.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.directional_shadow_max_distance = minf(
			sun.directional_shadow_max_distance,
			MOBILE_SHADOW_DISTANCE
		)
		sun.directional_shadow_fade_start = minf(
			sun.directional_shadow_fade_start,
			0.7
		)
