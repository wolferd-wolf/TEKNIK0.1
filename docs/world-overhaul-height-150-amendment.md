# World Overhaul Height Amendment — 150 Blocks

This amendment supersedes the earlier statement in `docs/world-overhaul-plan.md` that the overhaul should retain a 60-block world height.

## Decision

The TEKNIK world-overhaul architecture now targets a **150-block legal vertical world range**.

The old 60-block generator remains useful only as a Stage 1 regression oracle for confirming that the architecture refactor does not accidentally change today's generated terrain before the new terrain stages begin.

## Stage 1 rule

Stage 1 may preserve the current terrain surface heights while changing the legal build/generation ceiling to 150. That means the refactor can still prove terrain/biome output equivalence while making the new vertical range available to later stages.

## Performance rule

A 150-block world limit must **not** mean blindly scanning 150 Y cells for every chunk when most of that range is empty.

The overhaul runtime therefore uses an active-content mesh ceiling derived from:

- the highest generated surface in the padded chunk cache,
- tree-canopy headroom,
- the highest solid edited override affecting the padded chunk,
- a hard clamp at the legal 150-block ceiling.

This keeps the legal vertical range large while preserving the project's mobile-performance discipline.

## Later terrain stages

Stages 2 and 3 may use substantially more of the 150-block range for mountain ranges, plateaus, valleys and other large landforms. Their acceptance gates must demonstrate that terrain is not clipping against the ceiling and that generation remains within the established **1.0 ms p95** generation threshold.

The world-height limit should not be raised again during this overhaul without measured evidence that 150 is insufficient.
