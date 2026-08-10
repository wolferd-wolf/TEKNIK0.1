extends Resource
class_name TextureBlockRegistry

@export var blocks: Array[TextureBlockConfig] = []

func get_config(block_type: String) -> TextureBlockConfig:
	for config in blocks:
		if config.block_type == block_type:
			return config
	return null

func get_block_types() -> Array[String]:
	var result: Array[String] = []
	for config in blocks:
		result.append(config.block_type)
	return result
