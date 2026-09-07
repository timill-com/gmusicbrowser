# Session handoff

Status: the tree is clean. The most recent session did **two** probe increments
after re-verifying the baseline: the **M1 100k-row list-model probe**
(`t/gtk4/70_ListModel.t`) and the **M1 custom-drawing probe**
(`t/gtk4/80_Drawing.t`). Between them they answer **both halves of D010**, which
is now ready to settle rather than probe. **D039** records the user's answer on
how to modernize `RunPerlCode`.

**The three M1 probes still BLOCKED no longer gate any layout work** — drag and
drop, async finish/error, and GStreamer loop coexistence are transfer, playback
and packaging concerns. That is a change from every previous session, where a
blocked probe sat in front of a widget group.

## Read before choosing tomorrow's increment: SCALE_AND_TOOLING.md

`docs/modernization/SCALE_AND_TOOLING.md`, written 2026-09-08, answers the
user's two questions — how far the port is, and whether more tooling would speed
it up. Two things in it change the priority order and are not recorded anywhere
else:

- **Only 4 of 76 bundled layouts render at all (5%).** Measured by rendering
  every layout in the catalog headlessly and catching the failure. That is a
  harsher and more useful measure than the 20.2% instance coverage, because a
  layout at 95% of its widgets is still a layout that does not open.
