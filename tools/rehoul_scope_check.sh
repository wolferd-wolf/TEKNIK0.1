#!/usr/bin/env bash
# Scope guard for the inventory/UI/crafting rehoul (GATES.md G9).
# Fails when the diff vs the baseline commit touches anything outside the
# rehoul's allowed surfaces. GATES.md and these two tools are untracked.
set -u
cd "$(dirname "$0")/.."

BASELINE="$(cat /tmp/rehoul_baseline_commit.txt 2>/dev/null || echo HEAD~1)"

ALLOWED_REGEX='^(scripts/ui/(hud_hotbar|station_screen|item_slot_view)\.gd)$'
ALLOWED="$ALLOWED_REGEX"
ALLOWED+='|^(scenes/ui/(hotbar_v2|inventory_screen_v2)\.tscn)$'
ALLOWED+='|^(scripts/ui/(minecraft_inventory_screen\.gd(\.bak)?|inventory_hotbar\.gd))$'
ALLOWED+='|^(scripts/ui/v2/.*)$'
ALLOWED+='|^(scripts/player/inventory_first_person_controller\.gd)$'
ALLOWED+='|^(scripts/items/item_registry\.gd)$'
ALLOWED+='|^(scripts/inventory/(block_inventory|block_stations)\.gd)$'
ALLOWED+='|^(scripts/crafting/crafting_recipes\.gd)$'
ALLOWED+='|^(scripts/world/playable_world_mesher\.gd)$'
ALLOWED+='|^(native/carpathian/src/teknik_voxel_mesher\.hpp)$'
ALLOWED+='|^tests/(inventory_rehoul_gate|inventory_redo_gate|inventory_ui_v2_gate|inventory_hotbar_step4_gate|inventory_crafting_step5_gate|smelting_gate|diagnostic_log_capture_gate)\.gd$'

DIFF_NAMES="$(git diff --name-only "$BASELINE" -- scripts scenes native tests)"
if [ $? -ne 0 ]; then
  echo "SCOPE_CHECK_BROKEN: git diff failed for baseline $BASELINE"
  exit 1
fi
if [ -z "$DIFF_NAMES" ]; then
  echo "SCOPE_CHECK_BROKEN: empty diff vs baseline (nothing changed?)"
  exit 1
fi

VIOLATIONS="$(echo "$DIFF_NAMES" | grep -Ev "$ALLOWED" || true)"
if [ -n "$VIOLATIONS" ]; then
  echo "SCOPE_VIOLATIONS:"
  echo "$VIOLATIONS"
  exit 1
fi

# Every old UI file that existed at baseline must be gone from the tree now.
DELETED_EXPECTED=(
  "scripts/ui/minecraft_inventory_screen.gd"
  "scripts/ui/minecraft_inventory_screen.gd.bak"
  "scripts/ui/inventory_hotbar.gd"
  "scripts/ui/v2/hotbar_v2.gd"
  "scripts/ui/v2/inventory_screen_v2.gd"
  "scripts/ui/v2/item_slot_v2.gd"
  "scripts/ui/v2/slot_view_builder.gd"
  "scenes/ui/hotbar_v2.tscn"
  "scenes/ui/inventory_screen_v2.tscn"
)
for expected in "${DELETED_EXPECTED[@]}"; do
  if git cat-file -e "$BASELINE:$expected" 2>/dev/null && [ -e "$expected" ]; then
    echo "STALE_FILE_STILL_PRESENT: $expected"
    exit 1
  fi
done

echo "SCOPE_OK"
exit 0
