extends SceneTree

const CraftingRecipe = preload("res://scripts/crafting/crafting_recipe.gd")
const CraftingSystem = preload("res://scripts/crafting/crafting_system.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var failures: Array[String] = []
	
	print("=== CRAFTING LOGIC UNIT TEST ===")
	
	var inventory := BlockInventory.new(9, 64)
	var recipe := CraftingSystem.get_test_recipe()
	
	print("Test Recipe: %s" % recipe.recipe_id)
	print("Required: 4x LOG (block_id=%d)" % 5)
	print("Output: 1x PLANKS (block_id=%d)" % 4)
	print("")
	
	# Test 1: Empty inventory should fail
	print("TEST 1: Empty inventory")
	var result1 := CraftingSystem.can_craft(recipe, inventory)
	if result1:
		failures.append("Empty inventory returned true, expected false")
		print("  FAIL: can_craft returned true for empty inventory")
	else:
		print("  PASS: can_craft returned false for empty inventory")
	print("")
	
	# Test 2: Insufficient items (3 logs instead of 4)
	print("TEST 2: Insufficient items (3 logs)")
	inventory.add_item(5, 3)
	var result2 := CraftingSystem.can_craft(recipe, inventory)
	if result2:
		failures.append("Insufficient items (3 logs) returned true, expected false")
		print("  FAIL: can_craft returned true with only 3 logs")
	else:
		print("  PASS: can_craft returned false with only 3 logs")
	print("")
	
	# Test 3: Exact amount (4 logs)
	print("TEST 3: Exact amount (4 logs)")
	inventory.add_item(5, 1)
	var log_count := inventory.get_item_count(5)
	print("  Inventory has %d logs" % log_count)
	var result3 := CraftingSystem.can_craft(recipe, inventory)
	if not result3:
		failures.append("Exact amount (4 logs) returned false, expected true")
		print("  FAIL: can_craft returned false with 4 logs")
	else:
		print("  PASS: can_craft returned true with 4 logs")
	print("")
	
	# Test 4: More than required (8 logs)
	print("TEST 4: More than required (8 logs total)")
	inventory.add_item(5, 4)
	log_count = inventory.get_item_count(5)
	print("  Inventory has %d logs" % log_count)
	var result4 := CraftingSystem.can_craft(recipe, inventory)
	if not result4:
		failures.append("Excess items (8 logs) returned false, expected true")
		print("  FAIL: can_craft returned false with 8 logs")
	else:
		print("  PASS: can_craft returned true with 8 logs")
	print("")
	
	# Test 5: Wrong item (only stone, no logs)
	print("TEST 5: Wrong item (only stone, no logs)")
	var inventory2 := BlockInventory.new(9, 64)
	inventory2.add_item(3, 64)
	var result5 := CraftingSystem.can_craft(recipe, inventory2)
	if result5:
		failures.append("Wrong item (stone) returned true, expected false")
		print("  FAIL: can_craft returned true with wrong item")
	else:
		print("  PASS: can_craft returned false with wrong item")
	print("")
	
	# Test 6: Null recipe
	print("TEST 6: Null recipe")
	var result6 := CraftingSystem.can_craft(null, inventory)
	if result6:
		failures.append("Null recipe returned true, expected false")
		print("  FAIL: can_craft returned true for null recipe")
	else:
		print("  PASS: can_craft returned false for null recipe")
	print("")
	
	# Test 7: Null inventory
	print("TEST 7: Null inventory")
	var result7 := CraftingSystem.can_craft(recipe, null)
	if result7:
		failures.append("Null inventory returned true, expected false")
		print("  FAIL: can_craft returned true for null inventory")
	else:
		print("  PASS: can_craft returned false for null inventory")
	print("")
	
	print("=== TEST SUMMARY ===")
	if failures.is_empty():
		print("ALL TESTS PASSED")
		print("CRAFTING_LOGIC_TEST_PASS")
		quit(0)
	else:
		print("TESTS FAILED: %d" % failures.size())
		for failure in failures:
			print("  FAILURE: %s" % failure)
		print("CRAFTING_LOGIC_TEST_FAIL")
		quit(1)
