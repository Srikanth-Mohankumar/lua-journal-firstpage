# Transactional first-page architecture

Status: design validated; measured prose-only core implemented in class v0.4
Target engine: LuaHBTeX 1.22.0 / TeX Live 2025
Target format: LaTeX2e 2025-06-01 patch level 1
Date: 2026-07-13

## 1. Decision summary

The first-page engine will be a one-shot output-routine transaction over TeX's
already line-broken main vertical list. It will not collect or switch at
paragraph boundaries.

The measured journal specification uses a 344pt page-1 main lane and an
approximately 249pt native column. A page-aware `\parshape` reconciles those
measures before line breaking: the lines that can still occupy page 1 are
formed at 344pt, and the repeating tail shape is native `\columnwidth`. TeX
still contributes individual line boxes, interline glue, and penalties to the
page builder. A single paragraph can be split after a legal interline
breakpoint without reconstructing its source or rebreaking its committed tail.

The streams have deliberately different ownership:

- the masthead and title are an immutable, measured page-1 header;
- abstract, keywords, and article prose form one ordered main-galley stream;
- the author stub is a separately measured side stream;
- TeX owns the current page and recent contributions;
- a transaction owns only deep copies and staged output boxes;
- LaTeX owns final page shipping and all native two-column pages.

The page-1 transaction is:

```text
main galley with page-1/native adaptive parshape
        |
        v
TeX page builder -> box 255 + engine-held contributions
        |
        v
deep-copy box 255 and author-stub source
        |
        v
split only the copies at legal vertical breakpoints
        |
        v
compose complete page-1 candidate and logical remainder
        |
        v
validate geometry, roles, order, and exactly-once accounting
        |
        +---- failure ----> flush copies; originals remain authoritative
        |
        v
commit staged boxes; requeue the staged article tail before existing contributions
        |
        v
ship through LaTeX's page machinery
        |
        v
restore native LaTeX two-column output
```

No article-source command marks the page boundary. `\maketitle` arms the
one-shot engine; it does not force a page or expose a continuation environment.

## 2. Requirements and scope

### 2.1 In scope

- automatic page-1 front matter;
- an automatic transition to native two-column composition;
- a page break inside a paragraph, between already formed line boxes;
- arbitrarily long abstract text, followed by keywords, followed by the
  Introduction;
- an independently measured, automatically continued author stub;
- content-integrity and transaction diagnostics;
- prose, headings, glue, penalties, marks, and delayed write-like nodes needed
  by ordinary prose.

### 2.2 Explicitly out of scope

- `figure`, `table`, `figure*`, and `table*` placement;
- footnote insertions during the first-page transaction;
- tagged-PDF structure repair;
- bidirectional page composition;
- arbitrary unsplittable objects taller than the available lane;
- post-linebreak source reconstruction or destructive paragraph reflow.

Float support must remain in the separate production float system. This module
will neither inspect float queues to place floats nor silently accept float
nodes on a transaction page. An unsupported insertion is a deterministic
pre-commit failure, never a reason to ship partially accounted material.

### 2.2.1 Footnote ownership protocol (fail-closed in v0.4)

Footnotes are not ordinary whatsits owned solely by the selected vertical
list. TeX's page builder extracts insertion material into `\footins`, maintains
insertion height and penalty state, and may split that material independently
of the paragraph line that carries its mark. The page-1 routine also bypasses
LaTeX's normal `\@makecol` footnote assembly. Copying only box 255 would
therefore be neither complete nor rollback-safe.

A future footnote transaction must stage, as one unit, the callout line, the
corresponding insertion nodes, `\footins` content, split-insertion state,
footnote rule/skip geometry, and hyperlink destinations. Validation must prove
callout/body pairing and exact-once order before either stream is committed.
Rollback must restore the insertion queue and all counters without executing a
write or destination twice. Until that protocol exists, `\footnote`,
`\footnotemark`, and `\footnotetext` fail immediately while page 1 is armed;
ordinary native-page footnotes remain LaTeX-owned after handoff.

### 2.2.2 Tagged-PDF ownership protocol (fail-closed in v0.4)

Tagged PDF adds authoritative state outside the node list: structure elements,
parent-tree entries, marked-content sequences, MCID allocation, sockets, and
artifact decisions. A copied literal or boundary node is not an independent
copy of that structure state. Splitting and shipping a scratch list could
therefore leave dangling structure references even when the visual PDF is
correct.

