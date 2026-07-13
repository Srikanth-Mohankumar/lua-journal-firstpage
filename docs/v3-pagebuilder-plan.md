# V3 page-builder implementation plan

This branch starts the node-level implementation needed to remove the paragraph-boundary limitation.

## Current milestone

The Lua module now observes `pre_linebreak_filter`, `post_linebreak_filter`, `buildpage_filter`, and `pre_output_filter`. It records paragraph counts, generated line counts, page-builder activity, and shipped pages without modifying content.

## Required transition algorithm

1. Build the special title, abstract, and stub geometry.
2. Determine the exact article depth remaining below the abstract.
3. Let TeX line-break opening paragraphs at the first-page main-region width.
4. Retain fitting line boxes for page 1.
5. Recover source material for the unconsumed part of a crossing paragraph.
6. Re-line-break only that remainder at normal column width.
7. Hand control permanently to native two-column output.
8. Validate that content order and identity are preserved.

Already-broken line boxes cannot simply be transferred when page-1 and page-2 widths differ; the crossing remainder must be re-line-broken.

## Front-matter continuation

Abstract and author-stub content are independent streams. Abstract continuation has semantic priority over article body content. Keywords stay attached to the abstract. Stub continuation reserves measured space at the top of the right column and does not globally block the article body.

## Out of scope

Floats remain excluded. The deterministic float prediction and reservation mechanism will be integrated only after text-only pagination passes all regressions.
