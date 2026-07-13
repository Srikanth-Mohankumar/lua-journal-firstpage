# Lua Journal First Page

Experimental LuaLaTeX journal template for a fully automatic first-page layout followed by native two-column article flow.

## Goals

- No manual `\newpage`, `\twocolumn`, or `\finishfirstpage` command in article sources.
- Journal-style first page with masthead, title, abstract panel, and author stub.
- Abstract and stub are measured independently and may continue automatically.
- Long introductory paragraphs may break at line level.
- Native LaTeX two-column flow after front matter.
- Floats are intentionally out of scope for this first phase; the project is designed to integrate later with deterministic Lua float reservation.

## Quick start

```bash
make example
make test
```

Compile an example directly:

```bash
lualatex -interaction=nonstopmode -halt-on-error examples/neopage-technical-article.tex
lualatex -interaction=nonstopmode -halt-on-error examples/neopage-technical-article.tex
```

## Status

Research prototype. Not production ready. The repository includes a regression corpus for long title, long abstract, long stub, long single paragraph, lists, equations, and long article content.
