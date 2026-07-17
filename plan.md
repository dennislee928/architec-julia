# Implementation Plan (v4 — FINAL, post-grill)

> Status: **Phase 1 COMPLETE (2026-07-17)** — baseline harness built and run; see
> `bench/results/baseline-2026-07-17.md`. Key numbers (Julia 1.12.6, Apple Silicon):
> cold precompile CSV 18 s / DataFrames 45 s / Plots 55 s; load 1.2 / 2.1 / 4.6 s;
> TTFX ≤ 0.9 s; invalidations 973 / 1262 / 1539. Conclusion: on 1.12 the start-up
> loss lives in **precompilation and invalidation rework**, not runtime TTFX.
> Phase 2 target: invalidation-reduction PRs (DataFrames/Plots trees first).
>
> Scoped with the owner on 2026-07-17 over two review rounds. v2 (docs-site) was
> rejected as a misread of the goal; v3's open questions were answered in round 2.

## 1. Mission

Contribute to and refine the **Julia language**, using the owner's
lean-construction framework as the guiding theory:

| Julia pain point | Lean analogue | Countermeasure |
|---|---|---|
| TTFP / JIT cold start | Mobilization & ramp-up loss | Front-End Planning: precompilation, system images, invalidation reduction |
| Memory / binary bloat | Excess inventory / WIP | Tree-shaking, dead-code elimination, WIP caps |
| Runtime-only error discovery | End-of-line inspection | Shift-left: static analysis (JET/Aqua), Poka-Yoke checks |

## 2. Decisions (grill round 2, 2026-07-17)

| Question | Decision |
|---|---|
| Track | **B → A ramp**: ecosystem packages first (pure Julia), graduate to core/compiler later |
| First pain point | **TTFP / cold start** |
| Skill posture | Learning both Julia internals and C++/LLVM → prefer small, well-scoped, mentorable targets |
| First deliverable | **Benchmark baseline harness** ("First-Run Study"), then choose the upstream PR target from data |

## 3. Phase 1 (this session): TTFP baseline harness

Build `bench/` in this repo:

1. **`bench/ttfx.jl`** — measures, per target package:
   - fresh-precompile time (`Pkg.precompile` after cache purge = true cold mobilization)
   - `@time using X` load time (cold vs. warm process)
   - time-to-first-execute of a representative call (TTFX)
2. **`bench/invalidations.jl`** — uses `SnoopCompileCore.@snoop_invalidations` to
   count method invalidations triggered by loading each target package (start-up
   loss root cause in Julia ≥1.9's pkgimage world).
3. **`bench/run.sh`** — orchestrates cold/warm runs in separate processes (JIT state
   is per-process, so warm ≠ same-process rerun) and writes
   `bench/results/baseline-<date>.md`.
4. **Target packages** (small→large TTFX ladder): `CSV`, `DataFrames`, `Plots`
   (the canonical "time to first plot" case).
5. **Report**: `bench/results/baseline-2026-07-17.md` with tables + interpretation
   through the lean lens (where the start-up loss actually is).

## 4. Phase 2 (next): pick and ship the first upstream PR

From baseline data, choose one:
- A PrecompileTools.jl workload PR to a package the data shows is
  under-precompiled, or
- an invalidation-reduction PR (guided by `@snoop_invalidations` output), or
- a JET.jl/Aqua.jl rule if Phase 1 surfaces a type-instability pattern.

Follow `contribute.md` discipline: feature branch, atomic commits, DCO sign-off,
targeted tests, benchmark before/after.

## 5. Phase 3 (later): graduate to core (Track A)

Set up a `JuliaLang/julia` source build with `Make.user`
(`WITH_CCACHE=1`, debug build) per `readme.md`, and target method-invalidation /
startup-latency issues in core.

## 6. Role of this repo

Mission control: reference docs (`readme.md`, `docs/`, `contribute.md`), this plan,
the benchmark harness, and result logs. Not a docs-site project.
