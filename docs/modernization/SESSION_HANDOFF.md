# Session handoff

Status: the tree is clean. Two increments landed this session, both closing
default-level correctness gaps in already-rendered widgets:

1. The legacy `size=`/`relief=` button options, recorded as **D027**.
2. The legacy `Layout::Label` `xalign`/`yalign`/`ellipsize` options, recorded
   as **D028**.

Plus the correction of the previous handoff's `ToggleButton` recommendation.

Last session: 2026-09-07. Branch `gtk4-alpha`.

Read `MODERNIZATION.md` and `AGENTS.md` first. This file only records where the
previous session stopped and what the next one should verify before continuing.

## Read this before picking ToggleButton

The previous handoff recommended `ToggleButton` next, on the grounds that it is
"a `Layout::Button` variant, so it reuses `%Buttons`, `_CreateButton`, and
`_SetIcon` rather than adding a new shape". **That premise is wrong, and it was
checked this session before any code was written.**

`ToggleButton` is `Layout::TogButton` (`gmusicbrowser_layout.pm:602`, class at
`:3805`). It is a `Gtk3::ToggleButton` subclass, not a `Layout::Button`. It has
no `activate` and dispatches no command. Its entire purpose is showing and
hiding *another* layout widget: it reads `widget`, `togglegroup`, and `resize`,
and drives `::get_layout_widget`, `GetShowHideState`, `ShowHide`, and `Hide`,
plus a `::Watch($self,'HiddenWidgets',...)` subscription.

All **39** `ToggleButton`/`TogButton` option groups in `layouts/` carry
`widget=`. Not one is a plain toggle. Verified with
`grep -o 'To\(ggleButton\|gButton\)[0-9]*([^)]*)' layouts/*.layout` — 39
matches, 0 without `widget=`. So porting `ToggleButton` means porting the
layout show/hide subsystem first. That is a much larger unit than a `%Buttons`
entry, and it is not a button increment at all.

The same handoff also said `ToggleButton` "is the natural place to implement
the two-state `stock="on:... off:..."` form, which `LockAlbum` (22) and
`LockArtist` (22) also need". **Also wrong.** `ToggleButton` never uses that
form; no layout passes it a `stock=` at all. The six sites that do use it are
all `LockAlbum`/`LockArtist`, and those are `Layout::Button` with
`button => 0` — `GtkEventBox` forms, not buttons — whose widget-table `stock`
is already a hashref keyed by a `state` getter
(`gmusicbrowser_layout.pm:144-155`). The string form at `:3023-3032` only
*overrides* such a hash. Each state's value carries two icons and GTK3 shows
the second on `enter_notify_event`. So that form needs state, the `EventBox`
shape, and pointer hover — none of which is ported.

What the previous handoff got right is the other half of its recommendation:
`size=` and `relief=` were "the larger prize". That part was independent of
`ToggleButton` and is what this session did.

## Actual state of the port

The GTK4 work is an early spike, not a partly-finished migration. Do not assume
otherwise from the size of the planning documents.

- `gtk4-alpha` is 18 commits past `master`; the list is in the next section.
  Earlier handoffs said "ten" at `0074c06`, where the real count was 11 and the
  listed commits already numbered 11. Read the count from
  `git rev-list --count master..HEAD`, not from the prose.
- All 1,444 `Gtk3::` references are still present and unmodified across 27
  files. None has been ported. Verified against a `git archive` of `master`,
  which reports the same 1,444 and 27.
  A naive repository-wide grep now reports **1,447 across 28 files**, and that
  is not porting drift: `gmusicbrowser_gtk4_layout.pm` carries three `Gtk3::`
  mentions **in comments**, naming the GTK3 source of truth for a translation
  (`Gtk3::HBox->new`, `Gtk3::IconSize::lookup`, `Gtk3::Label::set_alignment`).
  That is the file's established convention. No GTK4 code loads Gtk3, and
  `t/04_Gtk4LayoutRenderer.t` asserts `!exists $INC{'Gtk3.pm'}`. Exclude
  `gmusicbrowser_gtk4*` when counting.
- GTK3 is the complete, working application (about 33,000 lines in the main
  modules). It is not a beta layer. The port direction is GTK3 to GTK4.
- The current branch is `gtk4-alpha`. A separate `gtk4` branch exists but points
  at the same commit as `master`.

## What is committed and what is not

Everything is committed. `gtk4-alpha` is **18** commits past `master`,
confirmed with `git rev-list --count master..HEAD`:

	80fcf7c docs: correct the commit count and reconcile the Gtk3 reference count
	9df79dc docs: record the landed commits in the handoff
	cf933af docs: record D028, and correct the markup usage count
	58d7cb3 gtk4: apply the legacy label alignment and ellipsize options
	20f676f docs: record the landed commits in the handoff
	a315171 docs: record D027, and correct the ToggleButton recommendation
	54b0a8f gtk4: apply the legacy button size and relief options
	0074c06 docs: record the session's landed commits in the handoff
	b85b89d docs: decide AB and WB, and cover AB alignment on real Wayland
	527eae9 gtk4: share one labels fixture across the renderer tests
	fc65354 gtk4: render Filler and apply the legacy size request
	6d30dcf gtk4: render the Next and Prev widgets
	4ed26ad gtk4: render the Stop widget from a stateless button table
	978bbdf gtk4: fall back to the -symbolic icon name
	e016554 gtk4: correct box packing geometry and resolve icons by theme name
	ec217bc initial gtk4 stubs
	d4c87d0 agents file
	774aa2e initial plan

Neither increment touched shared code. The `size=`/`relief=` one changed
`gmusicbrowser_gtk4_layout.pm`, `t/04_Gtk4LayoutRenderer.t`,
`t/gtk4/40_Icons.t`, `t/layouts/buttons.layout`, and `t/layouts/icons.layout`;
the label one changed `gmusicbrowser_gtk4_layout.pm`,
`t/04_Gtk4LayoutRenderer.t`, `t/gtk4/30_Box.t`, and added
`t/layouts/labels.layout`. Documentation is committed separately from code in
both cases.

No GTK3 production code, bundled layout, or file in `pix/` has been touched by
any increment on this branch. `gmusicbrowser.pl` is unmodified. No file has been
added this session; the earlier ones added `tools/run-gtk3-smoke`,
`t/RendererLabels.pm`, `t/layouts/sizing.layout`, and `t/layouts/align.layout`.

## This session, first increment: the legacy `size=` and `relief=` button options

The increment closes a correctness gap in the same class as `minwidth=` before
it: `Layout::Button` sets `relief => 'none'` and `size => SIZE_BUTTONS` in
`@default_options` (`gmusicbrowser_layout.pm:3001`), so both apply to **every**
button, not only where a layout names them. The GTK4 renderer implemented
neither, so every button it had already built was framed and theme-sized where
GTK3 draws it flat at 24px. Recorded as **D027**, status **Proposed**.

Both GTK3 APIs are gone in GTK4 and the replacements are not one-to-one:

- `gtk_button_set_relief` is removed. `set_has_frame` is the replacement, and
  `get_has_frame` reads back `1` and `''`, not `1`/`0`.
- `GtkIconSize` was cut to `inherit`/`normal`/`large`, measuring 16, 16, and
  32px. **Every legacy name is a fatal enum error through this binding**, not a
  warning: `set_icon_size('menu')` dies with `FATAL: invalid enum GtkIconSize
  value menu`. The enum cannot express the legacy set at all, since
  `large-toolbar` is 24 and `dialog` is 48.

So `size=` translates to `set_pixel_size`, which reproduces every legacy size
exactly. The pixel values were read from `Gtk3::IconSize::lookup` on
GTK 3.24.41 rather than assumed:

| legacy `size=` | GTK3 pixels | uses in `layouts/` |
|---|---:|---:|
| `menu` (`SIZE_FLAGS`) | 16 | 54 |
| `button` | 16 | 46 |
| `large-toolbar` (`SIZE_BUTTONS`) | 24 | 16 |
| `dialog` | 48 | 9 |
| `small-toolbar` | 16 | 4 |
| `dnd` | 32 | 0 |

That is the whole GTK3 icon-size set, and the first five are exactly what
appears in the bundled layouts, so **the translation is lossless** — unlike
D025's fractional alignment case. Mapping onto the three-valued GTK4 enum was
rejected as alternative 1 precisely because it is not.

Three details worth carrying forward:

