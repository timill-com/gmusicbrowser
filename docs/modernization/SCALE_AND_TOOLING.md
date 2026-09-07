# How far the GTK4 port actually is, and whether tooling would speed it up

Written 2026-09-08, at `gtk4-alpha` tip. Every figure here was re-derived on
that date by running the command beside it, not copied from another document.

This file exists because two questions came up that the other documents answer
only indirectly: **how far from a full GTK4 implementation are we**, and
**would more tooling and scripts move us faster**. The short answers are "much
further than the headline coverage figure suggests" and "yes, but only one
specific tool, and it will not change the order of magnitude".

`PROGRESS.md` remains the "where are we" view and is not superseded by this
file. This is the scale assessment and the tooling argument.

## 1. The distance, measured

| Measure | Value | Basis |
|---|---:|---|
| Widget instances rendering | 235 / 1161 (**20.2%**) | parser catalog walk |
| Distinct element names present in layouts | 8 / **103** | same walk |
| Container types | 8 / 15 | `%Layout::Boxes` |
| **Bundled layouts that render at all** | **4 / 76 (5%)** | headless render of every layout |
| `Gtk3::` references in production code | **1444** across 27 files | see `PROGRESS.md` |
| GTK4 code written | ~1,618 lines | `gmusicbrowser_gtk4*` |
| GTK3 code in the five main files | ~32,969 lines | `wc -l` |
| Decisions unresolved | **9 of 39** | D006–D012, D019, D039 |

### Why 20.2% is the most flattering number available

It counts **instances**, and the implemented widgets are the repetitive easy
ones — `Filler` alone is 94 of the 235. By distinct element *type* the figure is
**8 of 103**. Do not quote 20% as "a fifth done" without saying which basis it
uses; `PROGRESS.md` has a standing warning about exactly this.

### The number that reframes everything: 4 of 76

Rendering every bundled layout headlessly and recording the first thing that
stops each one gives **4 layouts that render** — `D_buttons`, `O_play`,
`O_stop_play_next`, `play_controls`, all tiny button strips — and 72 that stop.

**This is a better progress measure than instance coverage** because a layout is
what a user actually opens. A layout at 95% of its widgets is still a layout
that does not open.

### The GTK4 entry point is a proof harness, not an application

`gmusicbrowser_gtk4.pl` is **116 lines**. It has no music library, no playback,
and no configuration writer — just a toy `$playing` flag. Everything built so
far renders *layouts*; nothing plays a song. Subsystems with no GTK4 work at
all: the library and song model, playback, tag editing
(`gmusicbrowser_tags.pm`, 155 `Gtk3::` references), 17 of the 19 plugins, drag and
drop, configuration persistence, and the SongTree/SongList views that are the
application's signature.

### Position against the project's own roadmap

`ROADMAP.md` plans **8 milestones at roughly 14–24 person-months**. We are
finishing **M1** (feasibility) — the last three increments closed its input,
list-model and drawing gate rows — while some M4/M5 widget work has run ahead of
it. **M2 and M3**, the boundary and preparation milestones that account for most
of those 1444 references, are largely untouched.

**Overall: roughly 10–15% of the whole job.**

## 2. What the first-blocker measurement found

Ranked by how many bundled layouts each one stops from rendering at all:

| First blocker | Layouts stopped |
|---|---:|
| `MB` (menu bar container) | **15** |
| `SimpleSearch` | **11** |
| `Title` | 5 |
| `Title_by`, `Cover`, `SongTree` | 4 each |
| `VolumeIcon`, `TimeBar`, `@Small_player` | 3 each |
| `FilterPane`, `ArtistPic` | 2 each |
| 16 others | 1 each |

27 distinct first-blockers in total.

**`MB` is the single biggest unlock, and instance counting ranks it nowhere
near the top.** It has 19 declarations against `MenuItem`'s 99 instances, so
every previous priority list put `MenuItem` first. But `MB` is what 15 layouts
hit *before* they ever reach a `MenuItem`, and D038's menu interpreter is
already built and waiting behind it.

`@Small_player` appearing as a blocker is worth noting separately: it is an
embedded-layout reference (`@layout`), a feature listed as "not started at all".

**Caveat on this ranking:** it is the *first* blocker only. Fixing `MB` will not
render 15 layouts; it will move them to their next blocker, which is often
`MenuItem` or a list widget. The ranking says where to look, not what will
finish.

## 3. The tooling question

### Recommended: a layout coverage reporter

`tools/layout-coverage`, roughly 60 lines. A prototype was built and run to
produce the table in section 2, so this is a proven concept rather than a
proposal.