- **`MB` is the biggest single unlock, at 15 layouts blocked** — ahead of
  `SimpleSearch` at 11. Instance counting ranks `MB` nowhere near the top (19
  declarations against `MenuItem`'s 99 instances), which is why four sessions
  of priority lists put `MenuItem` first. `MB` is what those layouts hit
  *before* they reach a `MenuItem`, and D038's interpreter is already built
  behind it.

**Those two figures came from a scratch prototype and have no committed tool
behind them yet**, so they are measured but not reproducible from the
repository. Building `tools/layout-coverage` is the first recommended increment
partly for that reason. The user asked for the whole assessment to be written
down for review, which is what that file is.

## Most recent increment: the custom-drawing probe

`t/gtk4/80_Drawing.t`, 32 assertions on real Wayland.

**Both GTK4 drawing paths are closed through this binding, and both look open
until they are called** — which is the finding, and the reason it needed a probe
rather than a reading of the docs:

- **`Gtk4::DrawingArea` constructs and `set_draw_func` is accepted without
  complaint.** Mapping the widget then dies: the callback would be handed a
  `CairoContext`, whose GType is not registered with gperl. The draw function
  never runs even once. Loading the `Cairo` module first does not register it,
  before or after `try_init`.
- **`Gtk4::Snapshot` constructs and `Gdk::RGBA` is fully usable**
  (`parse('red')` → `rgb(255,0,0)`), so the natural first read of the failure —
  "my colour argument is wrong" — is wrong. It is the **geometry**:
  `append_color` and `translate` die on the unregistered graphene types, and
  `to_node` on `GskRenderNode`. There is an assertion pinning that the error
  names `GrapheneRect`, precisely to stop the next session re-debugging the
  colour.

**Consequence for D010, and it is a strong one: option 2 (a purpose-built
virtualized snapshot widget) is not merely unattractive, it is unavailable.**
There is no way to emit a render node from Perl.

**What works is composition, the same move as `AB` under D030.** The standalone
`Cairo` module is independent of the introspection binding and still renders:
draw into a `Cairo::ImageSurface`, wrap `get_data` in a `Glib::Bytes`, build a
`Gdk::MemoryTexture` with the surface's own stride, and show it through a
`Gtk4::Picture`. The probe reads the pixels back with `download` and checks them
(BGRA, so a red row is `0,0,255,255`), maps the result on screen, and swaps the
paintable to prove a repaint.

**So the legacy drawing *code* is portable even though the legacy *callback* is
not**, and that matters more than it sounds: `Skin::draw`
(`gmusicbrowser_layout.pm:5737`) already caches a pixbuf per state and size and
paints it, so it composites a cached image rather than drawing live vectors.
It is close to the shape the texture route wants. CSS already covers the flat
backgrounds and borders (D031, D032).

**Not measured, and excluded from any claim:** the cost of this at list scale.
The probe swaps one texture, not a viewport of them during a scroll. That is
the next thing to measure before committing to a SongTree design.

### Method note

The `DrawingArea` failure is only visible because `$app->run` is wrapped in an
`eval`. Inside a signal handler Glib catches the error and prints `unhandled
exception in callback` to stderr, so an assertion written there passes blind —
the same trap D006 records for `get_current_event`, hit again in a new place.

## Most recent session: the 100k-row list-model probe

`t/gtk4/70_ListModel.t`, 54 assertions on real Wayland. Chosen with the user
over the menu increment, after measuring that a naive `MenuItem` port would
deliver **14 working items out of 99** — see the command-registration section
below, which is now in `PROGRESS.md`.

**The headline: the list/model stack carries a library-sized model comfortably.**
100,000 rows build in 0.12s (`StringList`) or 0.27s (`Gio::ListStore` of
Perl-defined GObjects); random access, `SingleSelection` and a 50,000-row
`MultiSelection` range are all effectively free; and the
`SignalListItemFactory` allocates **205 row widgets for 100,000 rows**,
recycling them on scroll (setup 205 -> 206, bind 205 -> 410, 204 unbinds). So
D010's option 1 is no longer speculative, and nothing argues for option 2 on
performance grounds any more.

**Four binding limits, each now asserted and in D006:**

- **`GtkExpression` is unmarshallable**, like `GdkEvent` and the graphene
  types. `StringSorter`, `NumericSorter` and `StringFilter` therefore
  **construct but cannot be configured** — a case where construction is not
  evidence of usability, which is worth generalising.
- **`CustomSorter` receives `undef` for both items**, so the documented escape
  hatch is unusable and **sorting has to happen in Perl** over the backing
  list — 1.1s at 100,000 rows, and the same shape legacy already uses.
  `CustomFilter` *does* receive its item, so filtering in Perl works.
- **`Gio::ListStore::splice` corrupts the store with custom GObjects**: it
  passes nulls, GIO logs "undefined state", and **nothing raises a Perl error**.
  Append in a loop instead (0.14s for 100,000).
- **A Perl-defined `Glib::Object` subclass works fine as a row type.** Do not
  over-generalise D006's vfunc entry into "no subclassing"; it is specifically
  widget layout vfuncs that are ignored.

### Traps that cost real time this session

- **`scroll_to` is what moves a `ListView`; the `ScrolledWindow` adjustment is
  not.** `set_value` moves the value and nothing else, so my first recycling
  measurement read "no recycling at all" and looked like a binding limitation.
  The suite now pins that non-behaviour with its own assertion.
- **A failed `splice` cannot be cleaned up, and the crash lands nowhere near
  the cause.** The corrupted store segfaults when *freed*, several assertions
  later, only in a process holding other GTK objects. `prove` reported
  "All 47 subtests passed" *and* a SEGV with no plan. Found by truncating the
  test file at successive line numbers and re-running — a bisect on the test
  itself, which is the transferable technique. That assertion now runs in a
  child process.
- **I re-derived a known D006 rule the hard way.** Several scratch probes
  segfaulted at exit; I chased it through ListView, ColumnView and even
  `Gtk4::Label` before realising the scripts called `try_init` without
  `backend_probe`, which D006 already records as a segfault. **Read the
  evidence list before debugging a crash in a scratch script**, not just before
  writing production code.
- **A bare `prove` misreports the whole GTK4 suite.** Without `GMB_GTK4_SMOKE=1`
  and the isolated XDG environment, `00_Binding.t` reports 19 TAP / 6 skips
  instead of 18 / 4 and every other file reports 0. Copy `tools/run-gtk4-smoke`,
  add `-v`, and run the copy **from `tools/`** so its `gmb_root` resolves.

### The menu numbers, re-derived and confirmed

The previous handoff's warning holds exactly. From the parser catalog:
`MenuItem` is **99** = 69 command-only + 28 `togglewidget` + 2 neither;
**20 distinct `command=` values** across all bundled widgets, of which only
**six** are registered; **only 14 of the 69** use a registered one. `RunPerlCode`
is 23 instances. `PROGRESS.md` now carries this and the command to re-derive it.

### D039 — how to modernize `RunPerlCode`

The user answered the design question with a direction rather than a menu
choice: "How can we mordernize? I am not familiar with perl at all.. But
basically we should modernize as much as we can."

What makes an answer possible is a measurement: across every bundled layout and
plugin there are **exactly five distinct `RunPerlCode` expressions**, and all
five are plain calls to named core subs with constant arguments. So the `eval`
is a generic mechanism carrying five knowable actions. D039 proposes registering
those five as named commands, passing `ChooseAddPath`'s arguments as command
parameters, keeping `RunPerlCode` working unchanged in GTK3 (D002), and
reporting an unrecognised expression through `Unhandled` in GTK4 rather than
evaluating it. **Status Proposed, not Accepted** — it widens `%Command`, which
is shared code and needs a GTK3 pass, and it should be done as one increment
covering the whole 14-command registration gap.

## Earlier session: the `FB` packing prefix (D035)


**How it was found is the transferable part.** The task was to scope the
song-field state path with the user. Sizing the smaller alternatives first —
rather than taking the previous handoff's descriptions on trust — showed two of
them were mis-scoped, and one of those mis-scopings was a live parser defect.

`_extract_children` translated the packing prefix for `HB`/`VB`, `HP`/`VP` and
`TB`, three of the **six** `Prefix` regexes in `%Layout::Boxes::Boxes`. `FB`'s
was missing, so `FBLower= .1,0,.8,0 HBLower` parsed into a phantom widget named
`.1,0,.8,0` (element `.1,0,.8,` — the numeric-suffix rule stripping the last
digit) plus the real container with empty packing. **0 diagnostics.** The fix is
a three-line branch using the legacy regex verbatim.

### Two corrections to the previous handoff's alternatives list

- **`FB` is not a small increment.** It was listed as one because "`Gtk4::Fixed`
  works". `Gtk4::Fixed` is only the static half; both bundled uses are the
  fractional form, and all of that behaviour is in `SFixed`'s `size_allocate`
  override (`gmusicbrowser_layout.pm:2443`) — precisely the vfunc route D006
  proves silently ignored. A port needs a layout manager, as `AB` got in D030.
- **`TB` is not fixture-only.** Recorded as having one bundled use holding three
  unimplemented widgets. There are **two** live uses, and `main.layout:22`'s
  `TBRight` holds `VPRight`, an implemented pane, plus `Context`. It is the most
  reachable container increment left.

### A counting trap that silently reports nothing

Container names carry **word** suffixes, not just numeric ones: `TBRight`,
`FBLower`, `NBSidebar1`. A catalog walk filtering `^(TB|FB)\d*$` matches zero
nodes and looks like "the feature is unused" rather than "my filter is wrong".
Filter on the `{element}` field, or anchor only the prefix. The documented
numeric-suffix rule is about *elements* (`Label3` → `Label`); it does not
describe container declaration names.

### What did NOT change, and why

`contrib.layout:78` has `#VolumeIcon #_VolumeSlider(horizontal=1)` mid-line, and
the catalog counts both as widget instances. That looked like the same class of
defect. It is not: legacy strips only whole-line comments (`ReadLayoutFile`:
`next if m/^#/`) and `InitLayout` turns each unresolvable name into a
`Layout::PlaceHolder`, so the parser already agrees with legacy. **Checking the
legacy behaviour before "fixing" it is what kept this from becoming a D002
violation.** The instance total is therefore 1161, not 1159.

### Verification

- `make test-modernization` 473 → **484**, 0 skips.
- `make test-gtk4` unchanged at **346** TAP (340 executed + 6 pre-existing M1
  skips; per file 18/4/84/166/74, counted from `prove -v`).
- `make test-gtk3` passes, exit 0.
- Pristine `git archive HEAD` comparison: **11 of 56** fail, exactly the new
  assertions, 45 controls passing on both trees.
- **GTK3 exposure is nil and was checked, not assumed:**
  `gmusicbrowser_layout_parser.pm` is required only by `gmusicbrowser_gtk4.pl`.
  GTK3 reads layouts through its own `ReadLayoutFile`/`InitLayout`. `make
  test-gtk3` was run regardless.

### Still true after this increment

The song-field state path remains the bottleneck and is **unstarted**. It needs
a documented extension to `FRONTEND_CONTRACT.md` — frozen for the first slice —
because the contract can say *which* song is current (`CurSong` emits
`{id=>...}`) but has no way to resolve an ID to field values. It also needs a
fixture song source, since `gmusicbrowser_gtk4.pl` has no library at all. Scope
it with the user before writing code.

## Most recent increment: the menu interpreter (D038)

`gmusicbrowser_gtk4_menu.pm`, plus `t/07_Gtk4Menu.t` (64 offline) and
`t/gtk4/60_Menu.t` (25 on Wayland). All 12 conditional filters and all four
structural operators are carried, and the model is rebuilt per popup.

**Three findings, each of which cost a wrong first attempt:**

- **`append_section` does not group what follows it.** Appending an empty
  section where the separator sits leaves later entries at the top level and
  counts the empty section as an item — `get_n_items` read 6 where 2 was
  expected. The definition is now split into runs first, each run becomes a
  section, and a single run stays flat. **The offline double had faithfully
  reproduced the wrong model, so only the real Gio exposed this** — which is the
  case for keeping a Wayland test beside every offline one.
- **An entry carrying `code` takes the choice-menu path whatever its submenu's
  type** (legacy's order at `gmusicbrowser.pl:4742`), because an `ordered_hash`
  submenu is an array of alternating labels and values, not a definition.
  Dispatching on the submenu's type — the natural-looking reading — dies with
  `Can't use string ("Main") as a HASH ref`. **Found only by building the real
  `@TrayMenu` shape.** Every hand-written fixture had the convenient shape and
  passed. *Test a ported interpreter against a definition it did not author.*
- **`include` receives the menu as its second argument and both bundled
  callbacks use it** (`gmusicbrowser_layout.pm:25`, `:40`) to append in place via
  `BuildChoiceMenu(menu=>$menu)`, returning nothing. Dropping that argument
  looked harmless and silently broke both.

**On evidence, stated plainly: a new module cannot fail meaningfully against a
pristine tree.** The pristine run dies at `require` with **0 assertions
executed**. Do not report that as discrimination. What validates this instead is
that **29 assertions compare against the legacy conditions transcribed verbatim
and executing in the same process**, with two guards requiring that some cases
skip and some are kept.

**Not done, and excluded from any coverage claim:** no layout `MenuItem`
instance renders yet. This is the mechanism; placing a menu in a layout needs
the `MB`/`SM`/`BM` containers. The 23 `gmusicbrowser_list.pm` call sites still
await `SongList`. `submenu3`/`code3` are reported through `Unhandled` because a
right-click alternative needs a button number a model item does not carry.

## Standing direction set by the user: D036, D037, D038

Three decisions taken after the input probe, recorded because they govern every
future design choice rather than one increment.

**D036 — GTK4 standard, but all layouts keep working.** The user's words: "for
all design changes needed, I would say to respect GTK4 as much as possible, and
the standard here ... but we shall keep all the layouts working." Clause 1 picks
the native convention; **clause 2 says layout compatibility wins where they
conflict**, and that ordering is the load-bearing part. `Shimmer Desktop` is
named as the reference layout — the one the user actually uses.

**Do not optimise toward Shimmer Desktop yet.** It is the *least* covered
bundled layout: 5 of 45 own instances, 11%, against the 20% average, because it
uses close to one of everything — 4 `FilterPane`, 4 `ToggleButton`, 5
`MenuItem`, `SongTree`, `SongList`, `QueueList`, `Stars`, plugin widgets, and
the `NB`/`BM`/`SM` containers. It also opens with widgets hidden and declares
`DefaultFocus`/`KeyBindings`. It is a late acceptance target, not a next step.

**D037 — desktop icon theme only, plus a three-state dark/light toggle
defaulting to system.** The user asked for "desktop theme only ... but we should
have possibility to toggle dark and light also in app but default to system",
which is more than the option offered, and the addition is the substantive part.

Measured, because the obvious routes fail: **libadwaita is absent** so
`AdwStyleManager` is unavailable; `gtk-application-prefer-dark-theme` has no
GTK4 effect (already in D006); and **switching `gtk-theme-name` is not a usable
toggle** — setting `Adwaita`, a light theme, left the colour at
`0.93,0.93,0.93`. A display-level `GtkCssProvider` *does* work exactly and
reversibly. **Trap worth carrying forward: probe a colour mechanism with a
colour the theme could never produce.** The first probe used `#eeeeee`, read
0.93, and looked like "CSS is partly ignored"; `rgb(255,0,0)` gave
`1.000,0.000,0.000` and an unambiguous answer. This host is already dark, so
every honest dark value sits near every other one.

**D038 — menus port the interpreter, not the instances.** The user first chose
to port the whole subsystem, then, after being shown what reading `BuildMenu`
revealed, kept that scope with an interpreter framing. **`BuildMenu`
(`gmusicbrowser.pl:4670`) is an interpreter**: 14 conditional filters per item
plus `foreach`/`include`/`repeat`/`change_input`, all evaluated at popup time
from live state — close to the opposite of `GMenu`'s declarative model. There
are **50 call sites across 6 files, 23 of them in `gmusicbrowser_list.pm`**,
which is unported, so those cannot be exercised until `SongList` exists and must
be reported rather than claimed.

**Method note: the risk was found *after* the user had already chosen, and was
put back to them instead of being absorbed silently.** That is the right move
when new information changes what the choice meant.

## Most recent session, second increment: the M1 input-controller probe

`t/gtk4/50_Input.t`, 27 assertions. Chosen over the bigger rendering groups
because it was the only blocked probe that **every** other group depends on,
and because of a consequence that had gone unstated: `PARITY_CHECKLIST.md`
requires pointer and keyboard evidence before any row reaches `Parity review`,
so with zero event controllers in the renderer **no widget could ever be marked
done** regardless of how many rendered. That is why the checklist had no row at
parity.

Result: the binding carries the whole legacy input surface. Click, motion,
scroll, and key controllers construct and fire with correct payloads. Full
detail is in D006; the three findings that constrain a port:

- **`GdkEvent` is unmarshallable** (`get_current_event` dies), so a handler's
  own arguments are the entire payload. **Inside a signal handler Glib swallows
  the error and prints to stderr**, so an assertion written there passes without
  ever seeing the failure — I hit exactly that, and moved the check outside the
  handler where `eval` can catch it.
- **A synthetic press reports button 0** however the gesture is filtered, so a
  port needs **one gesture per button** via `set_button`, matching the legacy
  `'click'.$event->button` contract at `gmusicbrowser_layout.pm:1284`.
- **Baseline controller counts differ by widget type** (box 0, label 1, button
  3), so a test must identify a controller, never count them.

**This probe passes identically on a pristine tree, and that is stated in the
commit rather than glossed.** It tests the binding, not project code, so there
is no old implementation for it to fail against; its value is the measurement.
Do not read its "passes on both trees" as a weak test — read it as the reason
the usual pristine-discrimination rule does not apply to gate probes.

`t/gtk4/00_Binding.t`'s input skip became a real assertion, so the suite is now
**373 TAP = 368 executed + 5 skips** (was 346 = 340 + 6). Four M1 probes remain
BLOCKED: 100k-row `GListModel`, custom drawing, drag and drop, async
finish/error, and GStreamer loop coexistence.

**`PROGRESS.md` now carries a dependency-ordered route for the rest of the
port** — the four remaining widget groups, which probe gates each, and the two
things that need a user decision rather than code (extending the frozen
`FRONTEND_CONTRACT.md`, and the `GMenu`/`PopoverMenu` model).

## Earlier session: three increments and a progress overview

- the layout-wide `DefaultFont`/`DefaultFontColor` globals are now inherited
  by every label (**D032**), closing D031's deferred alternative 5;
- a **static** `markup=` is now applied (**D033**);
- the legacy `HSize`/`VSize` size groups are applied through
  `Gtk4::SizeGroup` (**D034**).

**New: `docs/modernization/PROGRESS.md`** is the "where are we overall" view —
measured coverage, what is implemented, the current bottleneck, and the test
position. It is linked from `MODERNIZATION.md` and required by `AGENTS.md`.
Start there; this file is the working notes and the checklist is the per-row
detail.

**Read D033 and D034 before letting any option or instance count drive a
decision.** Between them they correct seven recorded figures, and every error
had the same cause: a grep over `layouts/` cannot tell a layout block from a
`{Group}` skin block, a live line from a comment, a widget's `icon=` from the
layout's `Icon=` metadata, or a widget instance from a size-group declaration
that merely names one. The reliable method is to walk the parser's own
catalog.

## Earlier session, third increment: `HSize`/`VSize` size groups

Found by chasing a discrepancy, which is worth noting as a method: the recorded
widget instance counts disagreed with the parser's, and the reason turned out
to be an unimplemented feature.

Size groups are `gmusicbrowser_layout.pm:1056-1070`. The parser already
recognised the `[HV]Size\d*` spelling and kept them in `{definitions}`,
correctly outside `{nodes}` since they declare no container. The renderer never
read them. **27** declarations across the bundled layouts.

`GtkSizeGroup` survived into GTK4 unchanged, so this is a **direct, lossless**
translation — the first such in a while. Measured: all four modes construct,
`add_widget` raises a 36px label to a grouped 180px, `remove_widget` reverts
it, `get_mode`/`get_widgets` read back.

Three details that matter:

- **A leading number naming a single widget creates no group at all.** That is
  the `next if @names==1` early exit at `:1063`, and it is **12 of the 27**
  bundled uses — the common case, not an edge one. Implementing only the
  grouping would have missed the majority.
- **Where both apply, the group wins.** `HSize1= 120 Text5 Text6` requests 120
  and then groups, so the shared width is the widest member's natural width,
  which can exceed 120.
- **Groups are applied after the tree is built**, as the legacy does, because a
  declaration names widgets *and containers* that must already exist. Both are
  in the same `{widgets}` hash, matching the legacy's single hash, so
  `VSize0= 300 HBCover` resolves.

An unresolvable name is recorded through a new `UnhandledSizeGroups` accessor
rather than warned about as the legacy does (`:1068`), and the members that
*can* be resolved are still grouped.

### Two test traps this increment hit, both already recorded in other forms

- **The offline block aborted the whole file and hid fourteen assertions.**
  `@{$renderer->{size_groups}}` dies on a renderer that creates no groups, so
  the pristine run stopped at the first new assertion having reported
  everything before it as passing. Guarding with `|| []` is what lets pristine
  reach and fail them honestly. Same trap the `Filler` increment recorded.
- **One assertion was vacuous and pristine caught it.** `is($t5w,$t6w)`
  compared two labels that on the old renderer *both* measured 7 — equal
  because neither was touched. The fixture now gives them clearly different
  natural widths, and the assertion is paired with one that the shared width
  exceeds the requested number. Same class as D030's two.

### Verification for this increment

- `t/gtk4/30_Box.t` fails **6 of 166** against pristine on real Wayland;
  `t/04_Gtk4LayoutRenderer.t` fails **8 of 308** offline.
- Pristine failure values confirmed as the right reason: `got 7 / expected 180`
  for the equalisation, `21` against `40` and `7` against `120` for the
  requests.
- Only `UnhandledSizeGroups` needs stubbing into the pristine copy;
  `_ApplySizeGroups` was confirmed absent before the comparison was trusted.
- Controls passing on both trees: `an ungrouped label in the same row keeps its
  own width`, `a widget named by no numbered size group keeps an unset
  request`, the two "does not become a root/widget" assertions, and the
  `Destroy` bookkeeping.

## Earlier session, second increment: a static `markup=`

`markup=` looked like the largest remaining prize and the one thing needing the
song-field state path. Reading `Layout::Label` first showed it is **two
options**, split in the legacy code itself at
`gmusicbrowser_layout.pm:3156`: a value `::UsedFields` finds fields in
subscribes through `WatchSelID` and re-renders per song; anything else is set
once with `set_markup`. The second half needs no state, so it is a
self-contained increment. Recorded as **D033**.

**The count correction matters more than the code.** The docs recorded 76 uses.
That is right for `[(,] *markup=` across `layouts/` and still the wrong figure
for a renderer increment, because it reconciles as:

| | count |
|---|---:|
| real `markup=` options in layout blocks | **56** |
| SongTree drawing-layer uses in `{Group ...}`/`{Column ...}` skin blocks | 19 |
| commented-out layout-block line | 1 |
| total matching the recorded grep | 76 |

The 19 are the `text(markup=...)` drawing DSL, with `pesc()`, `.`
concatenation, `$_row` and `myfont`. No label port will ever reach them — the
same class as the already-recorded `shimmer.layout:132` `color='#ccc'` trap.
The 56 was confirmed by walking the parser's own catalog, not by grep.

**Of the 56, exactly 2 are static, and both land on implemented widgets:**
`Text(markup="/")` at `makeitlooklike.layout:481` and `Label0` with an
`xx-large` span at `shimmer.layout:119`. The other 54 name fields and stay
reported.

### Malformed markup, which is where the real work was

GTK4 gives no usable signal, measured through this binding:

- `set_markup` does **not** die on a malformed value.
- Its warning is a **GTK** warning on stderr, not a Perl one —
  `$SIG{__WARN__}` captures nothing, so it cannot be trapped.
- On failure it leaves the **displayed text untouched** while `get_label` still
  returns the raw string. So the widget silently keeps whatever it had.
- `Pango::parse_markup` is undefined, consistent with the recorded "Pango is
  unreachable through the GTK4 binding", so there is no validator to ask.

The renderer therefore sets the markup over a sentinel the markup itself cannot
produce and checks whether the text moved. A refused value falls back to
`set_text` of the raw string, so a typo shows its own source rather than
producing an invisible widget, and the option is reported.

**A refused value still prints one GTK warning to stderr.** Two appear during
`make test-gtk4`, one per refused fixture value. They are expected; do not hide
them.

### The wrong reading I nearly implemented

The first probe concluded "on failure `get_text` returns empty, so empty means
refused." **That was an artifact of the probe's own fixture** — the labels were
built with `Gtk4::Label->new('')`, so the *retained previous text* was empty.
Re-probing over a non-empty label showed the failure leaves the previous text
intact (`SENTINEL`, then `previous`).

Had it been implemented, a valid `<b></b>` — which legitimately renders nothing
— would have been reported as refused. **Probe a retained-state behaviour from
a non-default starting state**, or the default masks what is actually retained.

The full validation table, from the real binding: `<b>closed</b>`, `plain`,
`/`, `` (empty), `<b></b>`, `<span size="xx-large" ...>X</span>`, `&amp;` and
`<i>a</i> &amp; <b>b</b>` all valid; `<b>unclosed`, `a &badentity; b` and
`<unknowntag>x</unknowntag>` all refused. The offline double's markup stripper
was validated against **all 11**, rather than written to satisfy the test.

### Field detection without the shared table

`::UsedFields` (`gmusicbrowser.pl:1012`) maps `%<letter>` through
`%::ReplaceFields` and keeps only defined letters. That table is built at
`gmusicbrowser_songs.pm:1935` from the song field definitions — shared core the
renderer must not load. So `_MarkupUsesFields` counts **any** field sigil
instead.

The divergence is deliberately on the safe side (an unmapped `%X` is reported,
not drawn literally) and changes nothing for the bundled layouts: every sigil
in their `markup=` values is a real field — `%a` 13, `%t` 13, `%l` 12, `%s` 7,
`%y` 3, `%m` 2, `%Y` 1, `%g` 1, plus the `$album`/`$artist`/`$length`/
`$title_or_file`/`$track` aliases.

### Verification for this increment

- `t/gtk4/30_Box.t` fails **6 of 157** against a pristine `git archive HEAD`
  on real Wayland; `t/04_Gtk4LayoutRenderer.t` fails **10 of 293** offline.
- Pristine failure values confirmed as the right reason: every markup label is
  empty, and the precedence assertion fails `got 'ignored' / expected 'big'`,
  which is the `text=` the old renderer shows.
- The offline comparison needs `UnhandledGlobals` and `_MarkupUsesFields`
  stubbed into the pristine copy. `_Markup`, the sentinel, and the
  `%LabelHandled` entry were confirmed absent before it was trusted.
- **Every "is reported" assertion is a control here**, because pristine reports
  `markup` for *all* values, being wholly unimplemented. What discriminates is
  the rendering: `get_text` against `get_label`, the `xx-large` measurement,
  and the precedence over `text=`.
- Eight assertions check the validation sentinel never survives on any label —
  on the applied, refused, and field-bearing paths. Controls, but they guard the
  one way this mechanism could leave a visible artifact.

## Earlier session, first increment: layout-level option inheritance

`DefaultFont` and `DefaultFontColor` are layout properties, not widget
options. Legacy `InitLayout` reads them into `{global_options}`
(`gmusicbrowser_layout.pm:971`) and `NewWidget` merges that hash into every
widget (`:1162`). The parser already kept both in `$layout->{metadata}` — the
renderer simply **never read `{metadata}` at all**, so the whole mechanism was
unimplemented. `Render` now collects them and `_ApplyLabelOptions` falls back
to them per option.

**The precedence trap, which is the most transferable part.** `%$global_opt` is
merged *last* at `:1162`, so the merge order reads as though the global wins.
Neither option lets it: `:1163` is `$options{font} ||= $global_opt->{DefaultFont}`
and `Layout::Label` at `:3120` is `$opt->{color} || $opt->{DefaultFontColor}`.
Both are `||`, so **the widget's own value wins**. Do not infer a precedence
from a merge order without reading what the consumer does with the merged hash.

Three consequences that fell out of implementing it per option rather than as a
pair, all measured on real Wayland:

- **Each global is inherited independently.** A label carrying `font=8` under
  `DefaultFont=20, DefaultFontColor=white` renders at 80% *and* in white.
  Overriding one global must not discard the other.
- **A widget's own refused value is taken rather than falling through to the
  global.** `font=oops` renders at the theme font, not at the inherited ratio,
  because `||` accepts a truthy-but-invalid value.
- **`DefaultFont` reuses D031's `_FontRule`,** so `fullscreen.layout`'s
  `DefaultFont = 20` becomes `200%` of the desktop font for every label in that
  layout at once. The user was asked about that whole-layout scope specifically
  and chose consistency with D031 over an absolute size.

The measured table, from a probe inside the runner:

| label | own options | height | colour | classes |
|---|---|---:|---|---|
| baseline, no globals | — | 21 | theme | none |
| `Text` | — | 41 | `rgb(255,255,255)` | `gmb-font-200`, `gmb-color-white` |
| `Text2` | `font=8` | 17 | `rgb(255,255,255)` | `gmb-color-white`, `gmb-font-80` |
| `Text3` | `color=grey` | 41 | theme | `dim-label`, `gmb-font-200` |
| `Text4` | `font=oops,color=notacolour!` | 21 | theme | none |

An untranslatable global is reported through a new **`UnhandledGlobals`**
accessor rather than the per-widget `Unhandled` list. No widget's options named
it, so attributing it to every inheriting widget would misreport what the
layout actually wrote. `PATH`, `SkinPath`, and `SkinFile` are read into the
same legacy hash and are **not** ported — they belong to the skin machinery.

### The reachability claim in the previous handoff was wrong in both directions

It said this was "reachable from the bundled layouts" only "in a qualified
sense", closer to forward-looking work. Re-checked by dumping the catalog:

- **There are six uses, not five.** `desktop.layout:57` sets `DefaultFont=8`
  in `[D_screenlet]`, which the previous handoff missed entirely while listing
  the other five.
- **One is reachable on an already-implemented widget today.**
  `desktop.layout`'s `[D_clementine]` sets `DefaultFontColor= white` and
  contains `Text5`, a `Text` widget the renderer builds, with no `color=` of
  its own. The previous reading noted that `[D_clementine]` "contains the
  `color=grey` widgets that override it" and stopped there — `Text5` is the
  one label in that block with no `color=`, so it is precisely the inheriting
  case.

So this was a fix to a shipped layout, not forward-looking work. The bad
reading came from checking which widgets carry `color=` rather than which
carry none.

### Verification for this increment

- `t/gtk4/30_Box.t` fails **6 of 143** against a pristine `git archive HEAD`
  on real Wayland; `t/04_Gtk4LayoutRenderer.t` fails **7 of 250** offline.
- Pristine failure values confirmed as the right reason: `21 > 21` for the
  inherited font, because pristine draws every label at the theme size, and
  `got rgb(46,52,54) / expected rgb(255,255,255)` for the inherited colour.
- The offline comparison needs only the `UnhandledGlobals` accessor stubbed
  into the pristine copy — fewer stubs than D031 needed, because the
  inheritance sits on helpers that already exist. `_Globals` was confirmed
  absent from the pristine renderer before the comparison was trusted.
- **Most override assertions are controls, not proofs.** The per-widget
  `font=`/`color=` path already existed, so every assertion about an
  overriding widget passes on both trees. Each new assertion was read
  individually from `prove -v`; the file-level count hides which discriminates.
- One assertion was vacuous as first written and was strengthened: `a widget's
  own color= overrides the inherited DefaultFontColor` asserted only that the
  overriding label lacks `dim-label`, which passes against a renderer that
  never applies `dim-label` at all. It is now paired with an assertion that
  the inheriting and overriding labels differ from each other.
- **The unstyled baseline must come from a separate layout carrying no
  globals.** Every label in a layout with a global inherits it, so a
  within-layout baseline measures the global against itself. The fixture holds
  four layouts for this reason.
- No shared code changed. `make test-gtk3` was run anyway and passes.

## Previous session

The session before this one recorded the user's standing
native-mechanism policy as **D029**, closed `AB`'s fractional alignment gap
through a `Gtk4::ConstraintLayout` (**D030**, superseding the fractional half
of the Accepted D025), and applied the legacy label `font=`/`color=` options
through a `GtkCssProvider` (**D031**).

**Read D031 before touching presentation options.** It is the first place
where D002 fidelity and the goal of letting the desktop theme through actually
conflicted, and the user chose the theme: `font=20` becomes `200%` of the
desktop font rather than 20 absolute points. The measurement that forced the
choice is that **the OS theme font and colours already reach the renderer's
labels with no code at all**, so any styling the renderer adds is an override
of the theme, not a gain.

The decision backlog remained cleared: D023, D024, D025, D026, D027, and D028
were all **Accepted**.

Five were accepted as implemented, with no code change. One was accepted
*against* the entry's own recommendation and became this session's increment:

- **D028 alternative 2** — normalise a label's `ellipsize=1` to `'end'`,
  following `Layout::Button`. The entry originally recommended preserving the
  legacy asymmetry; the user's call was to normalise. The entry has been
  rewritten rather than annotated, and the change is recorded as a
  **deliberate parity exception**, since GTK3 leaves such a label
  un-ellipsized.

What the acceptances did **not** do, and this matters for reading the
checklist: D025 and D026 were accepted *as documented approximations*, so the
`AB` and `WB` rows deliberately stay at `GTK4 in progress`. Acceptance removed
the decision gate on each row without advancing it. No row was advanced to
`Parity review` this session.

Last session: 2026-09-07. Branch `gtk4-alpha`.

**Decision state.** D023–D034 are all **Accepted**. **Eight** entries are
unresolved, all pre-existing and none blocking a layout increment: D006, D007,
D008 and D010 are **Open**, and D009, D011, D012 and D019 are **Proposed**.
An earlier revision of this line named only the four Proposed ones and so
undercounted; D006 (the M1 binding gate) and D010 (SongTree architecture) are
the two that matter for the port's shape. See PROGRESS.md for the table.

Read `MODERNIZATION.md` and `AGENTS.md` first. This file only records where the
previous session stopped and what the next one should verify before continuing.

## This session's increment: label `font=` and `color=` through CSS

`Layout::Label` applies `font=` with `modify_font` and `color=` with
`override_color` (`gmusicbrowser_layout.pm:3118-3122`). GTK4 removed both
per-widget overrides, so each becomes a style class on one
`Gtk4::CssProvider` the renderer installs on the display and releases in
`Destroy`. Recorded as **D031**.

**The finding that shaped the whole design: the OS theme already works.** The
desktop font is `Roboto 10`, an unstyled `Gtk4::Label` measures 19x17, and
GTK3 on the same host reports the same font and the same 19x17. So the
renderer already inherits the desktop's font and colours; `font=`/`color=`
are overrides of that, which is the opposite of the framing the previous
handoff implied.

**`font=` is theme-relative.** A legacy `font=20` becomes `200%`, fixed
against the 10pt GTK3 baseline the bundled layouts were authored against:

| desktop font | unstyled | `font=20` | `font=8` |
|---|---:|---:|---:|
| Roboto 10 | 17px | 32px | 13px |
| Roboto 16 | 26px | 51px | 21px |
| Roboto 8 | 13px | 26px | 11px |

Identical to GTK3 at the baseline, a deliberate parity exception away from it.

**I got this wrong once and had to correct it mid-increment, which is the most
transferable part.** The first implementation derived the percentage from the
*live* theme size. That cancels out — `20/16 * 16pt` is `20pt` again — so it
reproduced the absolute legacy size exactly and the desktop font never reached
the widget. It looked theme-aware because the emitted class changed (`200%`
then `125%`) while the rendered size did not. **A ratio only follows the theme
if it is fixed against a constant baseline.** Check a "relative" translation by
varying the theme and reading the *rendered* size, never the emitted rule.

**`color=grey` becomes `dim-label`**, GTK4's de-emphasis class, which follows
the theme and its dark variant; every bundled `color=` use is a grey. A
non-grey is emitted literally. A grey is a named grey or a hex with equal
channels, so `#ccc` and `#888888` classify together.

Four things worth carrying forward:

- **`dim-label` has no observable.** It styles by opacity at draw time, so
  `get_color` returns the unmodified theme colour and `get_opacity` returns 1.
  `has_css_class` is the only check, which makes the grey path construction
  coverage. An explicit colour *is* readable through
  `get_style_context->get_color`.
- **A CSS rule body needs a trailing semicolon** or GTK warns `Expected ';' at
  end of block` for every rule — while still applying it, so the warning is
  the only symptom. `load_from_data` also needs the byte length as a second
  argument.
- **A `font-size` assertion only discriminates away from the theme size.** At
  `Roboto 10`, a `10pt` rule measures identically to no rule at all. Same
  class of trap as the 16px icon default.
- **Do not double `Gtk4::Gdk::Display` in the offline file.** The absence of a
  display is what makes `_IconTheme` return undef and every icon fall back to
  text. I added the double to make the CSS provider work offline, noticed it
  had quietly weakened that invariant, and removed it again. The offline file
  now asserts the *reporting* path instead, with rendering proved on Wayland.

### Verification for this increment

- `t/gtk4/30_Box.t` fails **8 of 124** against pristine on real Wayland;
  `t/04_Gtk4LayoutRenderer.t` fails **14 of 230** offline.
- Pristine failure values confirmed as the right reason: `21 > 21` for the
  font measurement, because pristine draws every label at the theme size, and
  `got rgb(46,52,54) / expected rgb(255,255,255)` for the explicit colour.
- The offline comparison needs `_IsGrey`, `_ColorRule`, `_FontRule`, and the
  baseline constant stubbed into the pristine copy, or the helper block dies
  before its assertions run.
- Controls pass on both trees: every "is not a grey" and "is refused"
  assertion, `a label with no font= gets no font class`, `an unparseable font=
  leaves the theme font alone`, and the three `Unhandled` assertions for
  values pristine also refuses.
- No shared code changed. `make test-gtk3` was run anyway and passes.

### What this increment did NOT cover

`DefaultFont`/`DefaultFontColor` inheritance was deferred as D031 alternative
5. **Done this session as D032**; see the top of this file.

Also note the four bundled `font=` uses are all on
`Title`/`Artist`/`Album`/`Date`, none of which the renderer builds yet, so
`font=` is exercised only by the fixture until those land. `color=` on `Text`
is reachable today. And `shimmer.layout:132`'s `color='#ccc'` is a
**drawing-layer** option, not a label option — do not count it as a fifth
label use.

## This session's increment: `AB` fractional alignment via a constraint layout

`AB` is the legacy `Gtk3::Alignment->new(xalign,yalign,xscale,yscale)`
(`gmusicbrowser_layout.pm:2333`, defaults `.5,.5,1,1`). D025 accepted
bucketing those four numbers into GTK4's three-valued `halign`/`valign`, which
loses a fractional alignment (`0.3` collapsed to `start`) and a fractional
scale (`0.5` became a full fill). D030 closes both.

**The gap was closable because `Gtk4::ConstraintLayout` reproduces
`GtkAlignment` exactly.** Measured against `Gtk3::Alignment` on the same
fixture, the same 400px slot and the same label child, under `LC_ALL=C`: 14 of
15 fractional `xalign`/`xscale` combinations agree exactly, one differs by 1px
from constraint-solver rounding. The table is in D025's evidence section.

The arithmetic, per axis, as two constraints:

	size = scale*slot + (1-scale)*minimum
	pos  = align*(1-scale)*slot - align*(1-scale)*minimum

The second is the substituted form of `align*(slot-size)`, which keeps each
constraint linear in one source term as `GtkConstraint` requires. `minimum`
comes from `measure($orientation,-1)`, which returns the right value before
realization.

**The common path deliberately does not change.** A constraint layout is
installed only where a value has no enum equivalent; `0`, `.5`, `1` and a
0-scale keep the plain property path, which is every value that appears in
`layouts/`. Five assertions pin that, and they pass on both trees.

Four things worth carrying forward:

- **A scale of `.5` needs the constraint path even though an alignment of `.5`
  does not.** `center` expresses a half alignment; nothing expresses "half
  fill". Getting this wrong is what made the first run leave `ABscale` on a
  `Gtk4::BoxLayout` and fill its slot — diagnosed by reading
  `get_layout_manager` per container rather than guessing from the geometry.
- **A refused value must not be confused with a differently-spelled one.** The
  first version compared the parsed value against the coerced one as strings,
  which reported `.5`, `0.0` and `1.0` — spellings the bundled layouts
  actually use — as unhandled. `_number` now returns nothing for a refused
  value, so the caller can both default and report without that false
  positive. Check any new `Unhandled` bookkeeping against the spellings in
  `layouts/`, not just against a bad value.
- **A non-numeric `xalign` now renders centred, not `start`.** Centred is the
  legacy `@default_options` value, so this is a correction toward GTK3; the
  assertion fails against pristine with `got 'start' / expected 'center'`.
- **Two assertions were vacuous when first written** and pristine caught both.
  See TESTING.md; the short version is that the old renderer buckets `0.3` to
  `center` rather than `start`, and that a "70% across the slack" check passes
  when the child fills the slot because both sides are then 0.

### Verification for this increment

- `t/gtk4/30_Box.t` fails **11 of 107** against a pristine `git archive HEAD`
  with only the changed test files and `t/layouts/align.layout` overlaid, on
  real Wayland. The pristine renderer was confirmed to contain no
  `_SetConstraints` before the comparison was trusted.
- `t/04_Gtk4LayoutRenderer.t` fails **11 of 199** offline against the same.
- Controls pass on both trees: the five "keeps the plain box layout"
  assertions, the three slack sanity checks, `a fractional xalign with
  xscale=0 leaves the child at its natural size`, and `a fractional alignment
  the constraint path implements is not reported`.
- Each new assertion was checked individually from `prove -v`, and the
  pristine failure of the non-numeric case was confirmed to be
  `got 'start' / expected 'center'` — the right reason.
- No shared code changed. `make test-gtk3` was run anyway and passes.

## Standing policy: the GTK4-native mechanism first — now D029

The user set this as a standing policy at the end of the 2026-09-07 session.
It is recorded as **D029, Accepted**; read the entry, not just this summary.

> Basically I would rather simplify and implement things the GTK4 native way
> than trying to port the exact GTK3 thing.

and, on whether a not-yet-ported option should make the renderer refuse:

> we should try to find equivalent in this case in GTK4, if none exists, we
> must implement

The operative rule is **find the GTK4 equivalent; if none exists, build it.**
Nothing is deliberately dropped. Three things bound it, and each has bitten
already:

- **It does not override D002 or D013.** That was the point of the two
  clarifying rounds. Native is about the toolkit call underneath, not the
  layout language, and not licence to restyle.
- **"We must implement" cannot mean a custom widget.** A `Gtk4::Widget`
  subclass registers and instantiates, but its layout vfunc overrides are
  **silently ignored** (see below and D006). Native therefore means composing
  GTK4's existing layout managers.
- **Do not read it as "refuse every layout using an unported option."**
  `markup=` alone has 76 uses; that reading would take the renderer from
  rendering 8 widget types to refusing nearly every real layout. The
  `Unhandled` accessor stays the mechanism for a not-yet-ported option.

## New D006 evidence from this session's probes

All measured on the real Wayland connection (display
`Glib::Object::_Unregistered::GdkWaylandDisplay`, `wayland=1`), under
`LC_ALL=C` for the numeric tables. Full detail is in D006; the headlines:

- **`Glib::Type->register_object('Gtk4::Widget','My::Class')` works.** The
  class registers, instantiates, and passes `->isa('Gtk4::Widget')`.
- **Layout vfunc overrides are silently ignored — the decisive finding.**
  `MEASURE`, `SIZE_ALLOCATE`, `do_measure`, and `do_size_allocate` were all
  defined on one subclass and **none** was called during real layout;
  `measure('horizontal',-1)` read back `0,0,-1,-1` and the widget was
  allocated height 0 against an override claiming 40. No warning. So D025
  alternative 1 is **impossible**, not deferred.
  *Method warning:* a lowercase `measure` sub does get called, but only
  because it shadows the introspected method when Perl calls
  `$widget->measure(...)` itself. That is not GTK invoking a vfunc, and
  counting it overstates what the binding supports. Probe with the
  uppercase/`do_` names and judge by GTK's own layout pass.
- **`Gtk4::ConstraintLayout` reproduces `GtkAlignment` exactly.** Measured
  against `Gtk3::Alignment` on the same fixture and slot: 14 of 15
  fractional `xalign`/`xscale` combinations identical, one off by 1px from
  solver rounding. The table is in D025. This is what makes the `AB`
  fractional gap closable.
- **`Glib::Type->from_package` does not exist** on this binding — the call
  dies. An earlier note recorded it as *reporting classes absent*, which
  implied it worked and answered wrongly. Probe by constructing inside
  `eval`, never by type lookup.
- **`backend_probe` never sets an `ok` key** — check `->{error}`. Checking
  `->{ok}` reports failure against a good display.
- **`Gtk4::Constraint` strength must be numeric.** `'required'` warns
  `isn't numeric` and coerces to strength **0**, so the constraint constructs
  but does not bind. Required is `1001001000`.
- **A widget's own CSS padding falsifies a geometry probe.** A `Gtk4::Button`
  asked for `set_size_request(40,24)` measures 26px wide at a 7px inset; a
  `Gtk4::Label` measures exactly 40 at 0. A *uniform* offset across every row
  of a geometry table is the signature of this, not of a layout bug.

### Two corrections to claims inherited from last session

Both were recorded in good faith and neither reproduces as stated. The method
that produced each bad reading matters more than the correction:

- **"`Glib::Type->from_package` reports lazily-registered classes as absent,
  and probing by construction reverses the result."** The construction results
  are right, but the explanation is not: `from_package` is not a method on this
  binding at all, so it never reported anything. There is no evidence here for
  lazy registration. The bad reading came from assuming a died call had
  returned a falsy answer.
- **"`measure`/`do_measure` were among five vfunc names tried and none was
  called."** The conclusion holds, but `measure` *was* called in that probe —
  by the probe's own `$widget->measure(...)` call, which a lowercase sub
  shadows. Mixing a shadowing method name into the vfunc list makes the
  evidence read as stronger and broader than it is.

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

## This session's increment: normalising the label `ellipsize=1` shorthand

The only code change of the session, and it exists because accepting D028
alternative 2 reversed what the implementation did.

`Layout::Button` maps an `ellipsize=` of `'1'` to `'end'`
(`gmusicbrowser_layout.pm:3051`); `Layout::Label` passes the value straight to
`set_ellipsize` (`:3128`). Both were read in production code, not assumed. So
`ellipsize=1` on a GTK3 label does not ellipsize, and the renderer previously
reproduced that by filtering the value and reporting it through `Unhandled`.
It now normalises it, so both legacy classes understand the shorthand.

Three things worth carrying forward:

- **This is a parity exception, not a translation, and is recorded as one.**
  It changes rendering relative to GTK3. What makes it cheap is that no
  bundled layout can reach it: all **37** `ellipsize=` uses across `layouts/`
  name `end`, isolated with `[(,]ellipsize=` so that `lmarkup=`-style prefixes
  and `minsize=` cannot inflate the count. Only a hand-written layout reaches
  the `'1'` form.
- **Normalising a value removes it from the out-of-range case, so the fatal
  enum filter loses its coverage unless a new value replaces it.** `'1'` used
  to be the out-of-range fixture. The fixture now carries
  `Text5(ellipsize=sideways)` for that, which is what keeps the filter tested;
  without it the increment would have silently deleted a test of a fatal
  failure mode.
- **An option leaving the ignored list is part of the change.** `ellipsize=1`
  previously appeared in `Unhandled`; it must not any more. That assertion
  fails against pristine in the offline file and is what pins the bookkeeping.

### The measurement, and why the fixture reads the way it does

`Text`, `Text2`, and `Text3` all carry the **identical** text `"ellipsized"`.

| Label | `ellipsize=` | Minimum width now | Against pristine |
|---|---|---:|---:|
| `Text` | `end` | 12 | 12 |
| `Text2` | `none` | 64 | 64 |
| `Text3` | `1` | 12 | **64** |

The 64 is the full text width. Had `Text3` carried a different string it would
have measured the string and passed against the un-normalised renderer, which
is exactly the trap the previous session recorded for the original ellipsize
assertions. The identical text is what makes the comparison turn on the option.

### Verification for this increment

- `t/gtk4/30_Box.t` fails **3 of 81** against a pristine `git archive HEAD`
  with only the changed test files and the fixture overlaid, on real Wayland.
  The renderer in that copy was confirmed to contain no `_Ellipsize`.
- `t/04_Gtk4LayoutRenderer.t` fails **2 of 179** offline against the same.
- Controls pass on both trees: both `ellipsize=sideways` assertions, and
  `ellipsize=end lowers the minimum width below the un-ellipsized one`. The
  comparison discriminates rather than merely failing everything.
- Each new assertion was checked individually from `prove -v`, not inferred
  from the file's failure count, and the pristine failure of the minimum-width
  assertion was confirmed to be `got 64 / expected 12` — the right reason.
- No shared code changed. `make test-gtk3` was run anyway and passes.

## Actual state of the port

The GTK4 work is an early spike, not a partly-finished migration. Do not assume
otherwise from the size of the planning documents.

- `gtk4-alpha` is a couple of dozen commits past `master`; the list is in the
  next section. **Do not record the exact number here.** Earlier handoffs said
  "ten" at `0074c06` where the real count was 11, and any figure written down
  goes stale the moment the next documentation commit lands — including the
  commit that records it. Read it from `git rev-list --count master..HEAD`.
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

Everything is committed. For the number of commits past `master`, run
`git rev-list --count master..HEAD` rather than trusting a figure here.
Newest first:

	0b33714 gtk4: apply the legacy HSize and VSize size groups
	cd219e7 docs: correct the claim that gmusicbrowser.pl is unmodified
	0af4767 docs: record D033 and correct the markup usage count
	23ea469 gtk4: apply a static markup= on a label
	2027830 docs: record D032 and the layout option inheritance results
	1bf528a gtk4: inherit the layout-wide DefaultFont and DefaultFontColor
	fddcf65 docs: record D031 and the label font/color CSS results
	c97247b gtk4: apply the legacy label font and color options through CSS
	6e33759 docs: record D030 and the AB constraint layout results
	fe65c9c gtk4: render a fractional AB alignment through a constraint layout
	9a12acc docs: record the native-mechanism policy and the layout vfunc finding
	adde70b gtk4: normalise the label ellipsize=1 shorthand to end
	f6d2927 docs: stop recording a commit count that goes stale on write
	f74d4e1 docs: record the landed commits in the handoff
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

None of this session's three increments touched shared code. All three changed
`gmusicbrowser_gtk4_layout.pm`, `t/04_Gtk4LayoutRenderer.t`, and
`t/gtk4/30_Box.t`, and each added one fixture — `t/layouts/inherit.layout`,
`t/layouts/markup.layout`, `t/layouts/sizegroups.layout`. The session also
added `docs/modernization/PROGRESS.md`. Documentation is committed separately
from code, as before.

The `font=`/`color=` CSS increment before it changed
`gmusicbrowser_gtk4_layout.pm`, `t/04_Gtk4LayoutRenderer.t`,
`t/gtk4/30_Box.t`, and `t/layouts/labels.layout`, and also touched no shared
code.

Of the previous session's two, neither touched shared code. The
`size=`/`relief=` one changed
`gmusicbrowser_gtk4_layout.pm`, `t/04_Gtk4LayoutRenderer.t`,
`t/gtk4/40_Icons.t`, `t/layouts/buttons.layout`, and `t/layouts/icons.layout`;
the label one changed `gmusicbrowser_gtk4_layout.pm`,
`t/04_Gtk4LayoutRenderer.t`, `t/gtk4/30_Box.t`, and added
`t/layouts/labels.layout`. Documentation is committed separately from code in
both cases.

No GTK3 production code, bundled layout, or file in `pix/` has been touched by
any increment on this branch.

**`gmusicbrowser.pl` is not unmodified at branch scope, and an earlier revision
of this file said it was.** `git diff master HEAD -- gmusicbrowser.pl` reports
109 insertions and 49 deletions, all from `ec217bc initial gtk4 stubs`, the
branch's first commit — it wired in the frontend boundary
(`gmusicbrowser_frontend.pm`, `gmusicbrowser_frontend_legacy.pm`, the
`$Frontend`/`$FrontendLegacy` globals and the frontend state hash). What is
true, and is what the claim was reaching for, is that **no layout increment has
touched it**: check with `git diff --name-only <increment-base> HEAD` rather
than trusting a blanket statement. Its `perl -c` failure is a missing
`Net::DBus`, not that change, and reproduces on a pristine archive of HEAD.

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

`markup` (76 uses) and `minsize`/`expand_max` are deliberately out of scope
there; see D028 alternative 3. `font` and `color` were listed with them at the
time and have since been implemented under **D031**.

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
applied. See D028, now Accepted. A label's `ellipsize=1` is normalised to
`'end'` under its alternative 2, which is the one accepted parity exception in
the renderer: GTK3 leaves such a label un-ellipsized.

`%LabelHandled` covers `text`, `markup`, `xalign`, `yalign`, `ellipsize`,
`minwidth`, `minheight`, `font`, and `color`; `minsize` and `expand_max` stay
reported, and so does a `markup=` that names a song field or cannot be parsed.
`font=`/`color=` land through a `GtkCssProvider` under D031, with `font=`
expressed as a ratio of the desktop font rather than as absolute points.

Under D032 a label with neither option inherits the layout's
`DefaultFont`/`DefaultFontColor` through the same provider, per option and with
the widget's own value winning; an untranslatable global is reported through
`UnhandledGlobals` rather than through the per-widget list. Under D034 the
`HSize`/`VSize` size groups are applied after the tree is built, with an
unresolvable name reported through `UnhandledSizeGroups`.

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

`make test-modernization`: **473** executed assertions passed, no skips.
Running totals: 269 three sessions ago, 298 after `Next`/`Prev`, 315 after
`Filler`, 317 after the labels fixture, 325 after `size=`/`relief=`, 342 after
label alignment, 344 after the `ellipsize=1` normalisation, 364 after the `AB`
constraint layout, 395 after the label `font=`/`color=` CSS, 415 after the
`DefaultFont`/`DefaultFontColor` inheritance, 458 after the static `markup=`,
473 after the size groups. The skip count was read from `prove -v`, not
assumed.

`make test-gtk4` on the real Wayland connection: **346** TAP results,
comprising **340 executed assertions passed** and the same six pre-existing M1
feasibility probes skipped, 0 failures. Per file: 18 binding (which is where
all six skips live), 4 proof-of-life, 84 pane, 166 box, 74 icon — measured per
file, not by subtraction. Running totals
for the same command: 173 before `Next`/`Prev`, 184 after it, 202 after
`Filler`, 216 after the `AB` coverage, 246 after `size=`/`relief=`, 258 after
label alignment, 261 after the `ellipsize=1` normalisation, 287 after the `AB`
constraint layout, 304 after the label `font=`/`color=` CSS, 323 after the
inheritance, 337 after the static `markup=`, 346 now. Do not restate this as
340 passing assertions.

Two GTK `Failed to set text ... from markup` warnings are expected in this run,
one per refused value in `t/layouts/markup.layout`. They are GTK warnings, not
Perl ones, and cannot be suppressed from Perl. Do not hide them.

The six skips were counted by copying the runner to
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

`t/01_ModFileMetadata.t` **passes on this checkout**, with 10 real assertions
and no skips — corrected this session, having been recorded as failing for
several sessions. The repository still ships no samples (`t/samples/` is in
`.gitignore` and `git ls-files t/samples/` is empty), but this working copy has
them downloaded. Both facts are true and they are about different things: the
repository state and this checkout's state. It would still fail on a fresh
clone, which is why it stays outside the offline target. Check
`git ls-files t/samples/` before reporting it either way.

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

**Updated after the list-model probe.** The strongest candidates now are, in
rough order of value:

- **The command-registration increment** (D039 plus the other 13 unregistered
  commands). It is the actual gate on menus, it is shared code needing a GTK3
  pass, and doing it once is far better than five commands at a time. After it,
  `MB`/`SM`/`BM` plus `MenuItem` turns D038's interpreter into visible menus for
  most of the 99 instances instead of 14.
- **The song-field state path**, still blocked on the frozen
  `FRONTEND_CONTRACT.md` and a fixture song source — see 0b below, which is
  unchanged and still the largest converging gate.
- ~~The custom-drawing probe~~ — **done**, `t/gtk4/80_Drawing.t`. What it
  leaves behind is a *decision*, not a probe: **D010 is ready to settle**, with
  option 2 ruled out by the binding and option 1 measured. The one thing worth
  measuring first is the texture route at list scale — a viewport of textures
  rebinding during a scroll, rather than the single swap the probe did.
- **The show/hide subsystem**, which unlocks `ToggleButton` (35) and the 28
  `togglewidget` `MenuItem`s, and needs no frozen-contract change.

`TB` remains a small, low-risk container increment if a short one is wanted.

0. ~~Layout-level option inheritance.~~ **Done** as D032. `DefaultFont` and
   `DefaultFontColor` are inherited; `PATH`, `SkinPath`, and `SkinFile` are
   read into the same legacy hash and are deliberately **not** ported, because
   they belong to the skin machinery, which has no GTK4 work yet. That is the
   remaining half of `{global_options}` and needs a skin design first.

0b. **The song-field state path is now the single gate on everything left in
   `Layout::Label`,** and it should probably be the next increment because so
   much converges on it. What it unlocks:
   - the **54** field-bearing `markup=` uses, the remainder of D033;
   - the whole rest of the family — `Pos`, `Title`, `Title_by`, `Artist`,
     `Album`, `Year`, `Comment`, `Length`, `PlayingTime`, `Volume`, `Visuals`,
     `LabelToggleButtons`, with `Label` an alias for `Text`. **Every one of
     them carries a `markup` in its own widget-table defaults**
     (`gmusicbrowser_layout.pm:246-333`) — `Title` is
     `'<b><big>%S</big></b>%V'`, `Artist` is `'<b>%a</b>'`. The markup *is* the
     widget, so none can be implemented without this path. An earlier version
     of this file recommended the family as a smaller step than `markup=`;
     that was wrong, and reading the widget table is what shows it.
   - once those land, D031's `font=` becomes reachable from a shipped layout
     for the first time (all four bundled uses are on
     `Title`/`Artist`/`Album`/`Date`) and five of D032's six bundled global
     uses become reachable too.

   Scope it as the state path, not as a widget: `::UsedFields`,
   `Songs::Depends`, `::WatchSelID`, `::ReplaceFieldsAndEsc`, and
   `markup_empty` for the no-song case (`:3178-3183`). `%::ReplaceFields` is
   built from the shared song field definitions at
   `gmusicbrowser_songs.pm:1935`, so this crosses the frontend boundary and
   needs a GTK3 pass.

1. ~~Decide the six Proposed entries.~~ **Done.** D023, D024, D025, D026,
   D027, and D028 are all Accepted. The recorded resolutions, so a later
   session does not reopen them:
   - **D027** — `set_has_frame`, not `add_css_class('flat')`. Alternative 3
     rejected; the style class would entangle button relief with the
     undecided `font=`/`color=` CSS work.
   - **D028** — normalise `ellipsize=1` to `'end'` on labels. Alternative 2
     accepted, reversing the entry's original recommendation.
   - **D023/D024** — accepted together. The `gmb-*` to freedesktop mapping
     stays deferred under D023 alternative 2 and was explicitly left deferred.
   - **D025/D026** — accepted as documented approximations. Their gaps are
     *not* waived, so the `AB` and `WB` rows stay where they are.

   The four entries still marked Proposed in `DECISIONS.md` — D009, D011,
   D012, D019 — are pre-existing and unrelated to the layout rows. Do not
   mistake them for this backlog.
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
4. ~~`AB`'s fractional gap.~~ **Closed** by D030: a fractional alignment or
   scale goes through a `Gtk4::ConstraintLayout` reproducing `GtkAlignment`
   exactly, and the integral path every bundled layout uses is unchanged. The
   `AB` row still does not advance, but only for the input/focus/
   accessibility/saved-profile reasons that hold every row.
   `WB` is untouched and D026 alternative 2 — folding `hover_layout` into
   `WB` — is still undecided and still needs a popup-window design.
5. D006 binding evidence. **Already recorded, keep extending it.** D006 now
   holds the graphene marshalling failure, the `->can` segfault, the
   widget-before-`Gtk4::init` segfault, the empty-string boolean artifact, the
   `set_theme_name` display-singleton refusal, the
   `get_size_request`/`set_size_request`/`measure` findings, and this session's
   fatal-enum, `Button`-image-child, and `set_has_frame` findings.
6. ~~Decide D023 and D024.~~ **Done**, both Accepted, so icon-bearing
   widgets are no longer gated. Still open underneath them: whether to propose
   mapping the 28 bundled `gmb-*` names to freedesktop names. That stays
   deferred by D023 alternative 2 and needs its own entry, because those files
   back gmusicbrowser's own "Icon theme :" preference at
   `gmusicbrowser.pl:7023` with three packs in `pix/`. Several `gmb-view-*`
   names also have no reliably available standard equivalent.
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

- **An option or instance count from `grep` over `layouts/` is not a count of
  anything the renderer sees.** Seven recorded figures were corrected this
  session (D033, D034), each for the same reason: grep cannot distinguish a
  `[layout]` block from a `{Group}`/`{Column}` skin block, a live line from a
  comment, a widget's `icon=` from the layout's `Icon=` metadata or a
  `tabicon=`, or a widget instance from an `HSize`/`VSize` declaration that
  merely names one. **Walk the parser's catalog instead**, and state the basis:
  widgets *declared in a layout's own block* versus *instances across all
  layouts*, which differ because six bundled layouts use `based on`
  (`Next` is 34 own, 36 all).
- **A count discrepancy can be an unimplemented feature.** The size-group
  increment was found by asking why the recorded instance counts disagreed
  with the parser's; the answer was that a grep matched a construct the
  renderer did not implement. Reconcile a disagreement rather than picking the
  figure that looks right.
- **Do not infer a precedence from a merge order.** `NewWidget:1162` merges
  `%$global_opt` *last*, which reads as though a layout-wide global outranks a
  widget option. Neither of the two globals lets it: both fall back with `||`
  (`:1163` and `:3120`), so the widget wins. Read what the consumer does with
  the merged hash, not just how the hash was built.
- **`{metadata}` is now load-bearing for the renderer.** It was previously
  unread — only `{nodes}` and `{roots}` were — so a layout property was
  invisible to it. `Type` is still metadata the renderer ignores, which is what
  lets a `Type=G` fixture carry keys only `Type=D`/`Type=F` layouts really use.
- **An inherited value needs a reporting channel of its own.** The per-widget
  `Unhandled` list means "options this layout wrote on this widget", and it is
  built from `{options}{order}`. Putting an inherited name in it would misreport
  the layout. `UnhandledGlobals` is the separate accessor.
- **A baseline for an inherited option cannot come from the same layout.**
  Every label under a global inherits it, so a within-layout baseline measures
  the global against itself. Take the unstyled baseline from a separate layout
  carrying no globals.
- **Checking which widgets carry an option is not checking which inherit it.**
  The previous handoff established that `[D_clementine]`'s labels carry
  `color=grey` and concluded the inheritance was barely reachable. `Text5` in
  the same block carries none, which makes it exactly the inheriting case and
  the increment a fix to a shipped layout. Grep for the absence, not the
  presence.
- **When an increment adds a fallback, most of its override assertions are
  controls.** The per-widget path already worked, so every "the widget wins"
  assertion passes on both trees. Only the inheriting cases discriminate.
  Reading the file's failure count would have made the proof look twice as
  strong as it is.
- **The OS theme font and colours already reach the renderer with no code.**
  An unstyled `Gtk4::Label` measures 19x17 under this host's `Roboto 10`, and
  GTK3 reports the same. Any `font=`/`color=` the renderer applies is an
  *override* of the desktop theme, so reach for it only where a layout asks.
- **A ratio only follows the theme if it is fixed against a constant
  baseline.** Deriving a percentage from the live theme size cancels out
  (`20/16 * 16pt` is `20pt`), reproducing the absolute size while the emitted
  rule looks relative. Verify a relative translation by varying the theme and
  reading the **rendered size**, not the emitted class.
- **Pango is unreachable through the GTK4 binding.**
  `Pango::FontDescription::from_string` is undefined, so a legacy font string
  must be parsed in Perl. Pango is still available alongside Gtk3 for a
  reference probe.
- **`load_from_data` needs the byte length**, and a CSS rule body needs a
  **trailing semicolon** or GTK warns `Expected ';' at end of block` while
  still applying the rule — the warning is the only symptom.
- **`dim-label` has no observable.** It styles by opacity at draw time, so
  `get_color` and `get_opacity` both read unchanged; `has_css_class` is the
  only check. An explicit CSS colour *is* readable through
  `get_style_context->get_color`.
- **A `font-size` assertion only discriminates away from the theme size.** At
  `Roboto 10` a `10pt` rule measures identically to no rule.
- **`gtk-application-prefer-dark-theme` has no effect in GTK4** — it is a GTK3
  setting. The dark variant is a theme *name* (`Breeze-Dark`). This host is
  genuinely in a dark context, with theme text at `rgb(249,250,251)`.
- **Do not double `Gtk4::Gdk::Display` in `t/04_Gtk4LayoutRenderer.t`.** The
  absence of a display is what makes `_IconTheme` return undef and every icon
  fall back to text; adding one to enable CSS offline silently deletes that
  coverage.
- **A style provider is installed on the display, so it outlives the widget
  tree.** `Destroy` must call `remove_provider_for_display`, which exists and
  works.
- **Isolating an option with `[(,]option=` misses a space after the comma.**
  `[(,]markup=` reports 74 where the whitespace-tolerant grep reports **76**:
  two uses in `songtree.layout` are written `, markup=`. Allow optional
  whitespace.
- **But that 76 is not 76 label options** — a grep count over `layouts/` mixes
  three populations, and D033 corrects it. It is **56** real `markup=` options
  in layout blocks, **19** SongTree drawing-layer uses inside
  `{Group ...}`/`{Column ...}` skin blocks, and **1** commented-out line. Only
  **2** of the 56 are static. So before an option count drives a decision,
  split it by block type and drop comment lines: `grep` sees a `{Group}` skin
  block and a `[layout]` block identically, and the parser's own catalog is the
  reliable way to count. The already-recorded `shimmer.layout:132`
  `color='#ccc'` drawing-layer trap is the same mistake caught once before.
- **`markup=` was two options all along.** Legacy `Layout::Label` branches at
  `gmusicbrowser_layout.pm:3156` on whether `::UsedFields` finds song fields:
  a field-free value is set once, a field-bearing one subscribes through
  `WatchSelID`. Look for a legacy class making such a split before scoping an
  option as one unit — half of this one needed no state at all.
- **Probe a retained-state behaviour from a non-default starting state.** The
  first `set_markup` probe concluded "on failure `get_text` returns empty".
  That was an artifact of building the probe labels with
  `Gtk4::Label->new('')`: the *retained previous text* was empty. Over a
  non-empty label the failure leaves the previous text intact. Implementing the
  first reading would have reported a valid `<b></b>` as refused.
- **A widget's own CSS padding falsifies a geometry probe.** A `Gtk4::Button`
  asked for `set_size_request(40,24)` measures 26px wide at a 7px inset,
  because the theme's button style insets the allocation; a `Gtk4::Label`
  measures exactly 40 at 0. A *uniform* offset across every row of a geometry
  table is the signature of this, not of a layout bug. Use a CSS-neutral child
  when measuring a container's placement.
- **`Gtk4::Constraint` strength must be the numeric enum.** `'required'` warns
  `isn't numeric` and coerces to strength **0**, so the constraint constructs
  and does not bind. Required is `1001001000`.
- **`Gtk4::ConstraintLayout` needs its constraints added before the window is
  presented.** Added afterwards on an already-mapped window they had no effect
  in a probe, leaving the child at its natural size. The renderer adds them
  during construction, which is why it works.
- **Read `get_layout_manager` when a constraint-driven container misbehaves.**
  A container that still carries a `Gtk4::BoxLayout` never reached the
  constraint path at all, which is a different bug from constraints that are
  present but wrong, and the geometry alone does not distinguish them.
- **A scale of `.5` has no GTK4 enum even though an alignment of `.5` does.**
  `center` expresses a half alignment; nothing expresses "half fill". A
  fractional-value check written for alignments will silently pass a
  fractional scale through to the bucketing path.
- **Check new `Unhandled` bookkeeping against the spellings the bundled
  layouts really use.** Comparing a parsed value against its coerced form as
  strings reported `.5`, `0.0` and `1.0` as unhandled — all three appear in
  `layouts/`. Have the coercion helper return nothing for a refused value
  instead, so defaulting and reporting stay separable.
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
- **Normalising a previously-rejected option value silently removes the
  coverage of the reject path.** `ellipsize=1` was the out-of-range fixture
  before D028 alternative 2 made it valid; the fatal-enum filter would have
  been left untested had `Text5(ellipsize=sideways)` not replaced it. When an
  increment makes a bad value good, check what that value was previously
  proving and replace it.
- **An option that becomes handled must leave the `Unhandled` list, and that
  is a test in its own right.** It is the half of a "now implemented" change
  that is easiest to forget, and it fails against pristine, so it discriminates.
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