- **Style the button's own image, not a replacement child.**
  `Gtk4::Button->set_icon_name` builds the `GtkImage` itself and `get_child`
  reaches it, so `set_pixel_size` lands there and `Button->get_icon_name` keeps
  working. Substituting an explicit `Gtk4::Image` child leaves
  `get_icon_name` undefined, which the renderer's own `_SetIcon`/
  `_SetPlayLabel` and every existing icon assertion depend on. Measured both
  ways before choosing.
- **`Total(size=small)` is not an icon size.** Five sites in
  `layouts/contrib.layout` use it; `Total` is a different widget and this is a
  font size. A naive `grep -o 'size=[a-z-]*'` also picks up `minsize=`,
  `picsize=`, and `ellipsize=end`, which is where an earlier reading of "37
  end" and "171 blank" came from. Use `[(,]size=` to isolate the real option.
- **An unrecognised `size=` is left to the theme and still reported.** It is
  not guessed at, and `%ButtonHandled` reports `size` conditionally on the
  value being in the mapping, so `Unhandled` stays honest.

### The vacuous-assertion trap this increment hit

A `measure()` check on an icon **only discriminates above 16px**. GTK4's own
default icon size is 16, so the `menu`, `button`, and `small-toolbar` rows
measure correctly even against a renderer that ignores `size=` entirely: three
of the nine measure assertions pass against pristine. `get_pixel_size` is what
actually pins those three, and the test now says so in a comment.

This is the same class of trap as the recorded `set_size_request` one — a
physical measurement that agrees with the expectation by coincidence rather
than because the option took effect. Both are in D006. The lesson generalises:
check every new physical assertion against pristine individually, not just the
file's failure count.

### Pixel size cannot be asserted offline

The offline doubles have no icon theme, so `_IconTheme` returns undef,
`_IconName` returns early, and **no icon resolves at all** — every button in
`t/04_Gtk4LayoutRenderer.t` falls back to a text label with no image to size.
Pixel-size assertions were written there first and had to be moved to
`t/gtk4/40_Icons.t`, where a real theme resolves the icons. What the offline
file can honestly prove is the relief default, the `Unhandled` bookkeeping, and
that a text-fallback button is not handed a stray image.

The doubles were extended to model the real behaviour rather than to satisfy
the test: `set_icon_name` now creates a `Gtk4::Image` child, `set_label`
removes it, and `Gtk4::Button` carries `has_frame` defaulting to 1, which is
GTK4's real default.

### Verification for this increment

- `t/gtk4/40_Icons.t` fails **16 of 74** against a pristine `git archive HEAD`
  with only the changed test files and fixtures overlaid, on real Wayland.
- `t/04_Gtk4LayoutRenderer.t` fails **5 of 160** offline against the same.
- Controls pass on both trees: `relief=normal keeps the frame`, the six
  `isa_ok` image checks, both unknown-`size=` assertions, and `a real widget
  reports the options it ignored`. The comparison discriminates rather than
  merely failing everything.
- No shared code changed. Only `gmusicbrowser_gtk4_layout.pm`, the two test
  files, and the two fixtures. `make test-gtk3` was run anyway and passes.

## This session, second increment: label alignment and ellipsize

Same shape as the first: a legacy `@default_options` value the renderer never
applied, so every widget it had already built was wrong by default.
`Layout::Label` sets `xalign => 0, yalign => .5`
(`gmusicbrowser_layout.pm:3105`) but **`Gtk4::Label` defaults to `xalign=0.5`**,
so every `Label` and `Text` was centred where GTK3 left-aligns it. Recorded as
**D028**, status **Proposed**.

Unlike the icon-size case, both translations here are trivial *and* lossless:

- GTK4 split the deprecated `Gtk3::Label::set_alignment` into
  `set_xalign`/`set_yalign`, which take the same float. Measured: 0.25 reads
  back as 0.25 in both toolkits. **This is the contrast with D025** — `AB`
  loses a fractional alignment to a three-valued `halign` enum, but a label's
  alignment is a float property in both toolkits.
- `ellipsize` is the same Pango enum in both, passed through unchanged.

Two values are filtered because an out-of-range enum is **fatal** through this
binding, and both stay reported through `Unhandled`:

- `ellipsize` outside the four Pango modes. Note `Layout::Button` maps `'1'` to
  `'end'` (`:3051`) but `Layout::Label` deliberately does **not**, so
  `ellipsize=1` on a label does not ellipsize in GTK3 either. The asymmetry is
  real and is preserved rather than tidied away.
- A non-numeric `xalign`/`yalign`. GTK3 accepts it with a Perl
  `isn't numeric` warning and coerces it to 0 — verified, not assumed — and
  since the legacy `xalign` default is also 0, falling back to the default
  reaches the same rendering.

`markup` (76 uses), `font`, `color`, and `minsize`/`expand_max` are deliberately
out of scope; see D028 alternative 3.

### Two of the new assertions were vacuous, and pristine caught it

This is the most transferable part of the increment. Both fixes were in the
fixture, not the test.

- **Four *centred* labels with differing text render at 186, 190, 188, and
  187.** The offsets already differ from text width alone, so an `isnt` or an
  ordering comparison passes against a renderer that ignores alignment
  entirely. Every alignment label in the fixture now carries identical text, so
  only the alignment can move the offset.
- **An un-ellipsized minimum width tracks the text**, so comparing
  `ellipsize=end` on one string against `ellipsize=none` on a different string
  measures the strings. Both labels now carry the same string; the ellipsized
  minimum is 9px against the full text width.

The lesson is the same one the `measure()`-above-16px trap taught in the first
increment, and it is worth stating generally: **run each new physical assertion
against pristine individually.** A file-level failure count hides an assertion
that fails for the wrong reason, and hides one that passes for the wrong reason
entirely.

### The right observable for a label's alignment

`Label->get_layout_offsets` returns where the text actually lands.
`translate_coordinates` cannot see a label's alignment, because the label widget
*is* the full slot — the alignment moves the text inside it. This is the
opposite of the `AB` case in the same test file, where the child widget moves
within the slot and `translate_coordinates` is exactly right.

### Verification for this increment

- `t/gtk4/30_Box.t` fails **7 of 78** against pristine on real Wayland.
- `t/04_Gtk4LayoutRenderer.t` fails **10 of 177** offline against pristine.
- Controls pass on both trees: the slot-width sanity check, the out-of-range
  ellipsize being left at the default, and `a Label with no xalign renders
  where xalign=0 does` — which legitimately matches on both trees, centred on
  pristine and left-aligned now, and is what pairs with the `far from centred`
  assertion to discriminate.
- No shared code changed. `make test-gtk3` was run anyway and passes.

## Renderer widget state

Widget elements implemented: `Label`, `Text`, `Play`, `Quit`, `Stop`, `Next`,
`Prev`, `Filler` — 8 of the ~100 in the layout compatibility surface. This is
still the real bottleneck: containers cover 8 of 15 types and are well ahead of
anything to put in them.

By instance count in the bundled layouts, `Filler` (102) is the second
most-used element in the whole layout system after `MenuItem` (103). It is now
implemented, so the note in earlier handoffs that "a fixture needing an
expanding filler must use `Text`, not the legacy `Filler`" no longer applies.

The three `%Buttons` entries (`Prev`, `Stop`, `Next`) exhaust the stateless
transport buttons whose commands the bridge exposes. Adding another means
either widening `@Commands` again — now a proven, cheap operation with
`make test-gtk3` available — or implementing a stateful button, which needs a
state getter and an event subscription the way `Play` does.

Every button the renderer builds now gets the legacy `Layout::Button` defaults,
so `Play`, `Quit`, `Prev`, `Stop`, and `Next` are frameless 24px icon buttons
matching GTK3, not framed theme-sized ones. See D027. `%ButtonHandled` now
covers `icon`, `stock`, `text`, `tip`, `size`, and `relief`; what remains
reported through `Unhandled` is `nbsongs`, `group`, `button=0`, and a `size=`
value outside the mapping.

`Label` and `Text` likewise get the legacy `Layout::Label` defaults, so they
are left-aligned rather than centred, and `xalign`/`yalign`/`ellipsize` are
applied. See D028. `%LabelHandled` covers `text`, `xalign`, `yalign`,
`ellipsize`, `minwidth`, and `minheight`; `markup`, `font`, `color`, `minsize`,
and `expand_max` stay reported.