It works because **the renderer already tracks what it cannot handle** —
`Unhandled`, `UnhandledGlobals` and `UnhandledSizeGroups` exist and are
populated (`gmusicbrowser_gtk4_layout.pm:230-248`). The data is already being
produced; nothing aggregates it. The tool renders each layout in the catalog,
catches the failure, and reports:

- how many layouts render, and which;
- the first blocker for each, ranked;
- unhandled options across all layouts.

**Why it is worth building:**

1. **It directs work by evidence.** It found the `MB`-over-`MenuItem` result
   above, which four sessions of instance counting did not.
2. **It attacks this project's most expensive recurring failure.**
   `PROGRESS.md` records that roughly twenty-eight figures have needed
   correction across the last eight sessions, essentially all from grep-based
   counting. A tool that re-derives coverage by *running the renderer* cannot
   miscount in the ways grep does.
3. **It is a regression check.** A layout that renders today and stops
   rendering tomorrow is currently invisible.

Constraints: it must run through `tools/run-gtk4-smoke`'s environment (real
Wayland, isolated XDG), and it needs the offline doubles or the real bindings.
The prototype used the real bindings, which needs no extraction work.

### Also worth it, smaller: a single verification target

A `make check` bundling `test-modernization`, `test-gtk4`, `test-gtk3` and
`perl -c` on changed files. Verification is currently four commands, and the
GTK4 one must run outside the sandbox.

### Argued against: code generation or mass-porting scripts

`AGENTS.md` forbids a mechanical `Gtk3`→`Gtk4` replacement, and the last three
probes show concretely why that rule is right rather than merely cautious. The
binding refuses `CairoContext`, the graphene types, `GskRenderNode`,
`GtkExpression` and `GdkEvent`. Each refusal required a *design* answer:

- drawing became "render offscreen with Cairo, upload as a texture";
- sorting became "sort in Perl, rebuild the model";
- alignment became a constraint layout (D030).

A translation script would have emitted code that compiles and fails at
runtime — the worst outcome, because it looks like progress.

### The honest limit on tooling

**The bottleneck is not typing speed.** It is that ~33,000 lines of GTK3 logic
need decisions about what the GTK4 equivalent should be, on a binding that
keeps saying no. Better instruments help us *aim* better; they do not make the
work 5× faster. Anyone promising otherwise has not read D006's evidence list.

## 4. What would genuinely accelerate the port

Ahead of any script:

1. **Settle D039** (Proposed). It gates ~85 of the 99 `MenuItem` instances.
   Only 6 of 20 distinct `command=` values are registered, so today a `MenuItem`
   port would deliver **14 working items out of 99**. Widening `@Commands` is
   shared code and needs a GTK3 pass, so it wants one deliberate increment
   rather than five small ones.
2. **Settle the `FRONTEND_CONTRACT.md` extension.** Frozen for the first slice,
   and it gates the 157-instance song-field group. It also needs a fixture song
   source, since the GTK4 application has no library.
3. **Settle D010.** Both halves are now measured — option 1 performs, option 2
   is *unavailable* because no render node can be emitted — so it is ready to
   decide rather than probe.

Two of those three are decisions, not code. That is the real accelerator
available right now.

## 5. Suggested order for the next few increments

1. `tools/layout-coverage`. Small, no production code touched, and it validates
   or refutes the `MB` result before anything is built on it.
2. `MB`/`SM` containers, then `MenuItem` — but only after D039, so the menu
   items actually activate.
3. `SimpleSearch`, the second-largest blocker at 11 layouts.

## 6. How to re-derive section 1 and 2

	# instance coverage, distinct elements
	# (the full snippet is in PROGRESS.md, "How to re-derive these figures")

	# Gtk3:: references, production only
	for f in $(git ls-files '*.pm' '*.pl' | grep -v '^t/' | grep -v gmusicbrowser_gtk4); do
	  grep -o 'Gtk3::' "$f"; done | wc -l

	# layouts that render, and the first blocker for each
	# renders every layout in the catalog through the real bindings and
	# catches the die; must run with a real Wayland connection
	# -- this is what tools/layout-coverage should become

	# decisions
	grep -c '^## D0' docs/modernization/DECISIONS.md
	grep -A2 '^## D0' docs/modernization/DECISIONS.md | grep -c 'Status: \*\*Accepted\*\*'

**The 4-of-76 and first-blocker figures have no committed tool behind them
yet** — they came from a scratch prototype. Treat them as measured but not yet
reproducible from the repository until `tools/layout-coverage` lands. That is
the first reason to build it.
