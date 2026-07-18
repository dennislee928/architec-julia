# Track A Dossier — REPL 載入引發編譯器自我無效化 (2026-07-17)

Status (updated 2026-07-18): **fix D1 implemented and committed**; validation
rebuild in progress.

- Local build of stock master completed: `1.14.0-DEV`, `usr/bin/julia` works.
- **Stock-master baseline measured**: `using REPL` invalidates **758 methods
  across 9 trees**; top trees are exactly the REPLCompletions interface
  extensions (`InferenceParams`, `get_inference_world`, `abstract_eval_globalref`)
  — root cause confirmed on master, not just 1.12.6.
- **D1 patch applied** on branch `avoid-absint-interface-invalidation`
  (commit `2dbb8d9`, DCO signed): cache `max_methods::Int` in
  `InferenceState`/`IRInterpretationState` at construction (constructor
  specializes on the concrete interpreter type); `get_max_methods(interp, sv)`
  reads the cached field — removing the vulnerable abstract
  `InferenceParams(interp)` callsite from hot abstract-interpretation paths.
  Patched `Compiler` package compiles and loads.
- Next: incremental `make` rebuild → re-measure `using REPL` invalidations →
  compare vs 758/9 → `make test-compiler`.

## 6. Validation results (2026-07-18, patched build)

**Mechanism validated; headline total needs the systematic follow-up.**

| Metric | Stock master | Patched (D1) |
|---|---|---|
| `using REPL` unique invalidated methods | 758 | 750 |
| `get_max_methods` in the `InferenceParams` tree | victim with huge cascade (396 children on 1.12.6) | **eliminated** |
| Children per victim in the `InferenceParams` tree | large cascades | **0 for every remaining victim** |

Interpretation:

1. **The pattern works**: moving the interface read into the concretely-specialized
   state constructor removed the `get_max_methods` victim entirely and collapsed
   the `InferenceParams` tree's cascade to zero-children leaves (the survivors are
   shallow `typeinf_edge` / `abstract_call_method` / `builtin_tfunction` instances
   that read *other* `InferenceParams(interp)` fields directly).
2. **Why the total barely moved**: the remaining bulk sits in the sibling trees of
   the same class — `get_inference_world(::REPLInterpreter)` and
   `abstract_eval_globalref` — which need the identical treatment (cache the
   interface-derived values in the state at construction). This is a mechanical
   but larger refactor: the natural upstream conversation is "should Compiler
   read AbstractInterpreter interface values through the inference state?", with
   this branch + these measurements as the evidence.
3. Correctness: **`make test-compiler` SUCCESS on the patched build** —
   539,410 passed / 0 failed / 50 known-broken in 9m22s, including the
   `Compiler/AbstractInterpreter` testset (the exact interface touched).

Branch: `avoid-absint-interface-invalidation` @ `2dbb8d9` (DCO signed) in
`~/Documents/GitHub/julia`.

## 7. Cloud confirmation (GHA run #2, 2026-07-18)

`.github/workflows/core-validation.yml` on ubuntu-latest, stock
`JuliaLang/julia@master`, 30m42s: `using DataFrames` invalidates
**2,364 methods across 56 trees**; the top tree is
`get_inference_world(::REPLInterpreter)` — the same AbstractInterpreter
interface class, confirmed cross-OS and via a different trigger package.
Artifact: `invalidation-report-master`.

**Continuation**: the systematic root-cure plan (inventory → atomic PR series
extending the D1 pattern to `inf_params`/`world`/`opt_params` → validation
gates → upstream flow) is specified in [`docs/PLAN-TRACK-A.md`](../../docs/PLAN-TRACK-A.md).

## 8. PR-2 implemented and measured (2026-07-18)

Commit `2f0ca85` (DCO): cache `world::UInt` in both inference states; add
`get_inference_world(sv::AbsIntState)`; swap the 18 callsites with a state in
scope (abstractinterpretation.jl ×14, typeinfer.jl ×4). Rebuilt and measured
(`using REPL`, macOS):

- world tree direct victims: **`abstract_call_gf_by_type` 0 (was 76 on the GHA
  stock report), `abstract_invoke` 0, `return_cached_result` 0**.
- 19 surviving victims = exactly the un-swapped entry-point class
  (`abstract_applicable`, `_hasmethod_tfunc`, `concrete_eval_invoke`,
  `method_table`, ctor instances) — PR-3 scope per
  [`docs/tracka-inventory.md`](../../docs/tracka-inventory.md).
- Remaining large tree: `InferenceParams` 66 victims (other field reads → PR-1
  extension); new small trees visible: `get_inference_cache` 15, `cache_owner` 6.
- Branch pushed to `dennislee928/julia @ avoid-absint-interface-invalidation` —
  run the GHA workflow with `julia_repo: dennislee928/julia`,
  `julia_ref: avoid-absint-interface-invalidation` for the cloud before/after
  vs stock's 2,364/56.
- `make test-compiler` on this build: **SUCCESS — 550,209 passed / 0 failed /
  50 known-broken in 8m19s**, including `Compiler/AbstractInterpreter`.

## 9. PR-1 extension + PR-3 implemented and measured (2026-07-18)

Commits `eff8ddf` (cache full `InferenceParams`, consolidating the max_methods
field) and `1ac0b5b` (cache `InferenceCache`, `cache_owner`, `method_table`;
swap tfuncs world sites), both DCO-signed. One bootstrap failure caught and
fixed en route: `get_inference_cache` returns the new `InferenceCache` struct
on master, not `Vector{InferenceResult}` — the package-context compile check
does not exercise state construction; only a full bootstrap does.

Measured (`using REPL`, macOS), the full series:

| Build | Unique invalidated | Trees | InferenceParams victims | world victims | inf-cache tree |
|---|---:|---:|---:|---:|---:|
| Stock master | 758 | 9 | (large cascades) | ~130 class | present |
| D1 | 750 | 10 | 0-children leaves | — | present |
| PR-2 | 751 | 9 | 66 | 19 | 15 victims |
| **PR-1ext + PR-3** | **648 (−14.5%)** | **8** | **18** | **13** | **eliminated** |

Remaining victims are exactly the documented no-state-in-scope class
(`find_method_matches` kwarg defaults, `force_const_prop`,
`abstract_eval_partition_load` with `interp::Union{Nothing,...}`, entry points,
`types.jl` cache helpers) plus `cache_owner` cross-frame comparison sites —
each requires either a signature change or acceptance; see
`docs/tracka-inventory.md`.

**PR-4 resolved by measurement**: `abstract_eval_globalref` tree = **0 victims**
on this build — per the decision rule in `docs/PLAN-TRACK-A.md` §2.1 (proceed
only if > 10), adopt Option 3: no code change; record the parameterization
design in the upstream issue.

## 1. Measured symptom (this repo's harness)

Loading **any** of CSV / DataFrames / Plots in a fresh Julia 1.12.6 process
triggers the insertion of

```
Compiler.InferenceParams(interp::REPLInterpreter)
  @ REPL.REPLCompletions stdlib/v1.12/REPL/src/REPLCompletions.jl:535
```

whose invalidation tree is the **largest we measured in both packages**
(`bench/results/toptrees-{DataFrames,Plots}.txt`), including:

- `Compiler.get_max_methods(::AbstractInterpreter)` — **396 children**
- `Compiler.abstract_eval_partition_load(...)` — 87 children
- `Compiler.typeinf_edge(...)`, `bail_out_const_call(...)`, `force_const_prop(...)` — dozens more

i.e. **the compiler invalidates itself** whenever REPL loads. The same applies to
any package defining an `AbstractInterpreter` (JET, Cthulhu, GPUCompiler, …).

## 2. Root cause (core source, JuliaLang/julia @ master clone)

- Victim callsite: `Compiler/src/inferencestate.jl:1312`

  ```julia
  get_max_methods(interp::AbstractInterpreter) = InferenceParams(interp).max_methods
  ```

  This method is compiled **during sysimage bootstrap** specialized at the
  abstract signature `(::AbstractInterpreter)`. At that point the only matching
  method for `InferenceParams(interp)` is `NativeInterpreter`'s, so inference
  devirtualizes and registers a method-table backedge on the abstract signature
  `Tuple{Type{InferenceParams}, AbstractInterpreter}`.

- Trigger: `REPL/src/REPLCompletions.jl:535` (and identically JET/Cthulhu/…)
  **must** define `CC.InferenceParams(::REPLInterpreter)` to implement the
  documented `AbstractInterpreter` interface — the extension is not at fault;
  the interface's design guarantees this collision.

- `get_max_methods` is reached from `abstract_call_gf_by_type` and friends, so
  invalidation propagates through a large fraction of the compiled compiler
  (the 396-children tree), which must then be re-inferred lazily — start-up
  rework precisely when the user starts typing (completion latency).

## 3. Negative result worth keeping (lab/core-experiment/mechanism.jl)

A minimal reproduction — abstract interface + single concrete method +
`invoke`-forced abstract specialization + late method insertion — produces
**zero** invalidations on stock 1.12. Conclusion: at *runtime*, 1.12's inference
does not register the vulnerable devirtualization backedge for a single
non-covering match; the vulnerable instances observed in §1 are artifacts of
**sysimage bootstrap inference** (different heuristic path). Any fix must
therefore be validated against a rebuilt sysimage, not a REPL session — hence
the local core build.

## 4. Candidate fixes (to validate on the local build)

| ID | Change | Trade-off |
|---|---|---|
| D1 | Cache `max_methods::Int` (and siblings read per-call from `InferenceParams(interp)`) in `InferenceState`/`IRInterpretationState` at construction; `get_max_methods(interp, sv)` reads the cached field. Shrinks the set of compiled instances holding the vulnerable abstract callsite to the constructors. | Invalidation still occurs at ctor instances; win depends on transitive-dependent count — must be measured, not assumed. |
| D2 | REPL side: extend REPL's pkgimage precompile workload to re-infer the known-invalidated Compiler methods, so post-invalidation recompilation is cheap. | Treats symptom (rework cost) not cause (rework); robust and low-risk. |
| D3 | Sysimage build: compile the affected Compiler internals only at concrete `NativeInterpreter` signatures (function-barrier at the abstract entry points), so extension methods no longer intersect compiled instances. | Largest refactor; risks code-size growth per interpreter type. |

**Validation protocol** (once `make` completes): patched build → rerun
`bench/invalidations.jl DataFrames` against `usr/bin/julia` → compare tree count
and children vs the 2026-07-17 baseline; then `make test-compiler`.

**Cloud validation path**: `.github/workflows/core-validation.yml`
(repo: `dennislee928/architec-julia`) builds any julia fork/branch on GitHub
Actions (~1.5–2.5 h) and uploads an invalidation report artifact — use it for
long validation runs; local Apple Silicon `make -j8` for short iterations.
Note: julia's default branch is `master`, not `main` (first run failed on this;
the workflow now fails fast with a clear message on a bad ref).

## 5. Upstream etiquette

Before any PR: search JuliaLang/julia issues/PRs for existing work on
"REPLInterpreter invalidations" / "AbstractInterpreter interface invalidation"
— this is a known-pattern area and may already have an owner. If open work
exists, contribute the measurement harness + data from this repo to that thread
instead of a competing patch (生態系貢獻的第一原則：先量測、後認領).
