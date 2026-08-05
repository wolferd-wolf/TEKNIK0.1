# TEKNIK Session — Minecraft-Style Inventory

## Rules

1. GDScript only.
2. One numbered step equals one commit. Do not bundle steps.
3. Inventory scope only. Do not modify world generation, terrain, lighting, shadows, movement tuning, camera tuning, mining speed, block hardness, crafting recipes, Android export, or unrelated UI.
4. Keep the existing mining and placement behavior, but continue using inventory as their only item source/sink. Do not restore the old hardcoded placement palette.
5. Placeholder text and shapes are acceptable. No art pass or texture work.
6. Every step must pass a focused gate before the next step starts. Do not mark a failed or unverified step complete.
7. Commit format: `[TEKNIK] step N: <short description>`.
8. Stop after Step 5.

## Steps

1. Expand the inventory model to 36 slots: nine hotbar slots plus 27 storage slots. Preserve 64-item stacks and atomic add/remove behavior. Add model-level stack pickup, merge, swap, split, and single-item placement operations.
2. Add a full inventory screen showing the 27 storage slots and the same nine hotbar slots. Add an InputMap inventory toggle and a visible touch-friendly open/close button. No crafting, armor, offhand, chest, or recipe UI.
3. Add Minecraft-style slot interaction: primary click/tap picks up, places, merges, or swaps full stacks; secondary click splits a stack or places one item. On touch, long-press performs the secondary action.
4. Lock gameplay input while the inventory is open, expose the cursor stack clearly, keep the always-visible hotbar synchronized, and return any carried stack safely when closing.
5. Run the complete inventory acceptance gate: 36-slot model, stack operations, inventory-screen layout, mouse/touch interaction paths, mining pickup, selected-slot placement consumption, full-inventory mining rejection, open/close input locking, screenshot, and crash checks.

## Definition of done

The player has a 36-slot inventory with a nine-slot hotbar and 27 storage slots. The inventory can be opened on desktop and Android, stacks can be moved/merged/swapped/split using Minecraft-style interactions, mining adds blocks, placement consumes the selected hotbar stack, and no unrelated system changes are included.

## Deferred

- Crafting-grid UI and recipes
- Armor and offhand slots
- Chests or container inventories
- Item drops, drag-distribution, shift-click, double-click collection, and creative inventory
- Inventory art, icons, textures, sounds, and animation
