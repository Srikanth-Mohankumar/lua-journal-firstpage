# V3 page-builder implementation plan

This branch starts the node-level implementation needed to remove the paragraph-boundary limitation.

## Current milestone

The Lua module observes four stages:

1. `pre_linebreak_filter` assigns a paragraph sequence.
2. `post_linebreak_filter` counts generated line boxes.
3. `buildpage_filter` records page-builder activity.
4. `pre_output_filter` records each page presented to the output routine.

This instrumentation is intentionally non-destructive. It establishes the measurements and regression signals required before ownership of page material is changed.

## Required transition algorithm

The production algorithm will use one uninterrupted article stream.

1. Build the special title, abstract and stub geometry.
2. Determine the exact first-page article depth remaining below the abstract.
3. Allow TeX to line-break the opening article paragraphs at the first-page main-region width.
4. At the page boundary, retain the fitting line boxes for page 1.
5. Recover the unconsumed source material for the crossing paragraph.
6. Re-line-break only that remainder at the normal column width.
7. Hand control permanently to native LaTeX two-column output.
8. Validate that content order and token identity are preserved.

A direct transfer of already broken line boxes is not correct when page-1 and page-2 widths differ. The crossing paragraph remainder must be re-line-broken for the normal column width.

## Front-matter continuation

Abstract and author-stub content are independent streams.

- Abstract continuation has semantic priority over article body content.
- Keywords remain attached to the end of the abstract.
- Stub continuation reserves measured space at the top of the right column.
- Article body begins only after the abstract stream is complete.
- A continuing stub does not block the body globally; it reduces only the targeted column room.

## Out of scope

Floats are excluded. The existing deterministic float prediction and reservation mechanism will be integrated only after text-only pagination passes all regressions.

## Acceptance tests

- A long opening paragraph crosses page 1 at line level.
- No source command identifies the page boundary.
- No missing, duplicated, or reordered words.
- Short and long abstracts compile.
- Short and long author stubs compile.
- The two-column handoff occurs exactly once.
- Repeated builds are pagination-stable.