A future tagged transaction must journal structure events without allocating
final MCIDs, classify the masthead/rules/panel as structure or artifacts,
associate article and author-lane content with distinct logical owners, and
allocate/commit parent-tree entries only after the visual transaction passes.
Rollback discards the journal and must leave the global structure tree
unchanged. The current profile rejects active `\DocumentMetadata` rather than
claiming partial conformance.

### 2.3 Interpretation of “native two-column” and stub continuation

Page 1 is the only page with the masthead/title/two-lane special page template.
From page 2 onward, the article is broken into columns by TeX and assembled by
LaTeX's stock two-column output path.

There is one necessary qualification. A stub that is taller than page 1 must
occupy physical space somewhere. To reconcile “continue the stub,” “do not
block article flow,” and “native two-column continuation,” the proposed policy
is:

- article text starts on page 1 without waiting for the stub to finish;
- a stub remainder is reserved at the top of the right column on subsequent
  pages;
- article text continues concurrently in the full left column and below the
  reserved stub fragment in the right column;
- the stock two-column page assembly remains in control; a narrow column hook
  temporarily adjusts only the right-column goal and prepends the measured
  stub fragment;
- as soon as the stub is exhausted, the hook becomes inert and subsequent
  pages are unmodified native output.

“Independent” therefore means that stub completion is not a gate before the
abstract or article can flow. It cannot mean that an in-text stub consumes no
space. If “native” is intended to prohibit even this temporary right-column
reservation, then long-stub continuation and the page-1-only rule are mutually
incompatible; that policy would need to be changed before implementation.

## 3. Findings from TeX and LuaTeX

### 3.1 The page builder, not a paragraph callback, owns the break

TeX's main vertical list is divided into the current page and recent
contributions. Completed paragraphs arrive as a sequence of line `hlist`
nodes, interline glue, and penalties. Legal vertical breaks normally occur at
glue preceded by a non-discardable node, at a kern followed by glue, or at a
penalty. Consequently, a paragraph is not atomic once line breaking has
finished.

When TeX passes the best breakpoint, it places the selected prefix in the
output box and moves the remainder back ahead of recent contributions. This is
the behavior the design must preserve. `\pagetotal` is only updated when the
page builder is exercised, and `\pagegoal` is latched from `\vsize` when the
first box or insertion enters an empty page. Neither is a reliable trigger for
a paragraph-oriented layout switch.

### 3.2 LaTeX's two-column output is a two-cycle protocol

The LaTeX kernel first calls `\@makecol`, which moves box 255 into
`\@outputbox`, attaches configured footnote/float areas, and packs the column.
`\@outputdblcol` then saves the first column in `\@leftcolumn`; on the second
cycle it combines the two columns and calls `\@outputpage`.

The page-1 engine must finish before the first-column save protocol begins.
After its one page is shipped it must restore all of the following coherently:

- the saved output token list;
- `\if@firstcolumn` to the first-column state;
- `\@colht`, `\@colroom`, and `\vsize` to native values;
- LaTeX's page/column mark regions;
- the output penalty associated with any requeued material.

LaTeX 2025 provides `build/column/before`, `build/column/after`, and configurable
column-output sockets. Those are appropriate for the narrow post-page-1 stub
reservation. They are not sufficient to implement the page-1 transaction by
themselves, because the transaction must see raw page material before normal
column assembly commits it.

### 3.3 Callback selection

| Callback or hook | Proposed use | Explicit non-use |
|---|---|---|
| `post_linebreak_filter` | assign stable paragraph/line origin IDs; make abstract-panel line boxes independently splittable | never decide whether page 1 is full |
| `buildpage_filter` | trace page-builder events and state transitions | never mutate `page_head` or `contrib_head` |
| `pre_output_filter` | inspect and checksum the list about to become box 255 | never destructively split or replace the engine list |
| one-shot TeX output dispatcher | acquire box 255, invoke the Lua transaction, commit, and restore native output | never remain installed after its work is finished |
| `build/column/*` hooks | reserve/prepend a pending stub fragment in a native right column | never rebuild ordinary article columns |
| `pre_shipout_filter` | optional final assertion and diagnostics | never serve as the primary validator; rollback is too late there |

Callbacks will be registered through `luatexbase` with unique names. The
module will not call `callback.register` directly and thereby erase another
package's callback.

The LuaTeX manual warns that assigning one TeX box pointer to another does not
copy its list, and that `tex.lists` setters can violate engine expectations.
The design therefore requires `node.copy_list`/box copies for transaction
work and forbids direct mutation of the special page/contribution list heads.

