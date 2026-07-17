# Implementation Plan (v2 — finalized after owner review)

> Status: **APPROVED SCOPE** — v1 assumptions were reviewed with the project owner
> on 2026-07-17. Decisions recorded in §2.

## 1. Project goal

Build a **bilingual (繁體中文 + English) documentation site** that serves as an
onboarding guide for developers who want to **contribute to the Julia language core**
(runtime, compiler, GC, build system). The four existing zh-TW documents are the
seed content.

## 2. Decisions from owner review

| Question | Decision |
|---|---|
| Deliverable | Documentation site (static, with nav + search) |
| Content focus | Contributing to Julia core / compiler internals (no toy demos) |
| Languages | Bilingual: Traditional Chinese (primary) + English |
| Constraints | Free rein: may rename/move files, add tooling, init git |

## 3. Architecture

- **Generator**: MkDocs + Material theme + `mkdocs-static-i18n` plugin.
  - Installed in a project-local `.venv` (no global pollution).
  - Markdown remains the source of truth → low-friction bilingual maintenance.
  - Material provides client-side search and a language switcher out of the box.
- **i18n layout**: suffix convention — `page.md` (zh-TW, default locale) and
  `page.en.md` (English) side by side.

## 4. Target repository layout

```
architec-julia/
├── README.md              # project purpose, quick start (bilingual)
├── CONTRIBUTING.md        # how to contribute to THIS docs project
├── plan.md                # this file
├── mkdocs.yml             # site config (theme, i18n, nav)
├── requirements.txt       # mkdocs deps, pinned
├── .gitignore             # .venv/, site/
└── docs/
    ├── index.md / index.en.md                  # landing page
    ├── 01-build-system.md / .en.md             # from old readme.md
    ├── 02-structure.md / .en.md                # from old docs/STRUCTURE.md
    ├── 03-implementation.md / .en.md           # from old docs/IMPLEMENTATION.md
    └── 04-contributing-to-julia.md / .en.md    # from old contribute.md
```

## 5. Work items

1. **Reorganize**: move the four docs into the numbered chapter layout above;
   the old `readme.md` / `contribute.md` are replaced by proper repo-level
   `README.md` / `CONTRIBUTING.md`.
2. **Translate**: produce full English versions of all four chapters
   (technical translation, keeping Julia/LLVM terminology exact).
3. **Site build**: `mkdocs.yml` with Material theme, static-i18n (zh-TW default,
   en secondary), navigation, search; verify `mkdocs build` passes cleanly.
4. **New repo docs**: bilingual `README.md` (what this project is, how to build
   the site) and `CONTRIBUTING.md` (style rules for both languages, how to add
   a chapter).
5. **Git**: `git init` + clean initial commit.
6. **Verify**: build the site and inspect the rendered output for both locales.

## 6. Out of scope

- Toy/demo code implementations (explicitly dropped in review).
- Hosting/deployment (GitHub Pages CI can be a follow-up).
- New chapters beyond the existing four.
