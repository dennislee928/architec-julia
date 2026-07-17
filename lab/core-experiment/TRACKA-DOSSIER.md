# Track A Dossier — REPL 載入引發編譯器自我無效化 (2026-07-17)

Status: root cause located in core source; candidate fixes assessed; empirical
validation blocked on the local core build (in progress at
`~/Documents/GitHub/julia`, `make -j8`).

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
