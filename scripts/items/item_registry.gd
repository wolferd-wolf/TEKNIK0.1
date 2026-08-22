extends RefCounted
class_name ItemRegistry

## Single source of truth for block/item presentation (names + swatch colors).
## Both meshers own the WORLD colors for lighting; this table owns the UI
## swatches. Values mirror teknik_voxel_mesher block_color() so the UI shows
## what the world renders.

const NAMES := {
	0: "AIR",
	1: "GRASS",
	2: "DIRT",
	3: "STONE",
	4: "SAND",
	5: "LOG",
	6: "LEAVES",
	7: "WATER WHEEL",
	8: "SHAFT",
	9: "MECHANICAL DRILL",
	10: "COAL ORE",
	11: "IRON ORE",
	12: "COPPER ORE",
	13: "FURNACE",
	14: "IRON INGOT",
	15: "COPPER INGOT",
	16: "COAL",
	17: "GLASS",
	18: "CHARCOAL",
	19: "CRAFTING TABLE",
	20: "CHEST",
}

# Station blocks that open a menu when used in the world.
const STATION_CRAFTING_TABLE := 19
const STATION_CHEST := 20
const STATION_IDS := [13, STATION_CRAFTING_TABLE, STATION_CHEST]

const SWATCH := {
	0: Color(0.09, 0.10, 0.12),
	1: Color(0.36, 0.62, 0.26),
	2: Color(0.48, 0.33, 0.20),
	3: Color(0.55, 0.55, 0.58),
	4: Color(0.87, 0.80, 0.57),
	5: Color(0.42, 0.29, 0.15),
	6: Color(0.22, 0.52, 0.18),
	7: Color(0.45, 0.52, 0.60),
	8: Color(0.38, 0.38, 0.42),
	9: Color(0.62, 0.35, 0.20),
	10: Color(0.30, 0.30, 0.32),
	11: Color(0.72, 0.58, 0.45),
	12: Color(0.44, 0.72, 0.60),
	13: Color(0.38, 0.34, 0.31),
	14: Color(0.78, 0.78, 0.80),
	15: Color(0.80, 0.48, 0.26),
	16: Color(0.12, 0.12, 0.13),
	17: Color(0.78, 0.88, 0.92),
	18: Color(0.20, 0.19, 0.18),
	19: Color(0.58, 0.42, 0.24),
	20: Color(0.45, 0.31, 0.16),
}

# Items that read better with a symbol glyph on the swatch.
const GLYPH := {
	13: "F",   # furnace
	9: "D",    # drill
	7: "W",    # water wheel
	8: "|",    # shaft
	19: "T",   # crafting table
	20: "C",   # chest
}


static func display_name(block_id: int) -> String:
	return String(NAMES.get(block_id, "BLOCK %d" % block_id))


static func swatch_color(block_id: int) -> Color:
	var color: Color = SWATCH.get(block_id, Color.MAGENTA)
	return color


static func glyph(block_id: int) -> String:
	return String(GLYPH.get(block_id, ""))


## Downloaded Minetest Game textures (CC BY-SA 3.0, see
## assets/textures/CREDITS.md) used as inventory icons.
const ICON_PATHS := {
	1: "res://assets/textures/icons/default_grass.png",
	2: "res://assets/textures/icons/default_dirt.png",
	3: "res://assets/textures/icons/default_stone.png",
	4: "res://assets/textures/icons/default_sand.png",
	5: "res://assets/textures/icons/default_tree.png",
	6: "res://assets/textures/icons/default_leaves.png",
	7: "res://assets/textures/icons/default_ladder_wood.png",
	8: "res://assets/textures/icons/default_stick.png",
	9: "res://assets/textures/icons/default_tool_steelpick.png",
	10: "res://assets/textures/icons/default_mineral_coal.png",
	11: "res://assets/textures/icons/default_mineral_iron.png",
	12: "res://assets/textures/icons/default_mineral_copper.png",
	13: "res://assets/textures/icons/default_furnace_front.png",
	14: "res://assets/textures/icons/default_steel_ingot.png",
	15: "res://assets/textures/icons/default_copper_ingot.png",
	16: "res://assets/textures/icons/default_coal_lump.png",
	17: "res://assets/textures/icons/default_glass.png",
	18: "res://assets/textures/icons/default_coal_lump.png", # tinted charcoal
}

## Per-icon modulate; charcoal is the coal lump with a woody dark tint.
const ICON_TINTS := {
	18: Color(0.55, 0.40, 0.28),
}

static var _icon_cache := {}


## Texture for the item, or null when the id has no icon (air/unknown).
static func icon(block_id: int) -> Texture2D:
	var key := int(block_id)
	if _icon_cache.has(key):
		return _icon_cache[key]
	if not ICON_PATHS.has(key):
		return null
	var tex := load(ICON_PATHS[key]) as Texture2D
	_icon_cache[key] = tex
	return tex


static func icon_tint(block_id: int) -> Color:
	return ICON_TINTS.get(int(block_id), Color.WHITE)


static func is_known(block_id: int) -> bool:
	return NAMES.has(block_id)
