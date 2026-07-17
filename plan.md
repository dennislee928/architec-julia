# Implementation Plan (v4 — FINAL, post-grill)

> Status: **Phase 1 COMPLETE (2026-07-17)** — baseline harness built and run; see
> `bench/results/baseline-2026-07-17.md`. Key numbers (Julia 1.12.6, Apple Silicon):
> cold precompile CSV 18 s / DataFrames 45 s / Plots 55 s; load 1.2 / 2.1 / 4.6 s;
> TTFX ≤ 0.9 s; invalidations 973 / 1262 / 1539. Conclusion: on 1.12 the start-up
> loss lives in **precompilation and invalidation rework**, not runtime TTFX.
>
> **Phase 2 target selection COMPLETE (2026-07-17)** — invalidation trees analyzed
> (`bench/toptrees.jl`); four named PR candidates in §4, starting with JSON.jl's
> `PtrString` conversions. Next action: check upstream issues, then branch and fix.
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

## 4. Phase 2: ship the first upstream PR — targets selected (2026-07-17)

Invalidation-tree analysis ran via `bench/toptrees.jl` (full output in
`bench/results/toptrees-{DataFrames,Plots}.txt`). Concrete candidates, ranked by
fit for a first PR (small, pure Julia, measurable):

| # | Trigger (package to patch) | Damage | Fix shape |
|---|---|---|---|
| 1 | `JSON.PtrString`: `convert(::Type{String}, x::PtrString)` and `convert(::Type{Symbol}, ...)` (JSON.jl) | 2 of Plots' top-5 trees | Trigger methods intersect abstract `convert` signatures compiled in Base; narrow the callers or precompile-protect — classic SnoopCompile fix |
| 2 | `SentinelArrays.ChainedVectorIndex`: `(::Type{T})(x::ChainedVectorIndex) where T<:Union{Signed,Unsigned}` | ~180 children across `Tuple{Type{Int64}, Integer}` backedges (incl. `Array` ctor, 48) | New integer constructor invalidates `Integer`-typed call sites; consider `convert` specificity or annotate hot Base callers |
| 3 | `DataStructures.values(::Accumulator)` → `PrettyTables._preprocess_data(::AbstractDict)` | 210 children | Type-annotate/concretize `_preprocess_data` in PrettyTables so `values(::AbstractDict)` isn't a vulnerable abstract call |
| 4 | `REPL.REPLCompletions`: `Compiler.InferenceParams(::REPLInterpreter)` | Largest tree in BOTH packages (`get_max_methods` alone: 396 children) | **Track A (Julia stdlib)** — deferred to Phase 3; check JuliaLang/julia issue tracker first, likely known |

**Execution order**: start with #1 (JSON.jl — smallest surface, clear reproduction,
active maintainers), then #3 (PrettyTables). #4 is the Phase 3 core on-ramp.

**Acceptance criteria per PR**: (a) upstream issue checked/opened first;
(b) `bench/toptrees.jl` shows the tree eliminated or reduced ≥ 80% with the patched
package `Pkg.develop`ed; (c) no TTFX regression in `bench/run.sh`; (d) follows
`contribute.md` discipline: feature branch, atomic commits, DCO sign-off, tests.

## 5. Phase 3 (later): graduate to core (Track A)

Set up a `JuliaLang/julia` source build with `Make.user`
(`WITH_CCACHE=1`, debug build) per `readme.md`, and target method-invalidation /
startup-latency issues in core.

## 6. Role of this repo

Mission control: reference docs (`readme.md`, `docs/`, `contribute.md`), this plan,
the benchmark harness, and result logs. Not a docs-site project.