Both increments follow the same pattern, and it is worth looking for more of
it: a legacy `@default_options` value whose GTK4 counterpart differs is a
silent, whole-class correctness bug. `%ButtonDefaults` and `%LabelDefaults` are
the two found so far. Any future widget class should have its
`@default_options` read before its options are, not after.

`minwidth=`/`minheight=` now reach every widget and container, through
`_ApplyCommonOptions`, which is the legacy `ApplyCommonOptions` size request
ported at both of the call sites GTK3 uses. That was a correctness gap
affecting every widget already rendered, not just new ones.

## Renderer container state, carried forward

The renderer covers 8 of the 15 container types, ordered by how often each
appears in the bundled layouts:

| Container | Uses in `layouts/` | State |
|---|---:|---|
| `HB`, `VB` | 449 | packing prefixes completed |
| `HP`, `VP` | 76 | implemented |
| `SB`, `FR`, `EB`, `AB`, `WB` | single-child | implemented |
| `SM`, `MB`, `BM` | 54 | not started |
| `NB` | 16 | not started |
| `TB`, `FB` | 4 | not started |

`_CreateBox` implements the full legacy `BoxPack` prefix set: digits are
padding, `_` is expand, `-` packs from the far edge, `.` turns fill off. It
keeps a single insertion point: once any `-` child has been packed, every later
child is inserted after the last start-packed child with `insert_child_after`,
which reproduces both groups' legacy order including interleaved `-a b -c d`.
`insert_child_after($widget,undef)` prepends, correct when no start child
exists yet. `_CreatePaned` implements `PanedPack`, and `_CreateSingle` covers
`SB`, `FR`, `EB`, `AB`, and `WB`.

## Previous session, fourth increment: D025/D026 for `AB` and `WB`

The oldest outstanding item in this file, deferred four sessions running,
is now written. Both entries are **Proposed** and both rows stay at
`GTK4 in progress` until accepted — nothing was advanced to parity.

The entries are more specific than "these are approximations", because
measurement narrowed both cases considerably:

**D025, `AB`.** The GTK3 container is
`Gtk3::Alignment->new(xalign,yalign,xscale,yscale)`
(`gmusicbrowser_layout.pm:2333`); `GtkAlignment` was removed in GTK4 and its
documented replacement is the `halign`/`valign` properties every widget now
carries. The renderer's translation is **exact for every bundled layout**: the
only alignment values anywhere in `layouts/` are 0, 0.0, .5, 0.5 and 1, and the
only scale values are 0 and 0.0, all of which map onto GTK4's three-valued enum
without loss. So the residual gap is not "the shipped layouts are
approximated" — it is two specific losses reachable only from a hand-written
layout: a fractional alignment buckets to start/center/end, and a fractional
scale is treated as fill. That is why the row still cannot advance: exact for
the layouts we ship is not parity for the layout language.

**D026, `WB`.** The GTK3 container is `Gtk3::EventBox->new`
(`gmusicbrowser_layout.pm:2337`), also removed in GTK4. Two measurements
reshaped this entry:

- **No bundled layout uses `WB` at all** — zero declarations across all 13
  files.
- `WB` exists for exactly one reason, stated in the source at
  `gmusicbrowser_layout.pm:1247`: `hover_layout` "only works with widgets/boxes
  that have their own gdkwindow (put it into a WB box otherwise)". The three
  `hover_layout` uses in `layouts/` reach it through the `EventBox` and `Cover`
  *widgets*, not through a `WB` container.

So `WB` is a workaround for a GTK3 limitation that GTK4 removed: a child can
now carry its own event controllers. The plain box keeps a user layout naming
`WB` building correctly, but the container currently has none of its behaviour,
and `hover_layout` is not ported either. D026 alternative 2 — fold
`hover_layout` into `WB` — is deferred rather than rejected, and is the point
at which this must be decided.

Both entries reject "make `AB`/`WB` a pass-through contributing no widget",
because those nodes can be packing targets: `layouts/contrib.layout` has
`-ABSearch`, `_ABSearchBox2`, and `ABSearchBox2` named in a
`Window= hidden=...` list. Removing the node would change the tree.

`AB` alignment now has the real-Wayland allocation coverage D025 requires
before that row could move, in `t/gtk4/30_Box.t`: four equal 150px expanding
slots place their child at x=0, 71, and 142 for `xalign` 0, .5, 1, and the
default `xscale=1` case fills its slot. **This is coverage of an implementation
that already existed, not a proof of new behaviour** — the same file passes
unchanged against the preceding commit. Do not cite it as an increment proof.

## Previous session, third increment: the shared labels fixture

`t/RendererLabels.pm` now holds the one `labels` hash the renderer tests pass,
replacing 13 copies of a literal that had grown once per tooltip-bearing
widget. Net effect on the test files is smaller than the module it adds, and
adding the next such widget is now a one-line change instead of a
thirteen-line one.

Two things learned while doing it:

- The values must match the `%Layout::Widgets` tips, not the widget names:
  `Next` is `Next Song`, `Prev` is `Recently played songs`. That is what makes
  a tooltip assertion pin the right widget entry.
- An assertion that the fixture satisfies the constructor is worthless and was
  removed. A `%Buttons` entry with no fixture label aborts the whole file at
  the first renderer built, with
  `GTK4 layout renderer needs the '<name>' label`, before any such assertion
  runs. Verified by adding a fake `Refresh` entry to a scratch copy. What is
  worth asserting is that `labels()` hands out a *copy*, which was verified to
  fail when the module returns `\%Labels` instead.

`gmusicbrowser_gtk4.pl` deliberately still carries its own literal: it is
production code and needs the `_"..."` gettext idiom, which is exactly what
`t/RendererLabels.pm` must not contain.

## Previous session, second increment: `Filler` and the legacy size request

Two things, both pure-layout with no shared-boundary change.

`Filler` is the legacy `Gtk3::HBox->new` (`gmusicbrowser_layout.pm:421`), so
GTK4 builds it as an empty `Gtk4::Box`. Worth doing because it is the second
most-used element in the bundled layouts — 102 instances — and because it
carries no options anywhere: every use is driven purely by its packing prefix,
which `_CreateBox` already translates. Measured on real Wayland, an expanding
`Filler` takes 564 of 600px while a plain one is allocated 0px with its
declared padding intact.

`_ApplyCommonOptions` is the more valuable half. Legacy `ApplyCommonOptions`
(`gmusicbrowser_layout.pm:1239`) runs on **every** widget and container, and
the GTK4 renderer did not implement it at all — so `minwidth=` (52 uses) and
`minheight=` (7) were being silently dropped for every widget already
rendered. It is now applied at both of the legacy call sites: `:1013` for
containers and `:1178` for widgets.

The legacy read-then-merge order is preserved verbatim, so a widget that
already requested a size of its own keeps whichever dimension the layout did
not name. That is safe because a GTK3 probe confirmed both toolkits spell an
unset dimension `-1` and that `minwidth=80` alone produces
`set_size_request(80,-1)` in each. This was verified rather than assumed.

`hover_layout`, the other half of `ApplyCommonOptions`, is deliberately not
ported: it needs a popup window and a widget with its own `GdkWindow`.

`maxwidth=` (44 uses) and `maxheight=` (7) were considered and left out. They
are not general options — in GTK3 they feed `Layout::Label`'s `expand_max`
ellipsize and scrolling machinery (`:3126`, `:3209`), so they belong with a
real `Layout::Label` port, not with a size request.

### Two traps this increment hit

- **A container's options go after the `=`.** The legacy syntax is
  `VBroot= (minwidth=320) ...`, read at `gmusicbrowser_layout.pm:1001`. Writing
  `VBroot(minwidth=320)=` does not error; the parser simply does not recognise
  `VBroot` as a container declaration, and the layout ends up with two roots,
  which `Render` then rejects.
- **`set_size_request` cannot shrink a mapped Wayland window.** It raises a
  minimum but never lowers a size the compositor already granted, which is the
  counterpart of the recorded `set_default_size` limitation. An assertion that
  a container is allocated at least its `minwidth` is therefore vacuous in a
  600px window and *passes against pristine*. Use `measure($orientation,-1)`,
  which returns `(minimum, natural, min_baseline, nat_baseline)` and marshals
  correctly through this binding, and add a control on a sibling with no
  `minwidth` so the comparison discriminates. Both are recorded in D006.

### Also corrected

