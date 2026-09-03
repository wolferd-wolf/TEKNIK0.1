extends Node

# Single source of truth for TEKNIK's save file: world seed, block edits,
# player position/look, and inventory contents.
#
# Registered as an autoload BEFORE WorldSeed in project.godot, so its save
# file is already read into memory by the time WorldSeed decides whether to
# randomize a new seed or reuse a saved one -- world generation must not
# start before that decision is made, or the seed and any restored block
# edits will mismatch (regenerated terrain won't match where old edits
# were made).
#
# File format (version 2):
# {
#   "version": 2,
#   "seed": int,
#   "overrides": { "x,y,z": block_id, ... },
#   "player": {
#     "position": [x, y, z],
#     "yaw": float,
#     "pitch": float,
#     "inventory": [ {"block_id": int, "count": int}, ... ],
#     "selected_slot": int
#   }
# }

const SAVE_PATH := "user://teknik_save.json"
const AUTOSAVE_INTERVAL_SEC := 8.0

var _cached_save: Dictionary = {}
var _loaded := false
var _autosave_elapsed := 0.0


func _ready() -> void:
	_load_from_disk()
	set_process(true)


func _process(delta: float) -> void:
	_autosave_elapsed += delta
	if _autosave_elapsed < AUTOSAVE_INTERVAL_SEC:
		return
	_autosave_elapsed = 0.0
	_autosave_from_live_state()


func _notification(what: int) -> void:
	# Android backgrounds an app (pause) rather than killing it outright, and
	# a paused app can be killed by the OS without further warning -- so a
	# save on _exit_tree()/shutdown() alone isn't enough on mobile.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_autosave_from_live_state()


func has_save() -> bool:
	return _loaded and not _cached_save.is_empty()


# Wipes the save file and cached state. Used by New Game so a fresh start
# doesn't inherit the old seed, block edits, position, or inventory --
# without this, WorldSeed and the world/player data would still read the
# stale save on their next lookup.
func clear_save() -> void:
	_cached_save = {}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func get_saved_seed() -> Variant:
	if not has_save() or not _cached_save.has("seed"):
		return null
	return int(_cached_save["seed"])


func get_saved_overrides() -> Dictionary:
	if not has_save():
		return {}
	var overrides: Variant = _cached_save.get("overrides", {})
	return overrides if overrides is Dictionary else {}


func get_saved_player_position() -> Variant:
	if not has_save():
		return null
	var player: Variant = _cached_save.get("player", {})
	if not (player is Dictionary) or not player.has("position"):
		return null
	var raw: Variant = player["position"]
	if raw is Array and raw.size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return null


func get_saved_player_look() -> Dictionary:
	if not has_save():
		return {}
	var player: Variant = _cached_save.get("player", {})
	if not (player is Dictionary):
		return {}
	return {"yaw": float(player.get("yaw", 0.0)), "pitch": float(player.get("pitch", 0.0))}


func get_saved_inventory() -> Array:
	if not has_save():
		return []
	var player: Variant = _cached_save.get("player", {})
	if not (player is Dictionary):
		return []
	var slots: Variant = player.get("inventory", [])
	return slots if slots is Array else []


func get_saved_selected_slot() -> int:
	if not has_save():
		return 0
	var player: Variant = _cached_save.get("player", {})
	if not (player is Dictionary):
		return 0
	return int(player.get("selected_slot", 0))


# Called by playable_world_data.gd's existing autosave (tick_save/shutdown).
func write_world_state(seed_value: int, overrides: Dictionary) -> void:
	_cached_save["version"] = 2
	_cached_save["seed"] = seed_value
	_cached_save["overrides"] = overrides
	_write_to_disk()


# Called by the player controller's autosave/exit hooks.
func write_player_state(
	position: Vector3,
	yaw: float,
	pitch: float,
	inventory_slots: Array,
	selected_slot: int
) -> void:
	_cached_save["version"] = 2
	_cached_save["player"] = {
		"position": [position.x, position.y, position.z],
		"yaw": yaw,
		"pitch": pitch,
		"inventory": inventory_slots,
		"selected_slot": selected_slot,
	}
	_write_to_disk()


func _autosave_from_live_state() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := scene.get_node_or_null("Player")
	if player != null and player.has_method("save_state_now"):
		player.save_state_now()
	var chunk_manager := scene.get_node_or_null("ChunkManager")
	if chunk_manager != null and chunk_manager.has_method("save_state_now"):
		chunk_manager.save_state_now()


func _load_from_disk() -> void:
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_cached_save = parsed


func _write_to_disk() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: unable to write save file")
		return
	file.store_string(JSON.stringify(_cached_save))