## 4. Layout model

Let:

```text
T  = \textheight
W  = \textwidth
C  = native \columnwidth
G  = native \columnsep
F  = measured page-1 main width (344pt)
I  = measured page-1 left inset (23pt)
S  = W - I - F - G, the measured stub width
H  = measured masthead/title header height including its trailing gap
A  = T - H, the available page-1 lane height
```

The invariant `2C + G = W` remains mandatory for native pages. Page 1 uses the
independently measured invariant `I + F + G + S = W`. Before each page-1
paragraph, the remaining vertical lane capacity determines how many leading
lines receive width `F`; the final `\parshape` entry has width `C` and repeats.
If fewer than four wide lines remain for a fresh paragraph, an internal
pre-line breakpoint moves that complete, already-native-width paragraph to the
next page. The output routine—not the paragraph hook—still chooses and commits
the physical page boundary.

The page-1 text area is composed as:

```text
+---------------------------------------------------+
| masthead / article metadata / measured title (W) |
+-------------------------+---+---------------------+
| abstract -> keywords -> | G | author stub prefix  |
| Introduction/body (F)   |   | (S)                 |
|                         |   |                     |
+-------------------------+---+---------------------+
```

The two lower lanes have independent natural heights and share only the
physical maximum `A`. A short stub does not push the Introduction downward. A
short main stream does not vertically center or stretch the stub.

### 4.1 Splittable abstract panel

The abstract cannot be a `\colorbox` around a `\parbox`, because that creates
one unsplittable vertical box. Instead:

1. page-1 abstract text is line-broken at `F - 2 * panel-padding`, with any
   continuation lines pre-formed at `C - 2 * panel-padding`;
2. each resulting line carries background coverage at its own formed width
   coverage and a stable `role=abstract` attribute;
3. top/bottom cap nodes are separate, accounted control nodes;
4. keywords use the same role and panel treatment;
5. the first Introduction line is emitted only after the keyword-end marker.

This keeps legal interline breakpoints. If the abstract crosses a page, its
next line remains the first main-galley item on page 2. The Introduction cannot
overtake it because all three are one source-ordered stream.

“Keywords stay attached to the abstract” is enforced as both ordering and
styling: the keyword block remains in the abstract role through its end marker,
and Introduction nodes are invalid before that marker. Normal widow/orphan
penalties can couple the final abstract line, keyword label, and first keyword
line without boxing an arbitrarily long keyword list.

### 4.2 Title overflow policy

The header is measured before the engine is armed. It must leave at least one
legal main-galley line plus the configured gap. A title/header that consumes
the whole text height is not silently scaled or clipped; it is a deterministic
preflight error. Multi-page titles are not a stated requirement.

## 5. State machine

| State | Meaning | Permitted next states |
|---|---|---|
| `UNARMED` | class loaded; no first-page request | `ARMED` |
| `ARMED` | `\maketitle` froze metadata, measured header/stub, and emitted abstract/keywords | `FIRST_BUILDING`, `FAILED` |
| `FIRST_BUILDING` | TeX is accumulating the ordinary main galley | `PREPARING`, `FAILED` |
| `PREPARING` | output fired; originals are frozen and copies are being split/composed | `READY`, `FIRST_BUILDING`, `FAILED` |
| `READY` | every validation passed; staged boxes require no further fallible transformation | `COMMITTING` |
| `COMMITTING` | register/list ownership is swapped exactly once | `STUB_PENDING`, `NATIVE`, `FAILED_FATAL` |
| `STUB_PENDING` | page 1 shipped; native article output active with an independent stub remainder | `STUB_PENDING`, `NATIVE`, `FAILED_FATAL` |
| `NATIVE` | stub empty; callbacks/hooks are observational or disabled | terminal normal document flow |
| `FAILED` | pre-commit failure; originals still owned by TeX/class | retry with a smaller legal target or stop with a package error |
| `FAILED_FATAL` | a post-commit invariant failed | terminate; never attempt a second commit |

Reentrancy is forbidden in `PREPARING`, `READY`, and `COMMITTING`. A callback
encountered in these states may record diagnostics but may not start another
transaction.

The engine will log every transition in a grep-friendly form:

```text
TNQ-FIRSTPAGE tx=1 state=PREPARING page=1 outputpenalty=10000
TNQ-FIRSTPAGE tx=1 main-input-lines=47 stub-input-lines=18
TNQ-FIRSTPAGE tx=1 main-page-lines=31 main-remainder-lines=16
TNQ-FIRSTPAGE tx=1 validation=pass missing=0 duplicate=0
TNQ-FIRSTPAGE tx=1 state=COMMITTING
TNQ-FIRSTPAGE tx=1 state=STUB_PENDING
```

## 6. Data flow

### 6.1 Preparation at `\maketitle`

1. Freeze metadata token lists so later assignments cannot change an active
   transaction.
2. Typeset and measure the immutable page-1 header at width `W`.
3. Typeset the author stub into a class-owned source vbox at width `S`.
4. Arm the one-shot output dispatcher after all separately owned page-1 boxes
   are ready.
5. Emit abstract start, splittable abstract/keyword lines, and abstract end
   directly into the main vertical galley under the adaptive `F`/`C` shape.
6. Return from `\maketitle`; ordinary body input follows with no source-visible
   page command.

Arming must precede emission of the abstract: an abstract longer than the
initial acquisition goal can invoke the output routine before `\maketitle`
returns.

The engine may initially acquire up to one native column of page material.
This bounds memory while ensuring there is normally enough material to split
at `A`. End-of-document output remains valid for a short article.

### 6.2 Transaction input

At the first ordinary output visit:

```text
O = original box-255 list selected by TeX
C = existing recent contributions already held by TeX
S = original class-owned author-stub list
P0 = original output penalty and mark-region state
```

`O`, `C`, `S`, and `P0` are read-only during preparation. `C` is never detached
or traversed destructively.

### 6.3 Working copies and split

```text
Wmain = deep copy of O
Wstub = deep copy of S

(Mpage, Mtail, Mdiscard) = legal vertical split(Wmain, A)
(Spage, Stail, Sdiscard) = legal vertical split(Wstub, A)
```

The split uses TeX/LuaTeX vertical-breaking semantics (`tex.splitbox` or an
equivalent split over scratch box registers), including penalties, maximum
depth, and split-top handling. It does not cut a line `hlist` in half.

The logical next-page sequence is:

```text
Mtail ++ original C
```

not `C ++ Mtail`. At output-routine exit TeX normally places vertical material
created by the output routine before held-over contributions. The commit uses
that mechanism rather than writing `tex.lists.contrib_head` directly.

A `\vsplit` is not byte-preserving: leading discardable glue/penalties can be
pruned and `\splittopskip` can be introduced. “Exact remainder” therefore
means exact semantic payload, source order, and TeX-correct vertical-break
semantics. The ledger separately records sanctioned control-node replacement;
all line boxes and side-effect nodes must partition exactly.

### 6.4 Candidate composition

The complete candidate is built off to the side:

```text
Candidate = vbox to T {
    Header
    HeaderGap
    hbox to W {
        vtop to A { Mpage }
        hskip G
        vtop to A { Spage }
    }
}
```

No original list is unboxed into this candidate. The candidate, `Mtail`, and
`Stail` all exist simultaneously before validation begins.

### 6.5 Commit

Commit is a short, ordered, non-speculative section:

1. enter the reentrancy guard;
2. install the already validated candidate in `\@outputbox`;
3. empty the original output box without shipping it;
4. place staged `Mtail` plus the restored original break penalty on the output
   routine's internal vertical list, ahead of engine-owned `C`;
5. replace the class-owned stub source with `Stail`;
6. restore/reinsert mark information for the split regions;
7. restore the saved LaTeX output routine and native column dimensions;
8. set `\if@firstcolumn` to the native first-column state;
9. call LaTeX's page output machinery exactly once;
10. leave the output routine, allowing TeX to resume the page builder on the
    staged remainder.

The irreversible point is the call that ships `Candidate`. Every allocation,
split, pack, dimension check, and node-ledger comparison must finish before
that call. A failure after the ownership swap is fatal rather than an attempted
rollback over a possibly shipped page.

### 6.6 Rollback

Before commit, rollback consists only of flushing transaction-owned boxes and
clearing transaction-local tables. `O`, `C`, `S`, the saved output routine, and
LaTeX's column state have not changed, so no reconstruction is required.

A retry may reduce `A` to the previous legal breakpoint if a candidate is
geometrically overfull. Retries are bounded and must make monotonic progress.
If no legal line fits, the transaction reports the first unsplittable offending
node and stops. It never drops that node.

## 7. Ownership model

### 7.1 Ownership table

