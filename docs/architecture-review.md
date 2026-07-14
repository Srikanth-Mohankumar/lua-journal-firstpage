# Architecture Review: Transactional First-Page Engine

Reviewed branch: `feature/transactional-firstpage`

## Summary

The branch now implements a genuine one-shot transactional first-page engine rather than a paragraph-boundary page switch.

The current architecture is suitable as a strong research prototype:

- article sources contain no page-specific handoff commands;
- the original article page list and author-stub stream remain untouched during staging;
- transaction-owned copies are split and validated;
- commit occurs only after exact-once, source-order validation;
- rollback restores the untouched original inputs and fails closed;
- a paragraph may cross the first-page/native-page boundary at a legal line break;
- long abstract and author-stub streams have independent continuation policies;
- native LaTeX two-column output resumes after the first-page commit.

![Transactional first-page architecture](architecture-diagram.svg)

## Architectural strengths

### Transaction ownership

The implementation separates source-owned input material from transaction-owned scratch material. The article page and stub boxes are copied before splitting, and originals are cleared only after validation succeeds.

This is the correct base model for a production pagination engine because a failed transaction cannot partially consume the source stream.

### Width-aware crossing paragraphs

Page-1 paragraphs are formed with a controlled `\parshape`: leading lines use the special first-page measure and the repeating tail uses native column width. The page builder therefore selects a legal interline breakpoint while the eventual remainder is already formed for the native column.

This avoids reconstructing source text from glyph nodes after line breaking.

### Validation ledgers

Lua assigns stable identities for lines, paragraphs, origins, marks and payload whatsits. The validator checks the partition for missing, duplicated and reordered material before commit.

Delayed writes, PDF destinations and LaTeX mark classes are explicitly included in transaction accounting.

### Fail-closed unsupported domains

First-page footnotes and active tagged-PDF metadata are rejected. This is preferable to silently producing incorrect insertion ownership, MCIDs or structure-tree ordering.

## Production risks and hardening work

### 1. LaTeX kernel compatibility

The implementation depends on internal kernel interfaces including `\@cclv`, `\@outputbox`, `\@outputdblcol`, `\@colht`, `\@colroom` and the mark-class update routine.

Actions:

- define an explicitly supported LaTeX kernel range;
- add a startup compatibility gate using `\fmtversion`;
- run CI against at least two supported TeX Live releases;
- fail with a clear diagnostic outside the validated range.

### 2. Wide-line estimate and retry exhaustion

The number of special-width lines is estimated using remaining vertical space and `\baselineskip`. Tall inline content, local font-size changes, displays and unusual line depth can make this estimate imperfect.

Actions:

- add a fatal retry-exhaustion diagnostic;
- include paragraph ID, split target, remaining height, retry count and offending line IDs;
- add regressions for tall inline boxes, local baseline changes and display mathematics near the split.

### 3. Boundary glue, kern and penalty accounting

Line, mark and whatsit identity is validated strongly. Discardable top-level glue, kern and penalty nodes should also receive a boundary-level structural check.

Actions:

- fingerprint an ordered window of top-level nodes around the split;
- compare node type, subtype and relevant dimensions before commit;
- keep the check lightweight so normal production runs are not slowed substantially.

### 4. End-document stub draining

The current emergency drain advances the document using artificial page material. This can produce short or blank pages for exceptionally long author stubs.

Actions:

- replace the fallback with an explicit continuation-page request;
- prove measurable progress on every drain cycle;
- add a regression where the stub occupies multiple continuation pages after the article body ends.

### 5. Abstract decoration isolation

The abstract panel is painted using per-line PDF literals so that it remains vertically splittable. This should remain isolated from the pagination transaction.

Actions:

- expose a decoration interface with `begin`, `line` and `end` operations;
- keep pagination independent of the PDF painting implementation;
- document future PDF/A and tagged-PDF requirements.

### 6. Integration contract for deterministic floats

The existing deterministic float reservation system and the stub continuation system both affect column room and column assembly.

Required ordering:

1. calculate front-matter or stub reservation;
2. calculate predicted-float reservation;
3. combine reservations through one shared column-room API;
4. build the article column;
5. inject reserved material;
6. validate total occupied height and missed slots.

Neither subsystem should overwrite `\@colroom` independently.

## Recommended milestone order

1. Kernel compatibility gate and CI matrix.
2. Retry-exhaustion diagnostics and difficult-line regressions.
3. Boundary-node structural signatures.
4. Replace emergency stub draining.
5. Define the shared reservation API.
6. Integrate deterministic floats behind that API.
7. Design separate ownership protocols for footnotes and tagged PDF.

## Readiness

- Research and architecture demonstration: **ready**.
- Prose-only automated regression use: **ready with documented constraints**.
- General production journal use: **not yet**.
- Float integration: **architecturally feasible after a shared reservation contract**.
- Footnotes and tagged PDF: **explicit production gates remain**.
