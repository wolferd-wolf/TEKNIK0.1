# Step 3 Acceptance Report — Touch Buttons and Hotbar Tap Selection

Status: **Passed in CI; real Android device verification remains deferred to the supervised export session.**

## Accepted implementation

- Rendered touch buttons: `jump`, `mine_block`, `place_block`, `craft_test_recipe`.
- Rendered tappable hotbar targets: `select_hotbar_1` through `select_hotbar_9`, selecting inventory slots 0 through 8.
- Touch input is routed through the existing Godot InputMap actions.
- Existing desktop keyboard and mouse bindings remain present.
- Independent touch indices are tracked and released safely; leaving the scene releases all pressed actions.

## Gate evidence

- Corrected head commit: `06a818e33d60391f76c2e187f97d10a186ea0ab3`.
- Dedicated Step 3 run: `30854850812` — success.
- Dedicated job: `91823359596` — success.
- Evidence artifact: `8872047164`, `teknik-step3-touch-gate`.
- Artifact digest: `sha256:5ae02f080857a22954058dee0437386bfaacab448ba988b53ba3816edf60d897`.
- Inherited acceptance run: `30854850917` — success.
- Inherited acceptance job: `91823359033` — success.

## Exact automated behaviors tested

- Project parses under Godot 4.3.
- `InputEventScreenTouch` is injected through `Input.parse_input_event`.
- Each rendered action button presses and releases its exact existing InputMap action.
- Each of nine rendered hotbar targets selects the expected slot from 0 through 8.
- Keyboard or mouse events remain attached to every affected InputMap action.
- The process exits cleanly without stuck actions or a crash.
- A 1280×720 screenshot is produced and stored in the evidence artifact.
- The complete inherited world, mining, placement, inventory, crafting, hotbar, virtual joystick, and drag-look gate remains green.

## Screenshot inspection

The accepted screenshot shows all four action buttons fully inside the viewport, all nine hotbar slots visible and tappable, slot 9 selected, the virtual joystick unobstructed, and the drag-look area visible. No action-button or hotbar overlap was observed at 1280×720.

## Rejected run and correction

- Rejected Step 3 run: `30850517504`.
- Failed artifact: `8870406662`.
- Failed artifact digest: `sha256:09c8bf1e7426930f76f7207f7373feb88c24c80bcedba7648517973b478ed004`.
- Failure: simulated screen touches did not emit `Button.button_down`, so InputMap actions were not pressed and hotbar selection remained at slot 0.
- Correction: retain the rendered buttons but explicitly hit-test `InputEventScreenTouch` positions in the overlay, bind each touch index to the matching existing InputMap action, and release that action on touch-up.

## Remaining device gap

This acceptance is desktop Xvfb touch simulation, not physical Android evidence. Physical multi-touch feel, finger ergonomics, device scaling, and Android event delivery must be checked during the supervised export session.

## Hard stop observed

No Android export preset, export template, signing configuration, Gradle setup, or APK export work was attempted.