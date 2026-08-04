extends SceneTree

const PRESET_PATH := "res://export_presets.cfg"
const PRESET_SECTION := "preset.0"
const OPTIONS_SECTION := "preset.0.options"
const PROJECT_ICON_PATH := "res://assets/icon.svg"


func _initialize() -> void:
	var config := ConfigFile.new()
	var load_error := config.load(PRESET_PATH)
	_expect(load_error == OK, "export_presets.cfg must load")

	_expect(ProjectSettings.get_setting("application/config/icon", "") == PROJECT_ICON_PATH, "placeholder project icon configured")
	_expect(FileAccess.file_exists(PROJECT_ICON_PATH), "placeholder project icon exists")

	_expect(config.get_value(PRESET_SECTION, "name", "") == "Android Debug", "preset name")
	_expect(config.get_value(PRESET_SECTION, "platform", "") == "Android", "Android platform")
	_expect(config.get_value(PRESET_SECTION, "runnable", false), "runnable preset")
	_expect(config.get_value(PRESET_SECTION, "export_path", "") == "", "no committed APK output path")

	_expect(config.get_value(OPTIONS_SECTION, "package/unique_name", "") == "com.wolferdwolf.teknik", "package name")
	_expect(config.get_value(OPTIONS_SECTION, "package/signed", false), "debug signing enabled")
	_expect(config.get_value(OPTIONS_SECTION, "gradle_build/use_gradle_build", false), "Gradle build enabled")
	_expect(config.get_value(OPTIONS_SECTION, "gradle_build/min_sdk", "") == "24", "minimum API 24")
	_expect(config.get_value(OPTIONS_SECTION, "gradle_build/target_sdk", "") == "34", "target API 34")

	_expect(not config.get_value(OPTIONS_SECTION, "architectures/armeabi-v7a", true), "ARMv7 disabled")
	_expect(config.get_value(OPTIONS_SECTION, "architectures/arm64-v8a", false), "ARM64 enabled")
	_expect(not config.get_value(OPTIONS_SECTION, "architectures/x86", true), "x86 disabled")
	_expect(not config.get_value(OPTIONS_SECTION, "architectures/x86_64", true), "x86_64 disabled")

	_expect(config.get_value(OPTIONS_SECTION, "keystore/debug", "") == "", "debug keystore path stays outside version control")
	_expect(config.get_value(OPTIONS_SECTION, "keystore/debug_user", "") == "", "debug alias supplied by environment")
	_expect(config.get_value(OPTIONS_SECTION, "keystore/debug_password", "") == "", "debug password supplied by environment")
	_expect(config.get_value(OPTIONS_SECTION, "keystore/release", "") == "", "release keystore remains unset")
	_expect(config.get_value(OPTIONS_SECTION, "keystore/release_user", "") == "", "release alias remains unset")
	_expect(config.get_value(OPTIONS_SECTION, "keystore/release_password", "") == "", "release password remains unset")

	print("ANDROID_EXPORT_SETUP_STEP4_PRESET_PASS")
	quit(0)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("Android export setup assertion failed: %s" % label)
	quit(1)
