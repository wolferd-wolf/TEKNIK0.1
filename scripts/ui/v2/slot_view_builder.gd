extends RefCounted
class_name SlotViewBuilder

## Pure presentation mapping for the v2 UI: backend stack dictionary ->
## immutable view payload for ItemSlotV2.bind_view(). Read-only by
## construction: never mutates the stack it receives. Used by both the
## screen (writer tier) and the hotbar (read-only subscriber).

const ITEM_REGISTRY := preload("res://scripts/items/item_registry.gd")


static func build(stack: Dictionary) -> Dictionary:
	var block_id := int(stack.get("block_id", 0))
	var count := int(stack.get("count", 0))
	if block_id <= 0 or count <= 0:
		return {"texture": null, "count_text": ""}
	return {
		"texture": ITEM_REGISTRY.icon(block_id),
		"tint": ITEM_REGISTRY.icon_tint(block_id),
		"swatch_color": ITEM_REGISTRY.swatch_color(block_id),
		"count_text": "x%d" % count,
		"tooltip": ITEM_REGISTRY.display_name(block_id),
		"dimmed": false,
	}