| Object | Owner before prepare | Owner during prepare | Owner after commit |
|---|---|---|---|
| current page / box 255 (`O`) | TeX | TeX, read-only | emptied and released |
| recent contributions (`C`) | TeX | TeX, untouched | TeX, after staged `Mtail` |
| header source | class | class, read-only | class until document end |
| stub source (`S`) | class | class, read-only | replaced by staged `Stail` |
| working lists | none | transaction | candidate/remainder or flushed |
| page-1 candidate | transaction | transaction | LaTeX shipout path |
| native page-2+ columns | TeX/LaTeX | not applicable | TeX/LaTeX |

### 7.2 Node and box rules

- A node list has exactly one mutable owner.
- A TeX box pointer is never assigned as a supposed copy; lists are deep-copied.
- Detaching `box.list` transfers ownership and must be explicit.
- A node is freed only by its current owner and only once.
- Original page nodes are never mutated during prepare/validate.
- Stable origin IDs are copied with nodes and survive register/box changes.
- Pointer equality is not an integrity check across copied lists.
- `tex.lists.setlist` is forbidden for page, contribution, hold, and discard
  heads in this module.

### 7.3 Side effects and marks

Delayed writes, destinations, save positions, and similar whatsits are content
for accounting purposes. A copied node is safe only if the original alternative
is discarded before shipout, leaving exactly one committed instance.

Marks need additional treatment because TeX updates page mark state when it
fires the output routine for `O`, even if the transaction later chooses an
earlier split inside `O`. The design follows the modern `multicol` lesson:

- derive page/column mark regions from `Mpage`;
- derive reinsertion marks from `Mtail`;
- restore the page-1 region while `Candidate` is shipped;
- reinsert the tail marks with `Mtail` so the next native column sees the
  correct top/first/last values;
- test all active LaTeX mark classes, not only primitive class 0.

The original output penalty is likewise restored exactly once at the original
`O`/`C` boundary. This preserves later break behavior after the copied tail is
requeued.

## 8. Continued author-stub protocol

If `Stail` is nonempty after page 1, the state is `STUB_PENDING`.

For each native page while pending:

1. build the left article column normally at full native height;
2. transactionally split a copy of the stub remainder for the next right-column
   fragment;
3. reduce only the next right-column article goal by the measured fragment and
   its separation;
4. let TeX build the right-column article prefix at that reduced goal;
5. prepend the staged stub fragment to the right `\@outputbox` using the
   column hook/socket and repack to the normal column height;
6. validate and replace the stub source with its staged remainder;
7. let stock `\@outputdblcol` assemble and ship the page.

The article's source order is unchanged: page 2 left-column article material
precedes page 2 right-column article material. The stub is a visually parallel
metadata stream with its own IDs and accounting domain. Tagged-PDF semantic
placement for that parallel stream is deliberately not claimed.

If a stub fragment consumes the full right-column capacity, the right column
contains only that fragment for the page; article flow still made progress in
the left column. Once the stub is empty, native dimensions and hooks are
restored before the next column begins.

If the article galley ends while `Stail` is still nonempty, end-of-document
handling must not strand the side stream. The controller internally supplies
empty article columns and repeats the same measured right-column transaction
until the stub is exhausted, then lets LaTeX finish the document normally.
This is engine-owned continuation logic; it introduces no command into the
article source. Every forced continuation cycle must reduce the stub line count
and is bounded by that count, preventing a dead-cycle loop.

## 9. Validation and invariants

### 9.1 Pre-commit invariants

1. `A > 0` and all candidate dimensions are finite.
2. `width(Header) <= W`; every line in `Mpage` has width `F`; every line in
   `Mtail` has width `C`; and `width(Spage) <= S`.
3. Candidate natural height/depth fits `T` within a one-scaled-point tolerance.
4. Every main-stream line origin in `O` occurs exactly once in `Mpage` or
   `Mtail`.
5. Every stub line origin in `S` occurs exactly once in `Spage` or `Stail`.
6. Origin IDs are strictly source-monotonic within every destination.
7. No ordinary content origin is classified as discarded control material.
8. Every delayed side-effect origin has exactly one committed destination.
9. `Introduction` cannot occur before the abstract/keyword end origin.
10. No float or unsupported insertion is present.
11. No working box aliases an original box list.
12. The saved output routine and native dimension snapshot are complete.

### 9.2 Post-commit assertions

