# Mobile-Only World Consolidation — Step 4 Verification

## Revision under verification

Step 3 commit: `da4989110471677551eedde2b10add9ef7c9b225`

The project uses `scripts/world/playable_world_port.gd` as the unconditional `ChunkManager` implementation on desktop, headless CI, and Android. The legacy desktop chunk/terrain implementation and its dedicated gates remain absent.

## Step 3 full-suite result

All workflows triggered for the Step 3 revision completed successfully:

| Workflow | Run ID | Result |
| --- | ---: | --- |
| TEKNIK Acceptance Gate | 31070341815 | success |
| TEKNIK Playable World Standalone Gate | 31070341813 | success |
| TEKNIK Inventory on Consolidated World | 31070341810 | success |
| TEKNIK Step 3 Touch Gate | 31070341968 | success |
| TEKNIK Vanilla Minecraft Lighting Gate | 31070341806 | success |
| TEKNIK Polish Leaf Seam Gate | 31070341824 | success |
| TEKNIK Step 4 Android Export Setup Gate | 31070341833 | success |
| TEKNIK Step 5 Export Configuration Diagnostic | 31070341805 | success |

The consolidated Acceptance workflow explicitly verified that the retired production files, tests, and workflows are absent and that no active script, scene, test, workflow, or `project.godot` entry references them.

## Acceptance coverage confirmed

- Strict Godot 4.3 project parsing.
- Desktop/headless scene binding to the standalone playable-world adapter.
- Headless and graphical world startup.
- Streaming traversal with the playable runtime's bounded unload buffer.
- Terrain variation, trees, collision readiness, movement, jump, camera look, atmosphere, and screenshot capture.
- Mining targeting, data mutation, collision removal, atomic chunk replacement, and 12-block boundary rebuilds.
- Placement, inventory consumption, occupied-cell rejection, player-overlap rejection, unloaded-cell rejection, and collision creation.
- Loaded-world-edge mine/place stress without loading the outside chunk.
- 36-slot inventory model, mining pickup/full-inventory fallback, placement consumption/retry, hotbar, crafting, inventory UI, camera sensitivity, and approved lighting behavior.
- Touch joystick and drag-look behavior against the consolidated main scene.
- Vanilla face dimming, corner ambient occlusion, leaf skylight, chunk-boundary lighting, and leaf-seam rendering.
- Android export configuration and Gradle export prerequisites.

Each world-mutating CI script uses an isolated Godot user-data directory so persistent `user://` world edits cannot leak between independent acceptance cases.

## Evidence

Consolidated Acceptance artifact:

- Artifact ID: `8955433797`
- Name: `teknik-consolidated-acceptance`
- Size: `1,887,387` bytes
- Digest: `sha256:eb66bf2f5108af835d16dfd66fb7833422b74b94281249a028574a25b528ea61`

## Step 4 gate

This documentation commit must receive the same green PR workflow matrix before Step 4 is marked complete or an Android APK export is started.
