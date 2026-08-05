# Contributing to TEKNIK 0.1

TEKNIK 0.1 is under active prototype development. Changes must protect the currently working Android gameplay baseline.

## Core Rule

**Do not merge a branch without explicit approval from the repository owner.**

A branch being complete, reviewed, or green in CI does not grant merge permission.

## Before Starting

1. Read [README.md](README.md).
2. Read [Project Status](docs/PROJECT_STATUS.md).
3. Read [Architecture](docs/ARCHITECTURE.md) for the active runtime path.
4. Define the exact scope of the change.
5. Identify the tests and device checks required before editing.

## Branches

Create a dedicated branch from the current approved `main` head.

Recommended naming:

```text
feature/<short-description>
fix/<short-description>
docs/<short-description>
test/<short-description>
```

Do not develop directly on `main` unless the repository owner explicitly requests that exact workflow.

## Scope Discipline

A branch should solve one defined problem.

Avoid:

- Opportunistic refactors.
- Formatting unrelated files.
- Changing controls while working on terrain.
- Changing rendering while working on inventory.
- Adding dependencies without a demonstrated need.
- Replacing a working system without preserving its acceptance behaviour.
- Committing generated or temporary diagnostic files accidentally.

Before reporting completion, inspect:

```bash
git diff --name-only BASE_SHA HEAD
```

Every changed file must be justified by the branch scope.

## Active World Path

For the current Android APK, world changes normally belong in:

```text
scripts/world/playable_world_port.gd
scripts/world/playable_world_runtime.gd
scripts/world/playable_world_data.gd
scripts/world/playable_world_mesher.gd
scripts/world/localized_water_bodies.gd
```

The older `chunk_manager.gd` and `chunk.gd` path is not the terrain runtime seen in the Android build unless the playable-world port is inactive.

Do not implement a feature only in the legacy path and report it as an Android gameplay feature.

## Code Style

- Use Godot 4-compatible typed GDScript where practical.
- Keep functions focused.
- Use clear names over compressed names.
- Prefer deterministic world-coordinate functions for procedural systems.
- Do not depend on chunk generation order.
- Keep tuning values as named constants or exports.
- Avoid hidden state and unseeded randomness.
- Check return values for world and inventory transactions.
- Preserve rollback behaviour when an operation spans multiple systems.

## Scene-Tree and Thread Safety

Do not add, remove, or mutate scene nodes from worker threads.

Worker threads may compute plain data such as:

- Block arrays.
- Height samples.
- Packed vertices.
- Packed normals.
- Packed colours.
- Packed indices.

Apply nodes, meshes, materials, and collision resources on the main thread.

## Tests

Read [Testing](docs/TESTING.md).

At minimum:

1. Run a Godot parse check.
2. Run the feature-specific acceptance tests.
3. Run relevant regression gates.
4. Test chunk boundaries for world edits.
5. Test on Android hardware for mobile-facing changes.

Do not weaken, delete, or bypass an existing test solely to make a change pass.

When a test expectation is genuinely obsolete, explain why and update it in the same branch with evidence.

## Bug Fixes

Diagnose before changing production code.

A good bug report or fix record includes:

- Reproduction steps.
- Expected result.
- Actual result.
- Exact affected commit.
- Device or platform.
- Relevant logs.
- Root cause.
- Why the selected fix is narrow.
- Regression test added.

For rendering faults, use temporary diagnostic modes to isolate:

- Face winding.
- Back-face culling.
- Internal-face culling.
- AO.
- Skylight.
- Material shading.
- Chunk-border sampling.

Remove temporary diagnostics after the issue is understood unless they are intentionally retained as tools.

## Commits

Use clear, scoped commit messages.

Examples:

```text
[TEKNIK] fix leaf face culling across chunk borders
[TEKNIK] add inventory storage interaction gate
docs: document Android export workflow
```

Commit checkpoints are encouraged during complex work, but a formal step should not be marked complete until its gate passes.

## Pull Requests

A pull request should state:

- Problem being solved.
- Exact scope.
- Files changed.
- Implementation summary.
- Tests executed.
- CI run IDs.
- Android artifact and device result when applicable.
- Known limitations.
- Screenshots or video for visual changes.

Do not enable auto-merge.

Do not merge the pull request without explicit owner approval.

## Documentation

Update documentation when a change affects:

- Controls.
- Gameplay behaviour.
- World-generation rules.
- Save format.
- Build requirements.
- Android export.
- Project limitations.
- Architecture or runtime selection.

Documentation must describe what the code actually does, not what is merely planned.

## Security and Secrets

Never commit:

- Release keystores.
- Keystore passwords.
- API keys.
- Store credentials.
- Personal device identifiers.
- Private signing files.

Use protected CI secrets for future release signing.

## Completion Report

When work is ready for inspection, report:

- Branch name.
- Final commit SHA.
- File list.
- Test commands.
- Test results.
- CI run IDs.
- APK artifact when relevant.
- Device validation performed.
- Remaining risks.

Then stop and wait for explicit merge approval.