`Text` was still listed as **Not started** in the parity checklist's widget
inventory even though it has been implemented since the proof slice. That is a
pre-existing documentation gap, now fixed. `Prev` was likewise missing from
that inventory entirely before the previous increment.

## Previous session, first increment: `Next` and `Prev`, and the first shared-boundary change

`Next` and `Prev` are now rendered, and `@Commands` in
`gmusicbrowser_frontend_legacy.pm` was widened to expose `NextSong` and
`PrevSong`. That bridge list is shared code, so this is the first
shared-boundary change of the port.

Why these two: they are the most-used unported simple buttons in the bundled
layouts. Counting actual widget instances, `Next` appears **34** times and
`Prev` **29**, against 20 for `Stop`. Both are Tier-1 stateless buttons, and
the renderer side was two `%Buttons` entries.

Those counts are hard to get right and three earlier readings disagreed, so the
method matters. A naive `grep -c` overcounts (`group=Next`, and three
`titlebar.layout` `Name=` lines that read "Stop, Play and Next buttons"); a
line-based grep undercounts because one line often holds `Prev Stop Play Next`;
and a token pass that splits on `=` misses the continuation lines in
`contrib.layout` and `makeitlooklike.layout`, whose children start with
whitespace and have no `=` of their own. The figures above come from
tokenizing every line, skipping only `Name=`/`Type=`/`Title=`/`Icon=`, taking
the right-hand side only when the line actually starts with `word =`, then
stripping trailing `\`, any option list, and any packing prefix before
matching. An earlier handoff recorded 17 `Next` and 10 `Prev`; those do not
reproduce by any counting method tried.

`NextSong` and `PrevSong` take no widget argument in the core `%Command` table
(`gmusicbrowser.pl:3489` and `3499`), which is what makes them safe to reach
through the widget-free bridge. `t/05_FrontendLegacy.t` now asserts that the
bridge *refuses to construct* when either definition is missing, so the
allowlist cannot silently drift out of step with a `%Buttons` entry.

### The renderer records what it ignores

`Next` and `Prev` carry `options => 'nbsongs'`, `nbsongs => 10`, a `group`, and
a `click3` that opens a song chooser. `click3` was not implemented — pointer
input is not ported. Rather than accept `nbsongs`/`group` silently, the
renderer now has an `Unhandled` accessor: `_CreateButton` records every option
name outside `%ButtonHandled` (`icon`, `stock`, `text`, `tip`) against the
widget's name, and leaves the parsed values untouched. That satisfies "unknown
options are preserved and reported, not silently deleted" without inventing a
diagnostics channel the renderer does not otherwise have.

Two details worth carrying forward:

- `Prev` is `group => 'Recent'`, not `'Next'`. Only `Next` is `group => 'Next'`.
- GTK3 does **not** display the widget-table `text` for these buttons.
  `Layout::Button` uses `text` only when `with_text` is set
  (`gmusicbrowser_layout.pm:3047`) or when there is no `stock` at all (3062).
  Since both have a `stock` default, `_"Next"` never appears in the GTK3 UI.
  The GTK4 renderer keeps the same shape: `text` is a fallback used only when
  no icon resolves, which offline is what the doubles see.
- The `tip` labels must match the GTK3 widget table exactly: `Next` is
  `_"Next Song"` and `Prev` is `_"Recently played songs"`. Both msgids already
  exist in `po/`.

### These two are the first real consumers of D024

Measured inside the runner environment, Adwaita carries `media-skip-forward`
and `media-skip-backward` **only** as `-symbolic`. Both buttons therefore
resolve to the suffixed spelling while `Stop` still resolves the unsuffixed
`media-playback-stop`. Without the D024 fallback these two widgets would have
shown a text label on stock GNOME. This is direct evidence for moving D024 out
of Proposed. The Wayland assertions accept either spelling so they do not pin
one theme's convention.

### The labels hash, and the cleanup that followed

The renderer constructor rejects a `labels` hash missing any `%Buttons`
tooltip, so `next` and `prev` had to be added at eleven test call sites plus
`gmusicbrowser_gtk4.pl`. That duplicated literal was extracted into
`t/RendererLabels.pm` in the third increment of this session; see below.

## The GTK3 regression smoke now exists

The previous handoff recorded that there is no scripted GTK3 startup/shutdown
smoke on this host. That is now wrong, and the reason it was believed was a
misdiagnosis.

`-nodbus -cmd Quit` *does* deliver the command: `gmusicbrowser.pl:1937` calls
`run_command(undef,'Quit')`. The problem is that **`Quit` is not in the
`%Command` fifo table at all** — it is a frontend lifecycle operation — so
`run_command` warns `Unknown command 'Quit'` at line 1716 and the application
simply keeps running. The earlier note "the command is not delivered" was
wrong.

`SIGTERM` is wired to `Quit` at `gmusicbrowser.pl:1938`, immediately before
`Gtk3->main`. `tools/run-gtk3-smoke` (`make test-gtk3`) uses that: it starts
GTK3 on the real Wayland connection with isolated config/data/cache/state,
waits for the main loop, sends `SIGTERM`, and reports one TAP assertion on the
exit status. It passes, and produces byte-identical diagnostics on the working
tree and on a pristine `git archive` of HEAD — the same missing
`Net::DBus::Annotation` for the MPRIS2 plugin, the same disabled mpv backend,
the same single `gtk_widget_get_scale_factor` GTK critical, exit 0.

Two traps it works around, both of which cost time:

- `XDG_RUNTIME_DIR` must stay the host's. `use Gtk3 '-init'` at
  `gmusicbrowser.pl:26` initialises GDK at compile time, so a temporary runtime
  directory with a symlinked Wayland socket produces `cannot open display`
  before any application code runs. Only config, data, cache, and state are
  isolated. `-demo` additionally means the run never writes tags or settings.
- gmusicbrowser outlives `timeout` and ignores a `SIGTERM` sent during startup,
  so the runner traps `EXIT` and `SIGKILL`s the child. If you script GTK3 by
  hand, check for and kill stray `gmusicbrowser.pl` processes afterwards.

## Previous session: the `-symbolic` fallback (D024)

The user's goal is that the OS icon theme supplies the artwork. D023 already
resolves icons by name, so the assumption was that standard freedesktop names
already follow the host theme. Measurement showed that assumption is wrong on
one of the D022 target desktops.

GNOME's Adwaita ships many action icons **only** as `<name>-symbolic`. It has
no `application-exit`, `view-refresh`, `help-about`, `edit-clear`,
`view-fullscreen`, `media-skip-forward`, or `media-skip-backward`, but carries
every one of them suffixed. Breeze and Humanity carry both spellings. So the
unsuffixed name silently failed on stock GNOME.

`_IconName` now tries the whole existing candidate chain unsuffixed first, then
the same chain with `-symbolic` appended. Unsuffixed keeps priority so a theme
that still ships full-colour artwork keeps supplying it; a candidate already
ending in `-symbolic` is not suffixed twice; an unmapped unknown name is never
turned into a fabricated `<name>-symbolic`, so it still falls back to text.
Recorded as D024, status **Proposed**.

Why this is inside D013: it changes no artwork, adds and removes no file, and
changes no layout-visible name. It repairs resolution of infrastructure GTK4
removed, which is the same ground D023 stands on. It is not a restyling.

## Previous increment: the first stateless command button

`Stop` is now rendered, as the first entry in a `%Buttons` table in
`gmusicbrowser_gtk4_layout.pm`. The table keeps the field names
`%Layout::Widgets` uses in `gmusicbrowser_layout.pm:60`, so the GTK4 and GTK3
definitions can be diffed by eye. `_CreateButton` builds it and `_SetTip`
applies tooltips; neither `Play` nor `Quit` changed behaviour.

Why `Stop` specifically, and nothing else in the same batch: the audited legacy
bridge registers only `Play PlayPause Pause Stop IncVolume DecVolume TogMute`
(`gmusicbrowser_frontend_legacy.pm:15`). `Stop` is the **only** simple
transport button whose command is already reachable. `Next` (34 instances in
bundled layouts, corrected from the 17 recorded at the time) and `Prev` (29,
corrected from 10) map to `NextSong`/`PrevSong`, which exist in the core
`%Command` table at `gmusicbrowser.pl:1624-1625` but are **not** in the
bridge's list. Porting them means widening a shared boundary, which needs its
own GTK3 regression pass, so it was deliberately left out rather than bundled
in.

Design points worth keeping:

- Adding a widget whose command is not registered would build fine and fail on
  click. The table is therefore restricted to bridge-exposed commands.
- `click2`/`click3` are omitted on purpose. `Stop` has
  `click2 => 'EnqueueAction(stop)'` and `click3 => 'SetNextAction(stop)'` in
  GTK3, but pointer input is not ported, and half-wiring them would be worse
  than dropping them. They are recorded as not covered.
- The authoritative icon option for `Layout::Button` is `stock`, not `icon`.
  `_SetIcon` accepts both, which is a superset and harmless, but the widget
  default is supplied as `stock`.
- The renderer takes every user-visible string from the caller's `labels`,
  which is why the table names its tooltip (`tip => 'stop'`) instead of
  embedding English. That convention is what keeps this module free of the
  `_"..."` idiom that makes `gmusicbrowser_layout.pm` non-compilable alone.
  The constructor now rejects a `labels` hash missing any `%Buttons` tooltip,
  so a mute button fails loudly instead of rendering blank. Nine call sites in
  four test files plus `gmusicbrowser_gtk4.pl` were updated to pass `stop`.
- Legacy `Layout::Button` defaults are `relief => 'none'` and
  `size => SIZE_BUTTONS` (`large-toolbar`). Those still are not implemented,
  but they are the *default* for every button, not rare options, so they matter
  more than the parity checklist implied.

One regression the doubles caught: giving `%Buttons` a default `stock` made
every button consult the icon theme, where previously only a layout-supplied
icon did. The offline doubles have no `Gtk4::Gdk::Display::get_default` at all,
so `_IconTheme` now wraps the display lookup in `eval` — the subroutine is
absent, not merely empty, when the renderer runs without a real binding.

## Why the recommended increment was NOT done

The handoff's suggested next step was to map the bundled `gmb-*` names to
freedesktop names. That was not done, for two reasons found while reading:

1. D023 alternative 2 **already deferred exactly this**, citing D013. Doing it
   would have quietly overridden an existing decision entry.
2. The `gmb-*` files are the artwork behind gmusicbrowser's own user-facing
   preference. `gmusicbrowser.pl:7023` builds an "Icon theme :" combo from
   `GetIconThemesList`, and `pix/` ships three packs — `elementary`,
   `gnome-classic`, and `oxygen` — that exist solely to re-skin those names.
   Replacing `gmb-random` with `media-playlist-shuffle` would not be
   infrastructure replacement; it would delete the artwork a documented
   feature selects between. That needs its own accepted decision.

Also worth knowing before proposing that mapping: `view-list-tree`,
`view-list`, `view-grid`, `system-search`, and `edit-find` are each missing
from at least one installed theme, so several `gmb-view-*` names have no
reliably available standard equivalent. Nothing was removed from `pix/`; the
user was not asked to, because no removal was proposed.

## Verification claims that did not reproduce

Four recorded results were wrong across the last two sessions. They are
corrected in `TESTING.md`; the method that produced each bad reading is
recorded because the same traps are easy to hit again.

- **"Yaru theme", and `application-exit`/`view-refresh`/`edit-find` absent.**
  Yaru is not installed on this host at all. The desktop theme is **Tela**, and
  all three names resolve under it. The absence is real, but it belongs to
  Adwaita.
- **The theme active during `make test-gtk4` is the desktop's.** It is not. The
  runner unsets the session bus, so GTK cannot read the icon-theme preference
  and uses **Adwaita**. This is why a pre-existing assertion expected
  `application-exit`, a name the active theme cannot render. That assertion now
  accepts either spelling.
- **The GTK3 `-cmd Quit` smoke "exited zero".** It exits **2**. `Net::DBus` is
  missing, so `gmusicbrowser.pl` warns that `gmusicbrowser_dbus.pm` failed to
  load and then calls the undefined `GMB::DBus::simple_call` at
  `gmusicbrowser.pl:512` anyway. A pristine `git archive` of HEAD fails
  identically, so it is pre-existing and not a GTK4 regression. The earlier
  "exited zero" was most likely `tail`'s exit status from a pipeline. That much
  still holds.
- **"There is no working scripted GTK3 startup/shutdown smoke on this host",
  and "`-nodbus` does not deliver the command".** Corrected this session. Both
  are wrong. `-nodbus` delivers the command fine at
  `gmusicbrowser.pl:1937`; `Quit` is simply not in the `%Command` fifo table,
  so `run_command` warns `Unknown command 'Quit'` and the application keeps
  running. `SIGTERM` *is* wired to `Quit` at `gmusicbrowser.pl:1938`, and
  `make test-gtk3` uses it to get a passing startup/shutdown smoke. The bad
  reading came from assuming the delivery path was broken instead of checking
  whether the command name existed.

## Verification status: read this before claiming anything

The packing and single-child coverage in `t/04_Gtk4LayoutRenderer.t` uses
in-process Perl doubles. It covers construction, options, packing translation,
and pane size calculations, not rendering or physical input. Real pane checks
are in `t/gtk4/20_Paned.t` and real box geometry in `t/gtk4/30_Box.t`; see
`TESTING.md` for the evidence and limits.

The box geometry assertions are not construction checks. Against the previous
`_CreateBox`, `t/gtk4/30_Box.t` fails 10 assertions and
`t/04_Gtk4LayoutRenderer.t` fails 10 more. Both were confirmed by running the
new tests against a scratch copy carrying the old implementation.

No row was advanced to `Parity review`. Real allocation and action signals are
not sufficient for complete input, focus, accessibility, and saved-profile
parity. `AGENTS.md` forbids reporting a skipped or reasoned-about test as a pass.

The icon assertions are behaviour, not construction. Against the previous
`_IconName`, `t/gtk4/40_Icons.t` fails 2 assertions, returning
`application-exit` and `view-refresh` where Adwaita can render only the
symbolic spellings.

The `Filler` and size-request assertions cannot pass against the previous tree.
Extracting `git archive HEAD` to a scratch directory and overlaying only the
changed test files and `t/layouts/sizing.layout`, the offline
`t/04_Gtk4LayoutRenderer.t` dies at
`t/layouts/sizing.layout:4: GTK4 widget 'Filler' is not implemented`. Because
that abort hides the sizing assertions, the proof was repeated with **only**
`Filler` added to the pristine copy, so those assertions are reached and judged
on their own merit: 4 offline assertions then fail and the file aborts on the
missing `_ApplyCommonOptions`, and on real Wayland `t/gtk4/30_Box.t` fails **8
of 52**. The sibling-row control (`a sibling row with no minwidth measures a
smaller minimum`) correctly passes on both trees, so the comparison
discriminates rather than merely failing everything.

The `Next`/`Prev` assertions cannot pass against the tree before them either.
The proof was run the same way, overlaying only the changed test files and the
fixture on a pristine archive:

- `t/04_Gtk4LayoutRenderer.t` and `t/gtk4/40_Icons.t` both die at
  `t/layouts/buttons.layout:4: GTK4 widget 'Prev' is not implemented`.
- `t/05_FrontendLegacy.t` fails 7 of 47 assertions, because the pristine bridge
  neither exposes nor requires `NextSong`/`PrevSong`.
- `t/06_LifecycleLegacy.t` passes against pristine. That is honest rather than
  a gap: the two added names ride along in its command fixture, and its role is
  startup/shutdown ordering, not the command allowlist. Do not cite it as
  proof of this increment.

Commands that were actually run and passed this session:

	perl -I. -c gmusicbrowser_gtk4_layout.pm
	perl -I. -c gmusicbrowser_gtk4.pl
	perl -I. -c gmusicbrowser_frontend_legacy.pm
	perl -I. -c t/04_Gtk4LayoutRenderer.t
	perl -I. -c t/gtk4/40_Icons.t
	perl -I. -c t/RendererLabels.pm    # one file per invocation
	prove --norc -I. t/02_LayoutParser.t t/03_FrontendContract.t \
	      t/04_Gtk4LayoutRenderer.t t/05_FrontendLegacy.t t/06_LifecycleLegacy.t
	make test-modernization
	make test-gtk4
	make test-gtk3
	git diff --check

`make test-modernization`: **342** executed assertions passed, no skips.
Running totals: 269 two sessions ago, 298 after `Next`/`Prev`, 315 after
`Filler`, 317 after the labels fixture, 325 after `size=`/`relief=`, 342 after
label alignment. The skip count was read from `prove -v`, not assumed.

`make test-gtk4` on the real Wayland connection: **258** TAP results,
comprising **252 executed assertions passed** and the same six pre-existing M1
feasibility probes skipped, 0 failures. Per file: 18 binding (which is where
all six skips live), 4 proof-of-life, 84 pane, 78 box, 74 icon. Running totals
for the same command: 173 before `Next`/`Prev`, 184 after it, 202 after
`Filler`, 216 after the `AB` coverage, 246 after `size=`/`relief=`, 258 now. Do not restate this as 246
passing assertions. The six skips were counted by copying the runner to
`tools/.verbose-smoke-tmp`, switching `prove` to `-v`, and grepping
`^ok [0-9]+ # skip` — six matches, all `BLOCKED:` M1 probes in
`t/gtk4/00_Binding.t`. Not assumed. Note that a copy of the runner placed
*outside* `tools/` computes the wrong repository root from `dirname $0` and
silently tests nothing; keep the copy in `tools/`.