- page 1 ships exactly once;
- box 255 is empty when the output routine returns;
- state is `STUB_PENDING` or `NATIVE`;
- `\if@firstcolumn` is true;
- native `\@colht`, `\@colroom`, `\vsize`, `\columnwidth`, and `\hsize` agree;
- the staged main remainder precedes the pre-existing contribution head;
- no page-1 callback can initiate a second page-1 transaction.

### 9.3 Accounting record

Each transaction emits a compact ledger:

```text
TNQ-ACCOUNT tx=1 domain=main input=812 page=533 remainder=271 control=8 missing=0 duplicate=0
TNQ-ACCOUNT tx=1 domain=stub input=146 page=101 remainder=41 control=4 missing=0 duplicate=0
TNQ-ACCOUNT tx=1 geometry header=143.2pt lanes=558.4pt total=701.6pt goal=701.6pt
TNQ-ACCOUNT tx=1 commit=yes
```

Counts are based on stable origin IDs, with separate totals for ordinary
payload, side effects, and sanctioned split-control transformations.

## 10. Requirement traceability

| Requirement | Design response | Validation |
|---|---|---|
| no source-level page commands | `\maketitle` only arms internal state | static source scan |
| line-level paragraph continuation | split the vertical line-box list at legal TeX breakpoints | one long paragraph with per-line IDs and numbered text tokens |
| no loss or duplication | immutable originals plus origin-ID partition ledger | node ledger and `pdftotext` exact-once checks |
| automatic page transition | one-shot output dispatcher restores stock two-column state | transition log and page-2 geometry assertion |
| long abstract | abstract is a splittable prefix of the main galley | abstract spanning 2 and 3 pages |
| abstract before Introduction | single source-ordered main stream plus role invariant | marker order in node log and extracted text |
| keywords attached | keywords retain abstract role through end marker | break-before/during-keywords cases |
| long author stub | independent transactional side stream with right-column continuation | short, exact-fit, two-page, and three-page stub tests |
| stub does not gate article | article flows in page-1 main lane and later left columns concurrently | verify article tokens on every stub-continuation page |
| page 2+ native two-column | stock page builder/output assembly; only pending-stub right-column reservation is active | compare post-stub pages against no-stub native reference |
| floats ignored | no float algorithm; explicit unsupported-node guard | expected-error transaction with a float marker |
| deterministic behavior | no timing decision based solely on transient `\pagetotal` | repeated-build normalized PDF/text/ledger hashes |
| footnotes/tagged PDF | separate ownership protocols; current profile fails closed | expected-error protocol-gate tests |

### 10.1 Production-hardening regression set

- short article ending on page 1;
- exact page-1 fit;
- one long paragraph crossing after several lines;
- page-1 break at paragraph glue and at interline penalty;
- long abstract with Introduction beginning on page 2;
- long abstract with keywords close to a break;
- short, exact-fit, and multi-page author stubs;
- a short article whose stub continues after all article text is exhausted;
- long abstract and long stub simultaneously;
- headings and marks on both sides of the transition;
- delayed write/destination on both sides of the transition;
- forced validation failure proving rollback leaves originals unchanged;
- unsupported insertion proving failure occurs before commit;
- post-stub native-output comparison;
- two identical builds proving deterministic ledgers and extracted text.

## 11. Existing implementations reviewed

### TeX page builder and output routine literature

- Victor Eijkhout's *TeX by Topic*, chapters 27–29, documents the current
  page/recent-contribution split, legal vertical breakpoints, `\vsplit`, output
  penalties, marks, and output-box obligations. This is the basis for using
  line boxes and for restoring a tail ahead of recent contributions.
- The LuaTeX reference manual, sections 8.7, 9.5, and 10.3, defines deep node
  copying, packing/dimensions, page-building callbacks, `pre_output_filter`,
  `tex.splitbox`, box-pointer hazards, and special list heads.
- The LaTeX kernel's `ltoutput.dtx` defines `\@makecol`, `\@opcol`,
  `\@outputdblcol`, output dimensions, marks, and the 2025 column hooks and
  sockets that this design must cooperate with.

### Comparable implementations

- LaTeX `multicol` demonstrates repeated `\vsplit`, reinsertion of the unused
  tail, explicit output-penalty restoration, and—critically—modern mark-region
  reconstruction. It also demonstrates why insertions and output-routine
  coexistence need explicit scope limits.
- `lua-widow-control` demonstrates stable line/paragraph attributes, saved
  copies, `post_linebreak_filter` instrumentation, `pre_output_filter`
  intervention, and exactly-once handling for lines moved to the next page. Its
  complex insertion recovery is evidence for excluding footnotes from this
  milestone rather than pretending they are ordinary nodes.
