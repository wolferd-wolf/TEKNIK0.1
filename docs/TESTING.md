# Testing

TEKNIK uses focused Godot acceptance scripts and GitHub Actions gates to protect working gameplay while new systems are added.

## Testing Principles

A change is not considered complete only because it compiles.

Relevant changes should prove:

- Script and scene parsing.
- Deterministic behaviour where required.
- Correct gameplay state before and after an action.
- Chunk-boundary behaviour.
- Mesh and collision updates.
- Input compatibility.
- Mobile-device behaviour for Android-facing changes.
- No unrelated file changes.

Visual bugs should be diagnosed before permanent fixes are applied. Temporary diagnostic rendering is acceptable when it isolates winding, culling, lighting, or mesh-boundary faults.

## Basic Project Parse

With Godot 4.3 available:

```bash
godot --headless --path . --editor --quit
```

This catches syntax errors, missing resources, and scene import failures.

## Running a Godot Test Script

Most repository acceptance tests extend `SceneTree` and are run directly:

```bash
godot \
  --headless \
  --path . \
  --script res://tests/TEST_FILE.gd
```

Tests that need a graphical viewport can run through Xvfb in Linux CI:

```bash
xvfb-run -a -s "-screen 0 1280x720x24" godot \
  --audio-driver Dummy \
  --path . \
  --script res://tests/TEST_FILE.gd
```

A test should return a non-zero exit code on failure and print a unique pass marker on success.

## Inventory Acceptance Tests

Current inventory coverage includes:

```text
tests/inventory_step1_gate.gd
tests/inventory_mining_step2_gate.gd
tests/inventory_placement_step3_gate.gd
tests/inventory_vanilla_baseline_gate.gd
```

These gates cover areas including:

- 36-slot inventory structure.
- Nine-slot hotbar and 27 storage slots.
- Stack size and stacking behaviour.
- Mining pickup.
- Full-inventory mining rejection.
- Placement consumption.
- Inventory screen interactions.
- Preservation of the approved camera, lighting, world, and control baseline.

The inventory workflow also enforces an allowlist of files that the inventory feature was permitted to change.

## World and Remesh Testing

World edits must be checked at both ordinary and boundary coordinates.

Minimum mining/placement coverage should include:

- A block inside a chunk.
- Each horizontal chunk edge.
- A chunk corner.
- Repeated edits to one coordinate.
- Edits spread across different coordinates.
- Mine then replace cycles.
- Adjacent chunk mesh refresh.
- Collision refresh near the player.
- No stale or missing visible faces.

When a change affects asynchronous or queued remeshing, inspect diagnostics for:

- Tasks started.
- Results applied.
- Stale results discarded.
- Coalesced requests.
- Active tasks.
- Pending applies.
- Maximum queue, compute, apply, and pump timings.

## Determinism Testing

Procedural generation must not depend on chunk creation order.

For a fixed seed and coordinate set, test:

- Repeated height samples are identical.
- Block IDs are identical across repeated instances.
- Trees resolve identically.
- Generating neighbouring chunks in different orders gives the same border blocks.
- Saving and reloading overrides preserves the same edited world.

Future generator versions should retain fixed seed fixtures and block-data hashes for regression comparison.

## Lighting and Meshing Testing

Lighting or face-culling changes should check:

- Shared faces between solid blocks are omitted.
- Leaf-to-leaf internal faces follow the intended policy.
- Face winding is correct with back-face culling enabled.
- Top, bottom, and side brightness values remain correct.
- Ambient-occlusion corners sample the correct neighbours.
- Chunk borders use enough padding for matching light and geometry.
- Mining and placement update lighting on affected neighbouring chunks.

For difficult artifacts, compare diagnostic modes such as:

- Unshaded material.
- Flat high-contrast background.
- Back-face culling enabled and disabled.
- Lighting or AO disabled independently.
- Wireframe or per-face debug colouring.

Diagnostics should be removed after the fault is understood unless they are intentionally retained as development tools.

## Input Testing

Input changes should test both the named `InputMap` action and the physical/touch path that emits it.

### Desktop

- Keyboard movement.
- Mouse look.
- Mouse mining and placement.
- Number-key hotbar selection.
- Mouse-wheel hotbar cycling.
- Inventory toggle.

### Touch

- Joystick capture and release.
- Right-side look capture and release.
- Simultaneous movement and look touches.
- Reverse boundary cases where a touch begins outside one control and enters another region.
- Jump, mine, place, craft, and hotbar touch buttons.
- Inventory toggle, slot tap, long press, and close behaviour.

Touch controls must not leak into desktop mouse-look through touch-to-mouse emulation.

## Android Acceptance

CI cannot replace physical device testing.

For Android-facing changes, install the exact APK produced from the tested commit and record:

- Commit SHA.
- Workflow run ID.
- Artifact name.
- Device and Android version when relevant.
- Launch result.
- Gameplay checks performed.
- Performance or visual regressions observed.

A build that exports successfully but crashes or performs poorly on-device is a failed gameplay build.

## Scope Control

Each feature branch should have a declared scope.

Before accepting a change:

```bash
git diff --name-only BASE_SHA HEAD
```

Confirm every changed file is required. Unrelated formatting, refactors, generated metadata, and accidental files should be removed rather than rationalized after the fact.

## Merge Gate

A branch is ready for merge only when:

- Its intended behaviour is complete.
- Relevant automated gates pass.
- The diff contains no unrelated changes.
- Device validation is complete when required.
- Known failures and limitations are reported honestly.
- The repository owner explicitly approves the merge.

Do not merge merely because CI is green.