`make test-gtk3`: 1 assertion passed on the real Wayland connection, and the
same command passed identically against a pristine `git archive` of HEAD with
byte-identical diagnostics. Both runs emit the pre-existing missing
`Net::DBus::Annotation` for the MPRIS2 plugin, the disabled mpv backend, and
one `gtk_widget_get_scale_factor` GTK critical, and both exit 0. `Net::DBus`
itself is still not installed, so `perl -I. -c gmusicbrowser.pl` still fails —
identically on the working tree and on a pristine `git archive` of HEAD, with
`gmusicbrowser.pl` unmodified, so it is not a regression. Both line numbers
appear and both are real: `Undefined subroutine &GMB::DBus::simple_call called
at gmusicbrowser.pl line 512`, then `BEGIN failed--compilation aborted at
gmusicbrowser.pl line 528`, which is where that `BEGIN` block closes. Earlier
notes cite only 512; expect to see 528 as the abort line.

`gmusicbrowser_layout.pm` was not changed and still is not standalone
compilable: `perl -c` fails on its `_"..."` gettext idiom for the committed
file as well.

Pane tests exercise both orientations, saved-size reconstruction, notification
state before saving, focus/action signals, and real window resizing under all
four resize policies. Box tests exercise allocated offsets and widths for
mixed, interleaved, and expand/fill rows in both axes. Physical pointer and
keyboard input is not covered by either.