- The local Wideband project demonstrates the requested copy/split/validate
  mindset, packaged-column marker measurements, and deterministic fallback. It
  also shows the risk of replacing `\@outputdblcol` and of making early
  decisions from `\pagegoal-\pagetotal`; this project will use a one-shot
  dispatcher and narrower native-column hooks instead.
- `cuted` and `ltxgrid` demonstrate that mid-page grid changes require broad
  output-routine ownership, mark/insert handling, and compatibility dispatch.
  They are useful precedents but are intentionally broader than this
  prose-only, first-page-only problem.

## 12. Risks and design gates

### Gate A: line width

Moving a formed 344pt line into a 249pt native column is forbidden. The
adaptive shape must therefore establish the width transition before TeX breaks
the paragraph. Pre-commit width accounting rejects any wide line in `Mtail` or
native-width line in `Mpage`. The implementation never fixes a mismatch by
scaling, clipping, unpacking, or reconstructing line contents.

### Gate B: author-stub policy

The right-column reservation policy in section 2.3 is the only interpretation
found that lets an arbitrarily long in-text stub continue while article text
also progresses and the normal two-column page builder remains responsible for
article columns. A stricter “no modification whatsoever after page 1” policy
would require either bounding the stub, moving its remainder outside the text
area, or relaxing continuation.

### Gate C: marks

Shipping a prefix copied from a larger box-255 selection without reconstructing
mark regions would make page-2 top marks incorrect. Mark reconstruction is not
optional even if the current sample page style displays no running marks.

### Gate D: split control nodes

Exact semantic remainder does not mean identical glue/penalty nodes. TeX's
vertical split intentionally prunes discardables and adds split-top glue. Tests
must distinguish payload loss from valid page-break normalization.

### Gate E: rollback timing

All validation must occur before `\@outputpage`. `pre_shipout_filter` is too
late to be the main transactional decision point.

### Gate F: unsupported insertions and tagging

Floats, footnotes, and tagged-PDF structures must not be silently accepted.
They require separate ownership/accounting protocols. This design is validated
only for the stated prose-only milestone.

## 13. Validation conclusion

The design satisfies the stated prose-only requirements under two explicit
interpretations:

1. the page-aware paragraph shape forms page-1 lines at the measured 344pt
   width and any continuation at native column width before the transaction;
   and
2. “native page 2+” permits a temporary, measured right-column reservation
   while an overlong independent author stub is pending.

The most important requirement—breaking an open paragraph at line level—is
met by operating after TeX has formed line boxes and by splitting the vertical
page list at TeX-legal breakpoints. The original page and side-stream lists
remain unchanged until validation succeeds. The proposed ownership and commit
protocol gives every payload node exactly one destination and restores the
main remainder ahead of existing contributions before native two-column output
resumes.

Implementation followed this conclusion: the baseline `\twocolumn[...]` title
box was removed, and the paragraph callback is used only for stable origins and
line-local decoration—not as the page-boundary decision maker.

## 14. Implementation record

Class v0.4 implements the core prose-only path and measured URP visual profile
described above:

- `\maketitle` measures the immutable header and independent stub, installs a
  one-shot output routine, and emits the abstract into the ordinary galley;
- the first output visit copies box 255 and the stub source, splits only those
  copies with TeX's vertical splitter, and validates line, unified-origin,
  mark, write, destination, and other-whatsit partitions;
- a successful transaction ships the staged page, restores the exact main tail
  ahead of contributions, and restores the saved LaTeX output routine;
- failed validation takes a non-committing rollback branch: transaction-owned
  boxes are discarded and the untouched original page list is requeued;
- abstract lines receive zero-net-width PDF background decorations inside their
  individual line boxes, preserving legal interline breakpoints;
- the adaptive paragraph shape reconciles the measured 344pt first-page lane
  with approximately 249pt native columns, and `TNQ-WIDTH` rejects a line on
  the wrong side of that transition;
- paragraph-origin intersections prove when one paragraph spans the page-1
  split; the ledger compares the complete origin sequence as well as frequency,
  while unique tokens extracted from the PDF check payload exactly once;
- LaTeX mark-class structures are rebuilt from the committed article fragment,
  with the article lane—not the author stub—owning running-head state;
- output-time running matter is excluded from abstract decoration state, so a
  metadata stream continuing beyond page 2 cannot decorate or misclassify page
  headers;
