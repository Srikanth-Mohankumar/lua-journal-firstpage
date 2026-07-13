# Lua Journal First Page

Research implementation of a fully automatic LuaLaTeX journal first page followed by native two-column article flow.

## Current milestone

- No `\finishfirstpage`, manual `\newpage`, or source-level `\twocolumn` command.
- First-page masthead, title, abstract panel, author stub, rules, and flowing introduction.
- Native LaTeX two-column flow for the prose-only baseline.
- Lua diagnostics for paragraph processing.
- Regression corpus for long titles, long abstracts, a single long paragraph, and longer articles.
- Floats are intentionally excluded from this milestone.

## Build

```bash
make example
make test
```

Direct compilation:

```bash
TEXINPUTS=.:src//: lualatex -interaction=nonstopmode -halt-on-error examples/neopage-technical-article.tex
```

## Repository layout

- `src/tnqjournal.cls` — class and automatic front-matter layout.
- `src/tnqjournal.lua` — Lua diagnostics and callback foundation.
- `examples/` — realistic NeoPage technical article.
- `tests/` — focused prose-only regressions.
- `docs/` — architecture, state machine, and known risks.

## Status

Research prototype. The current branch establishes a compiling native-flow baseline. The next implementation milestone is the special first-page page-builder that keeps the reference design while supporting line-level continuation, multi-page abstract flow, and multi-page author-stub reservations. It must pass content-integrity, visual, footnote, tagging, and continuation tests before production use.