GTK3 regression status for this session: the `Filler`/size-request increment
touches only `gmusicbrowser_gtk4_layout.pm`, so no shared code changed there,
but `make test-gtk3` was run anyway and passed. The `Next`/`Prev` increment
**did** change shared code, so the "cannot be affected" reasoning used by
previous sessions does not apply to it.
`@Commands` in `gmusicbrowser_frontend_legacy.pm` is on the shared boundary,
and widening it makes the bridge require `NextSong` and `PrevSong` at
construction — so the failure mode is a GTK3 startup abort at
`gmusicbrowser.pl:1866`. Two checks cover it:

- `make test-gtk3` exercises the real GTK3 path on Wayland and passes
  identically on the working tree and on pristine HEAD.
- A scratch probe extracted the `%Command` table from the unmodified
  `gmusicbrowser.pl` by regex, found 74 entries with all nine bridge names
  present, constructed the bridge against it, dispatched `NextSong`,
  `PrevSong`, and `Stop`, and confirmed `CloseWindow` and `SetFocusOn` stay
  unregistered. It was not kept as a permanent test.

What is still **not** covered on the GTK3 side: clicking the real GTK3 `Next`
and `Prev` buttons, since they route through `Layout::Button`'s `activate`
rather than the bridge, and any comparison of GTK3 and GTK4 button behaviour
under the same fixture and action sequence. Neither widget was advanced past
`GTK4 in progress`.

The earlier packing comparison still stands: the unchanged production `BoxPack`
was extracted from `gmusicbrowser_layout.pm` and driven by the same fixture,
parser, width, child size request and text direction, and GTK3 and GTK4
produced identical offsets and widths in all three rows; the table is in
`TESTING.md`. That is a focused packing comparison, not a full GTK3
application regression pass.

`t/01_ModFileMetadata.t` still fails: it downloads media samples and the
repository ships none. That is the pre-existing M0 gap, not a regression.

## Toolkit bindings are installed; Wayland requires sandbox access

The user installed the packages during the 2026-09-07 session:

	sudo apt install gir1.2-gtk-4.0 libglib-perl \
	  libglib-object-introspection-perl libgtk3-perl

The following probe now reports GTK 4.14.5:

	perl -e 'require Glib::Object::Introspection;
	  Glib::Object::Introspection->setup(basename=>"Gtk",version=>"4.0",package=>"Gtk4");
	  printf "GTK %d.%d.%d\n", Gtk4::get_major_version(),
	    Gtk4::get_minor_version(), Gtk4::get_micro_version()'

`make test-gtk4` initially failed with `Failed to open display` inside the
execution sandbox. Repeating it with approved access outside the sandbox used
the real Wayland connection and system packages. Before adding the pane test,
the runner reported 22 TAP results: 16 executed assertions passed and six
unimplemented feasibility probes were skipped. Do not call this 22 passing
assertions or a completed M1 gate. Introspection INIT-block and missing
session-bus warnings remain. Do not use the old temporary extracted packages.

## Pane saved-size increment and remaining gaps

Panes now expose the legacy `SaveOptions` callback returning `size`. Position,
max-position, and map signals queue one idle update after allocation; saving
also flushes the size calculation. GTK4 resize-child getters replace
`child_get()`. The legacy two-sided resize calculation, five-pixel tolerance,
and retry after insufficient space are retained; `0-0` avoids division by zero.
Teardown disconnects signals and removes any pending idle.

This closes the renderer callback gap, not application persistence: the GTK4
proof still has no configuration writer. Full pointer/keyboard/focus and
accessibility comparison remains. The parser catalog is not mutated by saving.

`AB` and `WB` have no GTK4 equivalent. `AB` became alignment properties on its
child and `WB` became a plain box. Both are approximations and need accepted
entries in `DECISIONS.md` before they can count as parity.

The box-packing follow-up recorded here previously is done. What box packing
still does not cover: homogeneous boxes, any `spacing` other than the legacy 1,
size groups, `expand_max`-style widget options that negotiate their own size,
right-to-left direction (the tests force `ltr`), and physical input. Nested
box-in-box geometry is only checked one level deep through `VBroot`.

## Icon increment and what it does not cover

`_CreateBox`'s sibling addition this session is icon resolution, accepted by the
user and recorded as D023 (status Proposed, since D013 defers presentation
changes and this replaces removed infrastructure rather than restyling).

`_IconName` resolves in order: the requested name, the bundled alias from
`%IconFallbacks`, the `gtk-*` replacement from `%StockNames`, then the
replacement for the alias. A name found in the theme wins immediately. If none
is found but the name was mapped, the mapped name is used anyway, because GTK
substitutes a missing-image paintable and a themed name absent on one host is
usually present on another. An unmapped unknown name resolves to nothing so the
widget keeps its text label rather than showing a broken image.

Two bugs the real test caught, worth knowing about:

- `_SetPlayLabel` originally overwrote any icon with the play/pause pair, so
  `Play(icon=gmb-random)` lost its icon. Only a widget whose icon actually is
  the play/pause pair now tracks state through the icon; everything else keeps
  what the layout asked for.
- The first resolver had no final fallback, so `stock=gtk-quit` produced no
  icon on this host because Yaru lacks `application-exit`.

Not covered: only `Play` and `Quit` accept icons, because they are the only
icon-capable widgets implemented. The other 99 `icon=` and 17 `stock=` uses in
bundled layouts belong to unimplemented widgets. Icon size options
(`size=button`, `size=large-toolbar`, `size=menu`), `relief=none`, and the
`stock="on:... off:..."` two-state form used by `LockAlbum`/`LockArtist` are
all still unhandled. Symbolic variants are now handled, as D024. No GTK3 icon
code was touched.

Still true after this session: the 28 bundled `gmb-*` names are app-supplied
artwork and do **not** follow the host icon theme. That is the remaining gap
against the user's stated goal, and closing it needs an accepted decision
because those files back the "Icon theme :" preference. None of the 28 names
exists in any installed host theme, so they cannot be shadowed by one.

## Do not repeat this dead end

The user reported the playing queue being clipped in the GTK3 window and
approved adding `+` to `VBLeft` in `layouts/shimmer.layout:10`
(`HPMain= VBLeft _VBRight`) to stop the pane shrinking. That fix was measured
and **does not work**, so it was not applied:

- With a plain label child, shrink-off changes nothing: the label's own minimum
  is already honoured and `set_position(20)` is simply refused.
- With a low-minimum child, which is what `NBList`/`QueueList` is, the pane
  clips to 46px whether or not `+` is present. `shrink` only respects the
  child's *declared* minimum, and a scrolled songtree declares almost none.

The real cause is that `QueueList` does not propagate a minimum width matching
its configured columns (`colwidth="queuenumber 20 titleaa 248"`, so ~268px).
Fixing it means changing minimum-size propagation in GTK3 production code,
which needs its own scoped decision. `Default = Window(size=1000x750)` also
means the reported ~1190px window is not the layout's designed size.

## Suggested next steps

1. **Decide D027 and D028**, both written this session as **Proposed**. They
   are the narrowest of the open decisions: both translations are lossless and
   measured in both toolkits, so the only real questions are D027's
   alternative 3 (`set_has_frame` versus `add_css_class('flat')`) and D028's
   alternative 2 (whether to preserve the `Layout::Button`/`Layout::Label`
   `ellipsize=1` asymmetry, which the implementation currently does). Every
   button and label row is blocked behind them, because until they are accepted
   the sizing and alignment are unaccepted approximations on paper even though
   both are exact in fact.
   There are now **six** Proposed entries — D023, D024, D025, D026, D027,
   D028 — and every one of them gates a row. That backlog is the main thing
   stopping the parity checklist from moving, not missing implementation.
2. Next widget candidates. **Do not take `ToggleButton` as a button
   increment** — see the section at the top of this file for why the previous
   recommendation was wrong. Corrected reading:
   - `ToggleButton` (39 option groups, all with `widget=`) needs the layout
     show/hide subsystem: `ShowHide`, `Hide`, `GetShowHideState`,
     `get_layout_widget`, and the `HiddenWidgets` watch. That is the real
     unit of work, and it is a subsystem port, not a widget port. It may
     still be the right next increment, but scope it as show/hide.
   - `LockAlbum`/`LockArtist` (22 each) need state, the `button=0` EventBox
     shape, and pointer hover for the second icon in each state. Not a
     `%Buttons` entry.
   - `Window` is a container-level concept and probably belongs with `@layout`
     embedding. `SimpleSearch` and `FilterPane` are list/model widgets and are
     gated behind the unproven M1 `GListModel` probe.
   - `MenuItem` and `SeparatorMenuItem` are the two most-used elements overall
     but are the `GMenu`/`PopoverMenu` design change — **ask the user first.**
   Instance counts in this file have been recorded wrong repeatedly; treat any
   figure here as needing a hand check before it drives a decision.
3. Keep running `make test-gtk4` on the real Wayland connection with the system
   packages, outside the execution sandbox when needed. Count explicit skips.
   Also run `make test-gtk3` after any shared-code change; it works now.
4. `DECISIONS.md` entries for `AB` and `WB`. **Written this session** as D025
   and D026, both **Proposed**. Accept them, or push back. Accepting D025 does
   not by itself advance the `AB` row: the fractional alignment/scale gap it
   documents has to be closed or explicitly waived first. Accepting D026 needs
   a call on its alternative 2, folding `hover_layout` into `WB`.
5. D006 binding evidence. **Already recorded, keep extending it.** D006 now
   holds the graphene marshalling failure, the `->can` segfault, the
   widget-before-`Gtk4::init` segfault, the empty-string boolean artifact, the
   `set_theme_name` display-singleton refusal, the
   `get_size_request`/`set_size_request`/`measure` findings, and this session's
   fatal-enum, `Button`-image-child, and `set_has_frame` findings.
6. Move D023 from Proposed to Accepted, or push back on it, before more
   icon-bearing widgets are added. D024 is now in the same position: both are
   Proposed and both concern icon resolution, so decide them together.
   **New evidence for D024 this session:** `Next` and `Prev` are its first
   production consumers. Adwaita carries `media-skip-forward` and
   `media-skip-backward` only as `-symbolic`, so without the fallback both
   would render as text on stock GNOME, a D022 target.
   Decide also whether to propose mapping `gmb-*` to freedesktop names, which
   D023 alternative 2 currently defers and which this session did not do.
7. Investigate the queue clipping properly: make `QueueList` propagate a
   minimum width from its configured columns. See the dead-end section above
   before touching `layouts/shimmer.layout`; the obvious `+` fix is disproven.
8. Integrate renderer saved options with an isolated configuration round trip,
   then compare physical pane input and accessibility against GTK3.
9. Consider right-to-left packing. GTK4 `insert_child_after` is direction
   independent, but the legacy far-edge meaning of `-` is not, and no bundled
   layout has been checked under `rtl`.
10. Then menus, `SM`/`MB`/`BM`, 54 uses. **Do not start these without asking the
   user first.** GTK4 replaced `GtkMenu` with `GMenu` and `PopoverMenu` models,
   so this is a design change rather than mechanical translation, and
   `plugins/appindicator.pm` is explicitly marked "do not port its GTK3 menu".

## Working notes

- **`ToggleButton` is `Layout::TogButton`, not a `Layout::Button` variant.** It
  is a show/hide controller for other layout widgets and dispatches no command.
  See the section at the top of this file before scoping it.
- **An out-of-range enum nickname is fatal through this binding.**
  `Image->set_icon_size('menu')` dies with `FATAL: invalid enum GtkIconSize
  value menu, expecting: inherit / normal / large`. So a legacy GTK3 enum
  nickname cannot be passed through and probed for afterwards — map it first.
  `GtkIconSize` measures 16px for `inherit` and `normal`, 32px for `large`.
- **`Gtk3::IconSize::lookup` takes the numeric enum, not the nickname,** through
  this binding. Passing `'menu'` warns `Argument "menu" isn't numeric` and
  returns zeros, which looks like the sizes are unavailable. Pass 1..6
  (`menu`, `small-toolbar`, `large-toolbar`, `button`, `dnd`, `dialog`) and it
  returns `(ok, width, height)`. Also note an *unrealized* `Gtk3::Image`
  measures 0, so read the sizes from `lookup`, not from `get_preferred_width`.
- **`Button->set_icon_name` creates the `Gtk4::Image` child itself,** reachable
  through `get_child`; `set_pixel_size` on it works and shows up in `measure`.
  `set_label` replaces that child. Style the button's own image: substituting
  an explicit `Gtk4::Image` leaves `Button->get_icon_name` undefined, which the
  renderer and every existing icon assertion rely on.
- `Button->set_relief`/`get_relief` are absent. `set_has_frame` is the
  replacement, `get_has_frame` reads back `1` and `''` rather than `1`/`0`, and
  GTK4's default is framed. `add_css_class('flat')` also works.
- **Nothing about icon size can be asserted in the offline doubles.** They have
  no display, so `_IconTheme` returns undef, `_IconName` returns early, and no
  icon resolves at all — every button falls back to a text label with no image.
  Icon-size assertions belong in `t/gtk4/40_Icons.t`.
- **`Label->get_layout_offsets` is the only observable for a label's
  alignment.** `translate_coordinates` cannot see it: the label widget *is* the
  full slot, and the alignment moves the text inside it. This is the opposite of
  the `AB` case in the same test file, where the child widget moves within the
  slot and `translate_coordinates` is exactly right.
- **Labels being compared for alignment must carry identical text.** Four
  *centred* labels with differing text render at offsets 186, 190, 188, 187 —
  they differ from text width alone, so an ordering or `isnt` comparison passes
  against a renderer that ignores alignment entirely.
- **Labels being compared for `ellipsize` must also carry identical text.** An
  un-ellipsized minimum width tracks the text, so two different strings measure
  the strings rather than the option.
- **Floating-point properties print in the current locale.** A GTK3 probe under
  this host's locale reported `xalign=0,5` with a comma and made
  `set_alignment` look broken. Run numeric probes under `LC_ALL=C`.
- `Gtk4::Label` defaults to `xalign=0.5`, so the legacy `xalign => 0` default is
  a real behaviour difference, not a no-op. `set_xalign`/`set_yalign` accept
  fractional values exactly in both toolkits, so unlike `AB` nothing is bucketed.
- **A `measure()` check on an icon only discriminates above 16px,** because
  GTK4's default icon size is 16. `size=menu`, `size=button`, and
  `size=small-toolbar` measure correctly even against a renderer that ignores
  `size=`. Pair every such measurement with `get_pixel_size`, and check each
  new assertion against pristine individually rather than trusting the file's
  failure count.
