extends Node

## Reports whether the native C++ GDExtension is loaded into the engine.
##
## Every native acceleration path in the game must be gated behind
## [method is_native_available]. When the extension is missing or fails to
## load, the game must run entirely on GDScript fallbacks with identical
## behavior (rule 1 of TEKNIK_BUILD_PLAN_NATIVE_AND_CAVES.md).

## Classes registered by the native GDExtension. Availability means at least
## one of them is live in ClassDB. TeknikCarpathianSampler ships today;
## TeknikVoxelMesher joins when the native mesher reaches parity (step 4).
const NATIVE_CLASSES: Array[StringName] = [
	&"TeknikCarpathianSampler",
	&"TeknikVoxelMesher",
]

var _cached_available: bool = false
var _checked: bool = false


func _ready() -> void:
	var mode := "native" if is_native_available() else "gdscript_fallback"
	print("TEKNIK NativeLoader: mode=", mode)


func is_native_available() -> bool:
	if not _checked:
		_cached_available = false
		for native_class in NATIVE_CLASSES:
			if ClassDB.class_exists(native_class):
				_cached_available = true
				break
		_checked = true
	return _cached_available


func reset_cache_for_testing() -> void:
	_checked = false
