# Modernization tests

Status: Wave 2 infrastructure

The GTK-free modernization tests are deterministic and offline:

```sh
make test-modernization
```

This runs the neutral layout parser, frontend contract and lifecycle, legacy
adapter and lifecycle integration, and GTK4 renderer contract tests. On
2026-09-07 it reported 458 executed assertions passed and no skips. Running
totals: 269 two sessions ago, 298 after `Next`/`Prev`, 315
after `Filler`, 317 after the shared labels fixture, 325 after the
`size=`/`relief=` increment, 342 after label alignment/ellipsize, 344 after the
`ellipsize=1` normalisation, 364 after the `AB` constraint layout, 395 after
the label `font=`/`color=` CSS, 415 after the `DefaultFont`/`DefaultFontColor`
inheritance, 458 after the static `markup=`. The skip count was read from
`prove -v`, not assumed. The
renderer test uses small in-process GTK doubles; it proves the
parser/renderer/command wiring without claiming that a real GTK4 binding or
display passed.

The real GTK4 smoke suite must run on an existing Wayland connection:

```sh
make test-gtk4
```

The runner creates temporary XDG config, data, cache, state, and runtime
directories, exposes only the current Wayland socket, forces
`GDK_BACKEND=wayland`, and applies a timeout. A missing Wayland connection,
Perl module, or typelib exits with status 77 and an explicit reason. Skips do
not satisfy the proof-of-life gate.

The current Ubuntu development host needs:

```sh
sudo apt install gir1.2-gtk-4.0 libglib-perl \
  libglib-object-introspection-perl libgtk3-perl
```

`libgtk3-perl` is not used by the GTK4 entry point. It is required to run the
unchanged GTK3 path with the same isolated fixture once the shared-code checks
begin.

On 2026-09-07 the system packages loaded GTK 4.14.5. The initial
`make test-gtk4` run failed to open the display inside the execution sandbox;
the same command outside it passed on the real Wayland connection. The two
original test files reported 22 TAP results: 16 executed assertions passed and
six feasibility probes were explicitly skipped. This replaces the temporary
archive setup recorded on 2026-09-06, whose reported total also included those
six skips. A pinned, reproducible package and the remaining M1 probes are still
required.

The run emits `Too late to run INIT block` from the introspection module and
`Unable to acquire session bus` because the runner unsets the session bus.
Neither warning should be hidden or interpreted as a clean desktop acceptance
result.

`t/gtk4/20_Paned.t` adds real pane allocation and renderer-level saved-size
checks to the runner, contributing 84 executed assertions to the 2026-09-07
`make test-gtk4` totals recorded below. Pane coverage includes
both orientations, saved-size reconstruction, all four resize policies during
real window resizing, and notification updates before saving. It exercises
programmatic movement and the `move-handle` action signal; these are not
physical pointer or keyboard input tests. The
pane's legacy `SaveOptions` callback returns `size`; the proof application does
not yet write that value to an application profile.