- **Isolate the real option when grepping layouts for `size=`.** A plain
  `grep -o 'size=[a-z-]*'` also matches `minsize=`, `picsize=`, and
  `ellipsize=end`; use `[(,]size=`. And `Total(size=small)` is a font size on a
  different widget, not an icon size.
- **A copy of `tools/run-gtk4-smoke` placed outside `tools/` tests nothing.**
  It computes the repository root from `dirname $0`, so it silently runs no
  test files and reports success. Keep any modified copy inside `tools/`.
- The layout parser already recognizes all 15 container types and already
  extracts `HP`/`VP` packing with the correct `([_+]*)` regex. Gaps are in the
  renderer, not the parser.
- The GTK3 source of truth for container behaviour is the `%Layout::Boxes::Boxes`
  dispatch table at `gmusicbrowser_layout.pm:2273`, with `BoxPack` at 2367 and
  `PanedPack` at 2377.
- In the legacy `Gtk3::Box->new('horizontal',1)` call the `1` is spacing, which
  is why the GTK4 boxes are created with spacing 1.
- Layout element names carry numeric suffixes: `Label3` has element `Label` but
  keeps `Label3` as its registry name. Fixtures need distinct names or widgets
  collide in `$renderer->{widgets}`.
- The renderer test asserts `!exists $INC{'Gtk3.pm'}`. Any new double must not
  pull in a real binding.
- `GMB::Gtk4::Binding::try_init` only sets up introspection. Creating any
  widget before `backend_probe` (which calls `Gtk4::init`) segfaults. Calling
  `->can(...)` on an introspected class also segfaults; probe by calling the
  method inside `eval` instead.
- Geometry must come from `translate_coordinates`, which returns
  `($ok,$x,$y)`. `compute_bounds` and `compute_point` die with
  `GType GrapheneRect/GraphenePoint ... is not registered with gperl`.
- `set_default_size` is ignored once a Wayland window is mapped; the
  compositor owns the size. Use `set_size_request` to grow a mapped window in
  a test, then wait for `max-position` or the allocation to change.
- When probing legacy `pack_start`/`pack_end` directly, pass `expand` and
  `fill` as explicit `0`/`1`. `$opt=~m/_/` yields `''` for no match, and this
  introspection binding mishandles the empty string, producing allocations
  that look like a packing bug but are a probe artifact.
- Widget elements in the GTK4 renderer: `Label`, `Text`, `Play`, `Quit`,
  `Stop`, `Next`, `Prev`, `Filler`. The earlier note that an expanding filler
  must use `Text` because `Filler` does not exist no longer applies.
- The GTK3 reference geometry is best obtained by extracting `BoxPack` from
  `gmusicbrowser_layout.pm` with a regex and `eval`, so the comparison uses
  production code rather than a copy. That module is not standalone
  compilable: `perl -c` fails on its `_"..."` gettext idiom, for the committed
  file too.
- `t/layouts/packing.layout` is the box fixture. Its rows deliberately include
  an expanding child, because a `-` child only reaches the far edge when some
  child expands.
- **Icon-theme testing must not use the display singleton.**
  `Gtk4::IconTheme::get_for_display` returns it, and `set_theme_name` on it is
  refused with a `gtk_icon_theme_set_theme_name: assertion
  '!self->is_display_singleton' failed` critical while silently leaving the
  theme unchanged. A first attempt at a cross-theme table this way produced 38
  names by 5 themes of identical all-YES results: it measured the live theme
  five times. Use `Gtk4::IconTheme->new` and `set_theme_name` on that. The
  renderer's `{icon_theme}` field can be pre-seeded with such an object to
  drive `_IconName` against a chosen theme.
- Use `add_search_path`, never `set_search_path`, when adding `pix/`.
  `set_search_path(['pix'])` replaces the whole path, so the host theme
  directories disappear and every standard name becomes unresolvable. That
  briefly looked like the resolver preferring bundled artwork.
- **The icon theme inside `tools/run-gtk4-smoke` is Adwaita, not the
  desktop's.** The runner unsets the session bus, so GTK cannot read the
  icon-theme preference. Separately, its temporary `XDG_DATA_HOME` hides
  `~/.local/share/icons`, so a theme installed there keeps its name in
  gsettings while its files are unreachable. Any assertion about specific
  artwork must be written against Adwaita, or accept either spelling.
- Do not hard-code a full-colour freedesktop name in a test expectation.
  Adwaita ships many action icons only as `-symbolic`, so a bare
  `application-exit` expectation fails there even though resolution is correct.
- `Gtk4::Button->activate` does not fire a button's `clicked` handler in a
  test: it needs a mapped, focusable widget and silently leaves the command
  undispatched. Emit `clicked` instead, which is the signal a real click
  raises, as `t/gtk4/20_Paned.t` does for its action signals.
- The offline renderer doubles have no GDK display at all, so anything the
  renderer newly reads from the icon theme must tolerate the lookup
  subroutine being absent rather than just returning nothing.
- GTK3 with `-cmd` and no `Net::DBus` exits 2 at `gmusicbrowser.pl:512`. With
  `-nodbus` it does not hang because the command was lost — it hangs because
  `Quit` is not in the `%Command` fifo table, so `run_command` warns
  `Unknown command 'Quit'` at line 1716 and the main loop continues. Use
  `SIGTERM`, which `gmusicbrowser.pl:1938` wires to `Quit`, or just run
  `make test-gtk3`. Either way gmusicbrowser outlives `timeout`, so budget for
  cleaning up stray `gmusicbrowser.pl` processes; it also ignores a `SIGTERM`
  sent before the main loop is reached, so a `SIGKILL` fallback is needed.
- Do not isolate `XDG_RUNTIME_DIR` for a GTK3 run. `use Gtk3 '-init'` at
  `gmusicbrowser.pl:26` initialises GDK at compile time, so a temporary runtime
  directory with a symlinked Wayland socket yields `cannot open display` before
  any application code runs. Isolate config, data, cache, and state only, and
  add `-demo` so the run never writes tags or settings.
- A fixture with several top-level containers gives the parser several roots,
  and `Render` requires exactly one. Nest the extra containers by naming them
  as children of the root, as `t/layouts/buttons.layout` does.
- A container's own options go **after** the `=`: `VBroot= (minwidth=320) ...`,
  which is what `gmusicbrowser_layout.pm:1001` reads. `VBroot(minwidth=320)=`
  does not error — the parser just stops seeing `VBroot` as a container
  declaration, and the layout silently ends up with an extra root.
- `set_size_request` raises a minimum on a mapped Wayland window but cannot
  shrink it, the counterpart of the `set_default_size` limitation. So an
  assertion that a widget is *allocated* at least its `minwidth` is vacuous in
  a window already wider than that, and will pass against a renderer that
  ignores the option entirely. Assert the minimum itself with
  `measure($orientation,-1)`, which returns
  `(minimum, natural, min_baseline, nat_baseline)`, and pair it with a control
  on a sibling that has no such option.
- `get_size_request` returns `-1` for an unset dimension in both GTK3 and GTK4
  through this binding, which is why the legacy `ApplyCommonOptions`
  read-then-merge ports unchanged. Verified against GTK3, not assumed.
- The offline doubles in `t/04_Gtk4LayoutRenderer.t` must reproduce the `-1`
  unset convention, not `0`/`undef`, or a merge test passes for the wrong
  reason.
- `Layout::Button` shows the widget-table `text` only when `with_text` is set
  (`gmusicbrowser_layout.pm:3047`) or when there is no `stock` at all (3062).
  For `Next` and `Prev`, which both have a `stock` default, `_"Next"` and
  `_"Previous"` never reach the GTK3 UI. Do not treat a widget-table `text`
  field as a visible label without checking that path.
- Widget usage counts in `layouts/` need care and have been recorded wrong
  three times. `grep -c` overcounts via `group=Next` and three
  `titlebar.layout` `Name=` lines; a line-based grep undercounts because one
  line often holds `Prev Stop Play Next`; and splitting each line on `=` misses
  the continuation-line children in `contrib.layout` and
  `makeitlooklike.layout`, which start with whitespace and carry no `=`. Verify
  any figure against a hand-checked listing. The real instance counts are
  **34** `Next`, **29** `Prev`, **20** `Stop`.