- the stock `\@outputdblcol` assembler remains the page-2+ owner. A pending stub
  temporarily shortens only a right-column goal and is transactionally prepended
  to that column; the hook becomes inert when the stub is exhausted;
- end-of-document draining supplies internal empty article columns when the
  article finishes before the independent stub.

The automated suite now covers the production-hardening items applicable to the
prose milestone: forced rollback fingerprints, exact page/keyword/stub limits,
paragraph-to-list handoff, active LaTeX mark classes and running heads, delayed
writes/destinations/other whatsits, normalized deterministic hashes, measured
visual-reference anchors/colors, three-page abstracts, and headings near
transaction/native splits. Footnotes and tagged PDF remain separate,
fail-closed protocols as specified in sections 2.2.1 and 2.2.2.

### 14.1 Spec-only visual audit

The supplied published article PDF is now the authoritative visual reference.
It is a 1269 × 1653 pixel page image embedded in a 609.12 × 793.92 pt PDF, so
measurements were made at its native 150 dpi. The handcrafted
`urp_flow_template_v6` was consulted only as a secondary dimensional
specification; no class code, page-building strategy, or output routine was
reused. At the user's direction, the logo, ORCID mark, and CC BY badge were
cropped from the published raster and are treated only as approved visual
assets. Content-dependent heights remain dynamic: the abstract background
grows and splits with its ordinary line boxes.

| Area | Reference measurement | Implemented measurement |
|---|---:|---:|
| media box | 609.12 × 793.92 pt | 609.12 × 793.92 pt |
| page-1 main-lane text x | 69.74 pt | 69.74 pt |
| title top (published four-line title) | 121.44 pt | 120.98 pt |
| abstract label x | 81.12 pt | 81.00 pt |
| abstract label y | 228.00 pt | 225.67 pt PDF text bound; 228.00 pt raster ink |
| abstract panel top | 215.04 pt | 215.04 pt |
| abstract panel left/right | 69.60 / 412.32 pt | 69.60 / 411.84 pt solid fill |
| author lane x | 438.24 pt | 438.09 pt |
| author lane first text top | 377.28 pt | 377.16 pt |
| correspondence text top | 600.00 pt | 600.30 pt |
| citation text top/bottom | 681.60 / 745.00 pt | 681.20 / 747.72 pt |
| page-2 running-head top | 42.72 pt | 42.7 pt |
| native left-column x | 42.84 pt | 42.84 pt |
| native right-column x | 312.0 pt | 312.0 pt |
| native column gutter | 18 pt | 18 pt |

The exact publication assets are defaults when present. The public
`\journallogo` and `\licensebadge` interfaces still permit replacement artwork;
code-generated fallbacks preserve the measured footprints when assets are not
installed. `verify-published-profile.py` renders test 019 at 150 dpi and checks
the artwork bounds, exact panel and rail colors, title and citation line breaks,
side-lane anchors, page rule, and minimum panel glyph coverage. It also inspects
the PDF resources for the `/Darken` blend state that prevents a later split-safe
background strip from repainting the preceding baseline.

## 15. References

- Victor Eijkhout, [*TeX by Topic*](https://mirrors.ctan.org/info/texbytopic/TeXbyTopic.pdf), chapters 27–29.
- LuaTeX project, [documentation and reference-manual guidance](https://www.luatex.org/documentation.html). The installed TeX Live 2025 manual matching the tested binary was also reviewed.
- LaTeX Project, [`ltoutput.dtx`](https://github.com/latex3/latex2e/blob/develop/base/ltoutput.dtx).
- LaTeX Project, [LaTeX2e News 41 / 2025-06-01 output-routine changes](https://latex3.github.io/news/latex2e-news/).
- Frank Mittelbach and the LaTeX Project Team, [`multicol` documented source](https://mirrors.ctan.org/macros/latex/required/tools/multicol.pdf).
- Max Chernoff, [`lua-widow-control` documentation](https://mirrors.ctan.org/macros/luatex/generic/lua-widow-control/lua-widow-control.pdf) and [source repository](https://github.com/gucci-on-fleek/lua-widow-control).
- Local Wideband investigation: `/data/neopage/repos/latex-wide-band/WIDEBAND-DIAGNOSIS.md` and `/data/neopage/repos/latex-wide-band/WIDEBAND-MULTIBAND-DESIGN.md`.
- Installed comparable package sources: `multicol.dtx`, `cuted.sty`, and `ltxgrid.dtx` from TeX Live 2025.
