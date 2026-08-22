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
}

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
}

# Items that read better with a symbol glyph on the swatch.
const GLYPH := {
	13: "F",   # furnace
	9: "D",    # drill
	7: "W",    # water wheel
	8: "|",    # shaft
}


static func display_name(block_id: int) -> String:
	return String(NAMES.get(block_id, "BLOCK %d" % block_id))


static func swatch_color(block_id: int) -> Color:
	var color: Color = SWATCH.get(block_id, Color.MAGENTA)
	return color


static func glyph(block_id: int) -> String:
	return String(GLYPH.get(block_id, ""))


static func is_known(block_id: int) -> bool:
	return NAMES.has(block_id)
