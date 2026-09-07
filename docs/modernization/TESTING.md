# Modernization tests

Status: Wave 2 infrastructure

The GTK-free modernization tests are deterministic and offline:

```sh
make test-modernization
```

This runs the neutral layout parser, frontend contract and lifecycle, legacy
adapter and lifecycle integration, and GTK4 renderer contract tests. On
2026-09-07 it reported 344 executed assertions passed and no skips. Running
totals: 269 at the start of the previous session, 298 after `Next`/`Prev`, 315
after `Filler`, 317 after the shared labels fixture, 325 after the
`size=`/`relief=` increment, 342 after label alignment/ellipsize, 344 after the
`ellipsize=1` normalisation. The skip count was read from `prove -v`, not
assumed. The
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
`AB` and label alignment coverage. On 2026-09-07, after the `ellipsize=1`
normalisation, the full
`make test-gtk4` run reported 261 TAP results: 255 executed assertions passed
and the same six feasibility probes were skipped, 0 failures. The skips were
counted from `prove -v` and are the same six M1 probes as before. Running
totals for the same command: 173 results before `Next`/`Prev`, 184 after it,
202 after `Filler`, 216 after the `AB` alignment coverage, 246 after
`size=`/`relief=`, 258 after label alignment, 261 after the `ellipsize=1`
normalisation. Per file: 18 binding, which is
where all six skips live, 4 proof-of-life, 84 pane, 81 box, 74 icon.
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
