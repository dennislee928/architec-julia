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
> **Phase 2.5 countermeasure lab COMPLETE (2026-07-17)** — all six lean principles
> implemented and measured in `lab/` (results: `lab/RESULTS.md`): sysimage kills the
> Plots user journey 7.1 s → 0.65 s; PrecompileTools workload cuts first-call
> 106.7 ms → 0.03 ms; juliac `--trim` yields a 1.1 MB / 130 ms executable; JET+Aqua
> gate live (and caught a real defect); 3-stage fail-fast CI green.
> **Track A root cause located in core source** (`Compiler/src/inferencestate.jl:1312`
> × `REPLCompletions.jl:535`) — dossier + candidate fixes D1–D3 in
> `lab/core-experiment/TRACKA-DOSSIER.md`; local core build running for validation.
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

## 4.5 Phase 2.5 (DONE 2026-07-17): countermeasure lab — all six lean principles

Implemented and measured in `lab/` (full numbers: `lab/RESULTS.md`):

| Lean principle | Artifact | Headline result |
|---|---|---|
| 避免冷啟動 Front-End Planning | `lab/sysimage/` (PackageCompiler + journey workload) | Plots journey 7.1 s → 0.65 s; load 5,978 → 0.6 ms |
| 持續整合 First-Run Study | `lab/LeanDemo/` PrecompileTools workload | first call 106.7 → 0.03 ms (~3,500×) |
| 限制 WIP | `lab/small-binary/` juliac `--trim=safe` | 1.1 MB executable, 130 ms startup (vs 462 MB sysimage) |
| 品質左移 Poka-Yoke | `lab/quality-gate/` JET + Aqua gate | 0 issues in package; gate self-test catches planted bugs; caught a real compat defect |
| 漸進驗證 Progressive Commissioning | `lab/ci.sh` stages 1→2→3 fail-fast | all green: static → unit → perf budget |
| 禁止 Big-Bang Closeout | same pipeline: per-stage gates, no end-of-line inspection | quality verified at every stage boundary |

Pain-point coverage: TTFP ✅ (sysimage + workloads) · memory/binary bloat ✅ (trim)
· static-quality ✅ (JET/Aqua gate) · ecosystem ✅ (upstream targets §4 + this repo's
harness as contribution evidence).

## 5. Phase 3 (STARTED 2026-07-17): graduate to core (Track A)

- `JuliaLang/julia` cloned to `~/Documents/GitHub/julia`; `make -j8` build running.
- Root cause of our largest measured tree located:
  `Compiler/src/inferencestate.jl:1312` (abstract `InferenceParams(interp)` callsite,
  devirtualized during sysimage bootstrap) × `REPL/src/REPLCompletions.jl:535`
  (mandatory interface extension) → compiler self-invalidation, 396-children tree.
- Negative result: runtime micro-repro shows the vulnerable backedges only arise in
  sysimage bootstrap inference — validation requires the rebuilt core.
- Candidate fixes D1 (cache `max_methods` in inference state), D2 (REPL pkgimage
  re-inference workload), D3 (concrete-only compilation barrier) with validation
  protocol: `lab/core-experiment/TRACKA-DOSSIER.md`.
- Upstream etiquette: search existing issues/PRs before claiming; contribute the
  measurement harness to any existing thread.

## 6. Role of this repo

Mission control: reference docs (`readme.md`, `docs/`, `contribute.md`), this plan,
the benchmark harness, and result logs. Not a docs-site project.