The replacement uses GTK4's [position property](https://docs.gtk.org/gtk4/property.Paned.position.html)
and [max-position property](https://docs.gtk.org/gtk4/property.Paned.max-position.html).
The action test uses [cycle-handle-focus](https://docs.gtk.org/gtk4/signal.Paned.cycle-handle-focus.html)
before [move-handle](https://docs.gtk.org/gtk4/signal.Paned.move-handle.html).

`t/gtk4/30_Box.t` adds real `HB`/`VB` packing geometry to the runner, plus the
`AB`, label alignment, and label styling coverage. On 2026-09-07, after the
static `markup=`, the full
`make test-gtk4` run reported 337 TAP results: 331 executed assertions passed
and the same six feasibility probes were skipped, 0 failures. The skips were
counted from `prove -v` and are the same six M1 probes as before. Running
totals for the same command: 173 results before `Next`/`Prev`, 184 after it,
202 after `Filler`, 216 after the `AB` alignment coverage, 246 after
`size=`/`relief=`, 258 after label alignment, 261 after the `ellipsize=1`
normalisation, 287 after the `AB` constraint layout, 304 after the label
`font=`/`color=` CSS, 323 after the inheritance, 337 after the static
`markup=`. Per file: 18 binding, which is
where all six skips live, 4 proof-of-life, 84 pane, 157 box, 74 icon.

**Two GTK `Failed to set text ... from markup` warnings are expected** in this
run, one per refused value in `t/layouts/markup.layout`. They are GTK warnings
rather than Perl ones — `$SIG{__WARN__}` does not see them — and cannot be
suppressed from Perl, because validating a markup means attempting it. Do not
hide them or read them as failures.

The `AB` constraint-layout assertions are behaviour, not construction. Against
the previous renderer, `t/gtk4/30_Box.t` fails **11 of 107** on real Wayland
and `t/04_Gtk4LayoutRenderer.t` fails **11 of 199** offline, verified by
extracting `git archive HEAD` to a scratch directory, overlaying only the
changed test files and `t/layouts/align.layout`, and confirming the pristine
renderer contains no `_SetConstraints` before trusting the comparison.

Two of those assertions were vacuous as first written, and pristine is what
caught both. Recorded because the traps generalise:

- **"not collapsed to the near edge" passes against the old renderer.** Its
  `_align` threshold is `<=.25` for `start`, so `xalign=0.3` buckets to
  `center`, not `start`, and lands well away from the edge. The
  discriminating fact is that it is not *centred* either.
- **"places the child 70% across the remaining slack" passes when the child
  fills the slot,** because the target offset is then `0.7*(slot-slot)` = 0
  and the measured offset is also 0. It only turns on the option once paired
  with an assertion that the slack exists.

The `Gtk3::Alignment` reference numbers this increment was measured against
were read with a `Gtk4::Label`/`Gtk3::Label` child, not a `Gtk4::Button`: a
button given `set_size_request(40,24)` measures 26px wide at a 7px inset from
its own theme CSS, which offsets every row of a geometry table uniformly and
looks like a layout bug. See D006.

The label `font=`/`color=` assertions (D031) are behaviour for the font and the
explicit-colour paths, and construction for the grey path. Against the previous
renderer, `t/gtk4/30_Box.t` fails **8 of 124** on real Wayland and
`t/04_Gtk4LayoutRenderer.t` fails **14 of 230** offline. The pristine failure
values were confirmed to be the right reason: `21 > 21` for the font
measurement, because the previous renderer draws every label at the theme size,
and `got rgb(46,52,54) / expected rgb(255,255,255)` for the explicit colour.

Three things to know before extending them:

- **The offline comparison needs stubs in the pristine copy.** `_IsGrey`,
  `_ColorRule`, `_FontRule`, and the `LEGACY_FONT_BASELINE` constant must be
  added, or the helper block dies before its assertions are reached and hides
  them. This is the same "add just enough to reach the assertions" step the
  `Filler` increment needed.
- **`t/04_Gtk4LayoutRenderer.t` deliberately does not double
  `Gtk4::Gdk::Display`.** The absence of a display is what makes `_IconTheme`
  return undef and every icon fall back to text, so supplying one to make the
  CSS provider work offline would quietly delete that coverage. It also means a
  generated `font=`/`color=` rule cannot be installed offline and is reported
  through `Unhandled` there, with the rendering proved on real Wayland instead.
  `dim-label` is the exception: it ships with GTK4, so it applies with no
  provider and is the one styling path the offline file can assert.
- **The theme colour differs between environments.** It is near-white on this
  desktop and `rgb(46,52,54)` inside `tools/run-gtk4-smoke`, whose Adwaita
  theme and unset session bus are already recorded. Compare against the
  measured theme colour rather than hard-coding a value.

The `DefaultFont`/`DefaultFontColor` inheritance assertions (D032) are
behaviour on real Wayland and a mix of behaviour and bookkeeping offline.
Against the previous renderer, `t/gtk4/30_Box.t` fails **6 of 143** on real
Wayland and `t/04_Gtk4LayoutRenderer.t` fails **7 of 250** offline. The
pristine failure values were confirmed to be the right reason: `21 > 21` for
the inherited font, because the previous renderer draws every label at the
theme size, and `got rgb(46,52,54) / expected rgb(255,255,255)` for the
inherited colour.

Four things to know before extending them:

- **The offline comparison needs only the `UnhandledGlobals` accessor stubbed**
  into the pristine copy, and `_Globals` must be confirmed absent there before
  the comparison is trusted. Fewer stubs than D031 needed, because the
  inheritance sits on top of helpers that already exist.
- **The unstyled baseline comes from a separate layout carrying no globals,**
  not from another label in the same one. Every label in a layout with a
  global inherits it, so a within-layout baseline would measure the global
  against itself. The fixture therefore holds four layouts: one with both
  globals, one with a grey global (the only inheritance path the offline
  doubles can assert, since `dim-label` needs no provider), one whose globals
  are both untranslatable, and one with none.
- **A "widget overrides the global" assertion is vacuous unless the two labels
  are compared against each other.** Asserting only that the overriding label
  lacks `dim-label` passes against a renderer that never applies `dim-label`
  to anything. This is the same class of trap as D030's two.
- **Most of the override assertions are controls, not proofs.** The
  per-widget `font=`/`color=` path already existed, so every assertion about
  an overriding widget passes on both trees. What discriminates is the four
  inheriting-label assertions on Wayland and the metadata read, precedence,
  and reporting assertions offline. Judge each new assertion from `prove -v`
  individually; the file-level count hides which is which.

The measured values, from a probe inside the runner, with `Text` under
`DefaultFont=20, DefaultFontColor=white`:

| label | own options | height | colour | classes |
|---|---|---:|---|---|
| baseline `Text`, no globals | — | 21 | theme | none |
| `Text` | — | 41 | `rgb(255,255,255)` | `gmb-font-200`, `gmb-color-white` |
| `Text2` | `font=8` | 17 | `rgb(255,255,255)` | `gmb-color-white`, `gmb-font-80` |
| `Text3` | `color=grey` | 41 | theme | `dim-label`, `gmb-font-200` |
| `Text4` | `font=oops,color=notacolour!` | 21 | theme | none |

`Text2` and `Text3` are what pin the per-option independence: overriding one
global leaves the other applied. `Text4` is what pins that a widget's own
refused value does not fall through to the global, matching legacy `||`.

The static `markup=` assertions (D033) are rendering behaviour on Wayland and a
mix of rendering and bookkeeping offline. Against the previous renderer,
`t/gtk4/30_Box.t` fails **6 of 157** on real Wayland and
`t/04_Gtk4LayoutRenderer.t` fails **10 of 293** offline. The pristine failure
values were confirmed to be the right reason: every markup label is empty, and
the precedence assertion fails `got 'ignored' / expected 'big'`, which is the
`text=` the old renderer shows.

Five things to know before extending them:

- **Every "is reported" assertion is a control**, because the previous renderer
  reports `markup` for *all* values, being wholly unimplemented. What
  discriminates is the rendering: `get_text` against `get_label`, the
  `xx-large` measurement, and the precedence over `text=`.
- **`get_text` and `get_label` are different observables and both are needed.**
  `get_label` returns the raw markup string, `get_text` the parsed text. A
  label showing its markup literally and one parsing it correctly have the same
  `get_label`, so only `get_text` distinguishes them.
- **A markup measurement needs a size in the markup and identical content.**
  The `xx-large` span measures 36px against 21px plain in the runner. A markup
  naming only `<b>` would not discriminate reliably.
- **The offline `Gtk4::Label` double's markup stripper was validated against
  the real binding on all 11 probe cases** — the three malformed classes
  (unclosed tag, unknown tag, unknown entity) and the two validly-empty ones
  (`''`, `<b></b>`) included — rather than written to satisfy the test. If it
  is extended, re-validate it the same way; a double that accepts what Pango
  refuses makes the reporting assertions pass for the wrong reason. The double
  also had to be corrected to report `''` rather than `undef` from `get_text`
  on a fresh `Label->new('')`, which is what the real binding does.
- **Two GTK warnings are emitted by these tests** and are expected; see above.

Eight offline assertions check that the validation sentinel never survives on
any label — on the applied, refused, and field-bearing paths. They are controls
on both trees, but they guard the one way this mechanism could leave a visible
artifact, which a rendering assertion would not catch.

A `font-size` assertion also only discriminates away from the theme size: with
the desktop at `Roboto 10`, a `10pt` rule measures identically to no rule at
all. 8, 9, 11, 12, 14, 16, 20, and 30pt all measure distinctly.
They read allocated child offsets with
[translate_coordinates](https://docs.gtk.org/gtk4/method.Widget.translate_coordinates.html);
`compute_bounds` and `compute_point` are unusable through this binding, which
reports `GType GrapheneRect ... is not registered with gperl`. That is a
concrete binding gap for D006, not a GTK limitation.

The box assertions are geometry, not construction: run against the previous
`_CreateBox`, which set fill on the cross axis and used `prepend` for `-`, the
same file fails 10 assertions and `t/04_Gtk4LayoutRenderer.t` fails 10 more.

The GTK3 reference for those assertions comes from the unchanged production
`BoxPack` in `gmusicbrowser_layout.pm`, extracted and called directly, driven by
the same `t/layouts/packing.layout` fixture and the same parser, at 600px width
with a 50x24 request per child and `direction=ltr`. GTK3 and GTK4 produced
identical offsets and widths in all three rows:

| Row | Offsets and widths |
|---|---|
| `HBmixed` | `Label` 0/50, `Text` 51/382, `Label4` 440/52, `Label3` 499/50, `Label2` 550/50 |
| `HBinterleaved` | `Label6` 0/50, `Text2` 51/396, `Label8` 448/50, `Label7` 499/50, `Label5` 550/50 |
| `HBfill` | `Label9` 0/265, `Label10` 364/86, `Label11` 550/50 |

Verified legacy behaviour behind the translation:

- Successive `-` children move inwards from the far edge, so the first `-`
  child stays nearest that edge. `prepend` reversed this and placed them at the
  near edge.
- `fill` acts on the packing axis, not the cross axis. With `_` and no `.` the
  child fills its extra space; with `_.` it keeps its natural size centred in
  that space; `.` alone receives no extra space at all. The cross axis fills
  in every case.
- Padding digits pad both packing-axis sides only.
- A `-` child only reaches the far edge when some child expands. With no
  expander GTK3 distributes the slack evenly among all children, so far-edge
  hugging is not an unconditional property.

Recording two probe artifacts that cost time: passing `expand`/`fill` to
`pack_start`/`pack_end` as an empty string instead of `0` produced wrong
allocations through this introspection binding, and `set_default_size` has no
effect on an already-mapped Wayland window. `t/gtk4/20_Paned.t` used
`set_default_size` for its resize step and four assertions failed reproducibly
on that account, before and independently of the box change; it now uses
`set_size_request`, and all 84 pane assertions pass.

`t/gtk4/40_Icons.t` covers GTK4 icon resolution with 74 executed assertions on
real Wayland. It uses `t/layouts/icons.layout`, which exercises a legacy `gtk-*`
name, the `stock=` option, a bundled `gmb-*` file, a bundled alias with no file
of its own, an unresolvable name, and a widget with no icon option. It then
pins a standalone icon theme to Adwaita to check the `-symbolic` fallback added
for D024, and finally asserts the D027 `size=`/`relief=` translation against
the live theme.

Measured against GTK 4.14.5, which is why the resolution chain exists rather
than a direct pass-through:

- 14 of the 15 legacy `gtk-*` names used by bundled layouts resolve to nothing
  in GTK4; only `gtk-fullscreen` is still found. GTK4 removed the stock-item
  system, so these need explicit mapping.
- Bundled `gmb-*` names resolve straight from the flat `pix/` directory once it
  is on the search path; no themed `index.theme` hierarchy and no file moves.
  None of the 28 bundled names exists in any host theme checked, so they cannot
  be shadowed by one.
- `gmb-queue0`, `gmb-queue-window`, `gmb-random-album`, and
  `gmb-view-fullscreen` ship no file of their own and need the same fallback
  indirection GTK3 applies through `%IconsFallbacks`.
- A mapped name that the active theme lacks still renders: `lookup_icon`
  returns a paintable because GTK substitutes its missing-image icon, confirmed
  with a mapped button that allocated 188x70 and displayed. So the resolver
  keeps a mapped name even when `has_icon` is false, and only an unmapped
  unknown name falls back to text.

Which icon theme is actually active during a run, corrected on 2026-09-07:

- Inside `tools/run-gtk4-smoke` the theme is **Adwaita**. The runner unsets the
  session bus, so GTK cannot read the desktop's icon-theme preference and uses
  its own default. Assertions about specific artwork must account for this
  rather than for the developer's desktop theme.
- Outside the runner this host resolves **Tela**, from
  `~/.local/share/icons`. A temporary `XDG_DATA_HOME`, which the runner sets,
  removes that directory from the search path, so the theme name stays "Tela"
  while its files are unreachable and lookups fall through to hicolor/Adwaita.
- An earlier revision of this file recorded the host theme as Yaru and stated
  that `application-exit`, `view-refresh`, and `edit-find` are absent here.
  Neither claim reproduces: Yaru is not installed on this host at all, and all
  three names resolve under Tela. The absence is real but belongs to Adwaita,
  not to this host's desktop theme.

Cross-theme availability, measured with `Gtk4::IconTheme->new` retargeted per
theme. `Gtk4::IconTheme::get_for_display` returns the display singleton, and
`set_theme_name` on it is refused with an `is_display_singleton` assertion
while silently leaving the theme in place; a first attempt using the singleton
produced a 38-by-5 table of identical results that measured the live theme five
times and proved nothing. Only the standalone object discriminates:

| Name | Adwaita | Breeze | Humanity | Tela | kora |
|---|---|---|---|---|---|
| `media-playback-start` | yes | yes | yes | yes | yes |
| `list-add`, `window-close` | yes | yes | yes | yes | yes |
| `application-exit` | no | yes | yes | yes | yes |
| `view-refresh` | no | yes | yes | yes | yes |
| `help-about`, `edit-clear` | no | yes | yes | yes | yes |
| `view-fullscreen` | no | yes | yes | yes | yes |
| `media-skip-forward`/`-backward` | no | yes | yes | yes | yes |
| `edit-find` | no | yes | no | yes | yes |
| `application-exit-symbolic` | yes | yes | yes | yes | yes |
| `view-refresh-symbolic` | yes | yes | yes | yes | yes |

Adwaita carries the `-symbolic` spelling of every action name in that list.
That is the measurement behind D024: 20 of the names checked go from four of
five themes to all five once the suffixed fallback is tried. Adwaita matters
because D022 makes stock GNOME a required target.

With `icon_path` omitted or pointing at a missing directory, rendering still
succeeds: standard names resolve, bundled names return nothing and the widget
keeps its text label.

## `Filler` and the legacy size request

`t/layouts/sizing.layout` is the fixture. Note that a container's own options
go after the `=` in the legacy syntax — `VBroot= (minwidth=320) ...`, as
`gmusicbrowser_layout.pm:1001` reads them — not on the container name; writing
`VBroot(minwidth=320)=` silently produces a layout with two roots instead.

Measured on real Wayland in a 600x300 window, `direction=ltr`:

| Widget | Allocation | Size request | Note |
|---|---|---|---|
| `VBroot` | 600x300 | `320,-1` | container `minwidth` |
| `HBfillers` | 600x21 | `-1,-1` | natural row height |
| `Filler` (`_`) | 564x21 | `-1,-1` | absorbs the free space |
| `Filler2` (`4`) | 0x21 | `-1,-1` | `margin_start` 4, no width of its own |
| `HBsized` | 600x40 | `-1,-1` | raised by its tallest child |
| `Filler3` | 120x40 | `120,-1` | entirely from `minwidth` |
| `Label4` | 90x40 | `90,30` | natural width is ~9px |
| `Label5` | 21x40 | `-1,40` | `minheight` only |

`Filler3` is the clearest case: an empty box has no natural size at all, so its
120px is produced solely by the size request. `Label4` is widened tenfold past
its natural width, and `HBsized` is 40px tall against `HBfillers`' 21px because
one child declared `minheight=40`.

Asserting a container's *allocated* width against its `minwidth` would be
vacuous in a 600px window, and a mapped Wayland window cannot be shrunk below
it: `set_size_request` raises a minimum but never lowers a size the compositor
already granted — the counterpart of the `set_default_size` limitation recorded
above. The assertions therefore use `measure('horizontal',-1)`, which returns
`(minimum, natural, min_baseline, nat_baseline)`, and include a control on a
sibling row with no `minwidth` so the comparison discriminates.

Both halves are behaviour, not construction. Against a pristine `git archive`
of the preceding commit the offline `t/04_Gtk4LayoutRenderer.t` dies at
`t/layouts/sizing.layout:4: GTK4 widget 'Filler' is not implemented`. Adding
only `Filler` to that pristine copy, so the sizing assertions are reached and
judged on their own merit, then fails 4 offline assertions and aborts on the
missing `_ApplyCommonOptions`; on real Wayland `t/gtk4/30_Box.t` fails 8 of 52,
while the sibling-row control correctly passes on both trees.

GTK3 comparison for the merge semantics: a GTK3 probe confirmed that a fresh
widget reports `get_size_request` as `(-1,-1)`, that `set_size_request(120,-1)`
reads back as `(120,-1)`, and that `ApplyCommonOptions` with `minwidth=80`
alone calls `set_size_request(80,-1)`. GTK4 through this binding behaves
identically, which is why the legacy read-then-merge is ported unchanged rather
than reimplemented.

`hover_layout`, the other half of `ApplyCommonOptions`, is not ported and has
no test: it needs a popup window and a widget with its own `GdkWindow`.

## `AB` alignment

`t/layouts/align.layout` puts four expanding `AB` containers in one row so each
gets an equal slot, which makes a child's offset inside its own `AB` the only
thing the alignment decides. Measured on real Wayland in a 600px window,
`direction=ltr`:

| `AB` | Slot | Child | Child x | `halign` |
|---|---:|---:|---:|---|
| `ABstart` (`xalign=0,xscale=0`) | 150 | 7 | 0 | `start` |
| `ABcenter` (`xalign=.5,xscale=0`) | 150 | 7 | 71 | `center` |
| `ABend` (`xalign=1,xscale=0`) | 150 | 8 | 142 | `end` |
| `ABfill` (default `xscale=1`) | 147 | 147 | 0 | `fill` |

Three clearly distinct positions in identical slots, plus a fill case that
spans its slot. The test also asserts that the start, centre, and end positions
differ from each other, so the three cannot all be satisfied by one accidental
position.

This is **coverage of an implementation that already existed**, not a proof of
new behaviour: the same file passes unchanged against the preceding commit.
D025 required it before an `AB` row could be advanced, which is why it was
added; the row still does not advance. D025 is now Accepted, but it was
accepted **as a documented approximation**, so the fractional-alignment gap it
records is still open and still blocks the row.

## The `ellipsize=1` normalisation

D028 alternative 2, accepted after the entry originally recommended against
it. `Layout::Button` maps an `ellipsize=` of `'1'` to `'end'`
(`gmusicbrowser_layout.pm:3051`) while `Layout::Label` passes the value
straight through (`:3128`), so a label written `ellipsize=1` does not
ellipsize in GTK3. The label now follows the button.

The measurement that makes this non-vacuous, and the reason the fixture looks
the way it does:

| Label | `ellipsize=` | Minimum width, normalised | Un-normalised |
|---|---|---:|---:|
| `Text` | `end` | 12 | 12 |
| `Text2` | `none` | 64 | 64 |
| `Text3` | `1` | 12 | **64** |

All three carry the **identical** text `"ellipsized"`. That is what makes the
comparison measure the option: an un-ellipsized minimum tracks the text width,
so had `Text3` carried a different string it would have measured the string and
passed against the un-normalised renderer. This is the same trap recorded for
the original alignment and ellipsize assertions, and it applies to any label
comparison.

`Text5` carries `ellipsize=sideways`, a genuinely out-of-range value. It exists
because `'1'` used to be the out-of-range case, and normalising it would
otherwise have left the fatal-enum filter uncovered — an out-of-range enum
nickname dies through this binding, so reaching the assertion at all proves the
value was filtered. Both of its assertions pass on the un-normalised tree too,
which is what makes them the **control**: the comparison discriminates rather
than merely failing everything.

Against a pristine `git archive HEAD` with only the changed test files and the
fixture overlaid, `t/gtk4/30_Box.t` fails 3 of 81 on real Wayland and
`t/04_Gtk4LayoutRenderer.t` fails 2 of 179 offline. Each new assertion was
checked individually rather than by the file's failure count.

No shared code changed. `make test-gtk3` was run anyway and passes.

## Shared test fixtures

`t/RendererLabels.pm` holds the one `labels` hash the renderer tests pass. The
renderer takes every user-visible string from its caller and its constructor
rejects a hash missing any `%Buttons` tooltip, so before this the literal was
duplicated at 13 call sites across four files and every new tooltip-bearing
widget meant editing all of them. Load it with `require 't/RendererLabels.pm'`
alongside the other module requires; the tests all run with `use lib '.'` from
the repository root, and the GTK4 runner keeps that working directory.

The values match the `%Layout::Widgets` tips in `gmusicbrowser_layout.pm`,
which is what pins a tooltip assertion to the right widget entry — `Next` is
`Next Song` and `Prev` is `Recently played songs`, not the widget names.

`labels()` returns a fresh copy each call, asserted in
`t/04_Gtk4LayoutRenderer.t`, so one test mutating its labels cannot affect
another. There is deliberately no assertion that the fixture satisfies the
constructor: a `%Buttons` entry with no fixture label already aborts the whole
file at the first renderer built, with `GTK4 layout renderer needs the '<name>'
label`, which is a clearer failure than any test could add.

The symbolic fallback is a behaviour change, not a construction detail. Run
against the previous `_IconName` in a scratch copy of the tree,
`t/gtk4/40_Icons.t` fails 2 assertions, returning `application-exit` and
`view-refresh` where Adwaita can render only the symbolic variants.

The `size=`/`relief=` assertions for D027 are behaviour too. Proved by
extracting `git archive HEAD` to a scratch directory — the whole tree, not a
hand-picked subset — and overlaying only the two changed test files and the two
changed fixtures, so the old renderer is judged against the new assertions:

- `t/gtk4/40_Icons.t` fails **16 of 74** on real Wayland.
- `t/04_Gtk4LayoutRenderer.t` fails **5 of 160** offline.

The comparison discriminates rather than merely failing everything: the control
cases pass on both trees. On pristine, `relief=normal keeps the frame`, the six
`isa_ok` image checks, `an unknown size= leaves the pixel size unset`, `an
unknown size= is still reported as unhandled`, and `a real widget reports the
options it ignored` all pass, because the old renderer's GTK4 defaults happen
to be framed and unsized and it reported `size`/`relief` as unhandled.

The label alignment and ellipsize assertions for D028 are rendering, not
property read-back. `Label->get_layout_offsets` returns where the text actually
lands; the widget itself fills its slot, so `translate_coordinates` cannot see a
label's alignment. Proved the same way: `t/gtk4/30_Box.t` fails **7 of 78** on
real Wayland and `t/04_Gtk4LayoutRenderer.t` fails **10 of 177** offline against
a pristine archive with only the tests and the new fixture overlaid.

**Two of those assertions were vacuous on the first attempt, and running them
against pristine is what caught it.** Both fixes are in the fixture, not the
test:

- **Every alignment label must carry identical text.** Four *centred* labels
  with differing text render at offsets 186, 190, 188, and 187 — they already
  differ by a few pixels from the text width alone, so an `isnt` or an ordering
  comparison passes against a renderer that ignores alignment entirely. With
  identical text the only thing that can move the offset is the alignment.
- **The two ellipsize labels must carry identical text.** An un-ellipsized
  minimum width tracks the text, so comparing two different strings measures the
  strings. With the same string, `ellipsize=end` measures a 9px minimum against
  the un-ellipsized string's full width.

**A `measure()` check on an icon only discriminates above 16px.** GTK4's own
default icon size is 16, so the `menu`, `button`, and `small-toolbar` rows
measure correctly even against a renderer that ignores `size=` entirely — three
of the nine measure assertions pass on pristine. `get_pixel_size` is what
actually pins those three. This is the same class of trap as the recorded
`set_size_request` one: a physical measurement that agrees with the expectation
by coincidence rather than because the option took effect. Both are in D006.

A reduced GTK3 probe on 2026-09-07 copied the legacy pane calculations into
`/tmp/gmb-legacy-paned-wayland.pl`, used two labels, temporary XDG config/data/
cache directories, and `GDK_BACKEND=wayland timeout 30s perl` to run it. It
exited zero and printed observations; it was not an assertion-backed test or
a full application regression. At maximum position 599, `200-200` restored to
399 for start-only resize, 200 for end-only, and 299 for both/neither. Moving
to 150 saved `150-449`. Increasing the maximum to 699 produced positions 250,
150, and 175 respectively. These observations support the resize-policy
translation; different fixtures and window geometry mean they are not a
GTK3/GTK4 parity comparison. The temporary script is not a permanent test.

## GTK3 regression smoke

```sh
make test-gtk3
```

`tools/run-gtk3-smoke` starts the unchanged GTK3 entry point on the real
Wayland connection with isolated `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
`XDG_CACHE_HOME`, and `XDG_STATE_HOME`, waits for it to reach the main loop,
shuts it down with `SIGTERM`, and reports one TAP assertion on the exit status.
It exits 77 with a reason when there is no Wayland socket or no `Gtk3`. It runs
with `-nodbus -noscan -nocheck -demo`, and `-demo` means it never writes tags
or settings.

The real `XDG_RUNTIME_DIR` is kept rather than replaced with a symlink farm.
`use Gtk3 '-init'` at `gmusicbrowser.pl:26` initialises GDK at compile time, so
the Wayland socket must already be reachable under its own name; pointing
`XDG_RUNTIME_DIR` at a temporary directory produced `cannot open display`
before any application code ran.

Shutdown must go through `SIGTERM`, which `gmusicbrowser.pl:1938` wires to
`Quit` immediately before `Gtk3->main`. On 2026-09-07 this passed on both the
working tree and a pristine `git archive` of HEAD, with byte-identical
diagnostics on each: the optional MPRIS2 plugin fails to load because
`Net::DBus::Annotation` is missing, the mpv backend reports itself disabled, one
`gtk_widget_get_scale_factor: assertion 'GTK_IS_WIDGET (widget)' failed`
critical is emitted, and perl exits 0. Those warnings are pre-existing, so this
is a startup/shutdown regression check rather than a clean GTK3 acceptance
result.

Corrections recorded on 2026-09-07, replacing two earlier readings:

- An earlier revision stated that `perl gmusicbrowser.pl -layout "with
  playlist" -cmd Quit` with temporary XDG directories "wrote its configuration
  and exited zero". It does not on this host: it exits **2**, because
  `Net::DBus` is not installed, so `gmusicbrowser.pl` warns that
  `gmusicbrowser_dbus.pm` failed to load and then calls the undefined
  `GMB::DBus::simple_call` at `gmusicbrowser.pl:512` anyway. A pristine
  `git archive` of HEAD fails identically, so it is pre-existing. The earlier
  "exited zero" reading was probably a `tail`'s exit status at the end of a
  pipeline. `perl -I. -c gmusicbrowser.pl` fails at the same line for the same
  reason, on the committed file too.
- A later revision concluded from this that "there is currently no scripted
  GTK3 startup/shutdown smoke on this host" and that with `-nodbus` "the
  command is not delivered". Both are wrong, and the second was a misdiagnosis.
  `-nodbus` *does* deliver the command: `gmusicbrowser.pl:1937` calls
  `run_command(undef,'Quit')`. The problem is that `Quit` is not in the
  `%Command` fifo table at all — it is a frontend lifecycle operation — so
  `run_command` warns `Unknown command 'Quit'` at line 1716 and the application
  keeps running until it is killed. Using `SIGTERM` instead makes a scripted
  smoke work, which is what `tools/run-gtk3-smoke` does. Budget for `pkill`ing
  a stray `gmusicbrowser.pl` if a `-cmd Quit` route is attempted again;
  gmusicbrowser also outlives `timeout`, so an outer hard kill is needed.

Two further corrections recorded on 2026-09-07, both to probe *method* rather
than to a test result. Neither had reached a committed test, but both were
recorded as binding evidence and both overstate what was shown:

- **`Glib::Type->from_package` was said to report lazily-registered classes as
  absent, with probing-by-construction reversing the result.** The
  construction results stand — `Gtk4::Fixed`, `Gtk4::Overlay`,
  `Gtk4::CenterBox`, `Gtk4::ConstraintLayout`, and `Gtk4::BinLayout` all
  construct — but `from_package` is **not a method on this binding**, so it
  never reported anything and there is no evidence for lazy registration. The
  bad reading came from treating a died method call as a falsy answer. Probe a
  class by constructing it inside `eval`.
- **`measure` and `do_measure` were listed among five vfunc names tried, none
  called.** The conclusion is right and is now the basis of D025's alternative
  1 being impossible, but the evidence was contaminated: a lowercase `measure`
  sub *shadows* the introspected method, so the probe's own
  `$widget->measure(...)` call invoked it. Re-run with only the
  uppercase/`do_`-prefixed names on a subclass with nothing shadowing a real
  method, `MEASURE`, `SIZE_ALLOCATE`, `do_measure`, and `do_size_allocate` are
  all defined and **none** is called during GTK's own layout pass; the widget
  is allocated height 0 against an override claiming 40 and
  `measure('horizontal',-1)` reads back `0,0,-1,-1`. Judge a vfunc override by
  whether GTK's layout pass calls it, never by a direct Perl method call.

The GTK3 side of this increment: `@Commands` in
`gmusicbrowser_frontend_legacy.pm` is shared code, and widening it makes the
bridge require `NextSong` and `PrevSong` at construction. The failure mode is
therefore a GTK3 startup abort at `gmusicbrowser.pl:1866`. Two checks cover it.
`make test-gtk3` exercises the real path and passes identically on the working
tree and on pristine HEAD. Separately, a scratch probe extracted the `%Command`
table from the unmodified `gmusicbrowser.pl` by regex, found 74 entries with all
nine bridge names present, constructed the bridge against it, dispatched
`NextSong`, `PrevSong`, and `Stop`, and confirmed `CloseWindow` and
`SetFocusOn` stay unregistered. That probe was not kept as a permanent test.

`perl -c gmusicbrowser_layout.pm` fails on the `_"..."`
gettext idiom for the committed file as well; that module is not standalone
compilable and the failure is not a regression.

The `%Buttons` widgets are covered on both sides. `t/layouts/buttons.layout` is
the fixture; it now carries `Prev`, `Stop`, `Stop4`, and `Next` plus a
`Prev2(nbsongs=4,group=Recent)` and `Next2(size=menu,relief=normal,tip="Skip")`
that exercise the unhandled-option path. It has one root container, because the
renderer requires exactly one and three top-level containers would be three
roots.

Offline in `t/04_Gtk4LayoutRenderer.t` there is no icon theme behind the
doubles, so every icon resolves to nothing and the assertions cover the text
fallback, the default tooltip, a layout `tip=` override, per-widget command
routing, repeated stateless dispatch, and the `Unhandled` report. On real
Wayland in `t/gtk4/40_Icons.t` the same fixture resolves icons from the active
theme, carries no text label, keeps its tooltips, honours a layout `stock=`
override, reports its ignored options, and dispatches `Stop`, `NextSong`, and
`PrevSong` when `clicked` is emitted.

Both are behaviour, not construction. Run against `git archive` of the
preceding commit, with only the test files and the fixture overlaid on the
pristine tree, `t/04_Gtk4LayoutRenderer.t` and `t/gtk4/40_Icons.t` both die at
`t/layouts/buttons.layout:4: GTK4 widget 'Prev' is not implemented`, and
`t/05_FrontendLegacy.t` fails 7 of 47 assertions because the pristine bridge
does not require `NextSong` or `PrevSong`. `t/06_LifecycleLegacy.t` still
passes there: the two added names ride along in its command fixture and its
role is startup/shutdown ordering, not the command allowlist.

`Next` and `Prev` are the first production consumers of the D024 symbolic
fallback. Measured in the runner environment, Adwaita carries
`media-skip-forward` and `media-skip-backward` **only** as `-symbolic`, so both
buttons resolve to `media-skip-forward-symbolic` and
`media-skip-backward-symbolic`, while `Stop` still resolves the unsuffixed
`media-playback-stop`. Without D024 these two widgets would have fallen back to
a text label on stock GNOME. The assertions accept either spelling so they do
not pin one theme's convention.

`Gtk4::Button->activate` does not work for this: it needs a mapped, focusable
widget and left the command undispatched. Emitting `clicked` is the signal a
real click raises and is the same technique `t/gtk4/20_Paned.t` uses for action
signals. Neither is synthesised pointer input.

Adding a `%Buttons` default `stock` made every button consult the icon theme,
where previously only a layout-supplied icon did. That broke the offline doubles,
which have no `Gtk4::Gdk::Display::get_default` at all, so `_IconTheme` now
wraps the display lookup in `eval`: the subroutine is absent rather than merely
returning nothing when the renderer runs without a real binding.

`t/01_ModFileMetadata.t` remains outside the offline target because it downloads
media samples at runtime and the repository contains none of those samples.
M0 remains open until redistributable local fixtures replace that download.
Do not run it in an offline or network-restricted job and do not interpret its
exclusion as a pass.

Real frontend comparisons must use the same fixture library, configuration,
layout, action sequence, theme, scale, and window size. Record the backend,
skips, screenshots, interaction results, timings, and memory measurements with
the test artifacts.
