# Session handoff

Status: uncommitted work in the tree, GTK4 box packing corrected and GTK4 icon
resolution added

Last session: 2026-09-07. Branch `gtk4-alpha`.

Read `MODERNIZATION.md` and `AGENTS.md` first. This file only records where the
previous session stopped and what the next one should verify before continuing.

## Actual state of the port

The GTK4 work is an early spike, not a partly-finished migration. Do not assume
otherwise from the size of the planning documents.

- `gtk4-alpha` is three commits past `master`: `initial plan`, `agents file`,
  `initial gtk4 stubs`.
- All 1,444 `Gtk3::` references are still present and unmodified across 27
  files. None has been ported.
- GTK3 is the complete, working application (about 33,000 lines in the main
  modules). It is not a beta layer. The port direction is GTK3 to GTK4.
- The current branch is `gtk4-alpha`. A separate `gtk4` branch exists but points
  at the same commit as `master`.

## Uncommitted work in the tree

Nothing has been committed. `git status` shows:

	M docs/modernization/PARITY_CHECKLIST.md
	M docs/modernization/TESTING.md
	M gmusicbrowser_gtk4_layout.pm
	M t/04_Gtk4LayoutRenderer.t
	M tools/run-gtk4-smoke
	?? docs/modernization/SESSION_HANDOFF.md
	?? t/gtk4/20_Paned.t
	?? t/gtk4/30_Box.t
	?? t/gtk4/40_Icons.t
	?? t/layouts/containers.layout
	?? t/layouts/icons.layout
	?? t/layouts/packing.layout
	?? t/layouts/single.layout

`docs/modernization/DECISIONS.md` gained D023 for GTK4 icon handling.

`t/gtk4/20_Paned.t` was also edited this session: its window-resize step used
`set_default_size`, which does nothing to an already-mapped Wayland window.

The renderer went from 2 containers to 8, ordered by how often each appears in
the bundled layouts rather than alphabetically:

| Container | Uses in `layouts/` | State |
|---|---:|---|
| `HB`, `VB` | 449 | packing prefixes completed |
| `HP`, `VP` | 76 | implemented |
| `SB`, `FR`, `EB`, `AB`, `WB` | single-child | implemented |
| `SM`, `MB`, `BM` | 54 | not started |
| `NB` | 16 | not started |
| `TB`, `FB` | 4 | not started |

What changed in `gmusicbrowser_gtk4_layout.pm`:

- `_CreateContainer` now dispatches by element instead of handling only boxes.
- `_CreateBox` implements the full legacy `BoxPack` prefix set: digits are
  padding, `_` is expand, `-` packs from the far edge, `.` turns fill off. The
  previous renderer rejected `-` and `.` outright.
- `_CreatePaned` implements `PanedPack`: `_` is resize, `+` disables shrink,
  and the `size` option sets the initial handle position.
- `_CreateSingle` covers `SB`, `FR`, `EB`, `AB`, and `WB`.
- The generic `border` container option becomes margins.

The first container increment brought `t/04_Gtk4LayoutRenderer.t` to 44
assertions. Pane saved-size coverage brought it to 88; the box packing
increment brings it to 105, and the whole offline suite to 261. All pass.

`_CreateBox` was rewritten this session. The previous version had two defects,
both now corrected and covered by real geometry tests:

- It set fill on the cross axis with `set_valign`/`set_halign` reversed.
  Legacy `fill` acts on the packing axis and only matters while expanding.
- It used `prepend` for `-`, which placed end-packed children at the near edge
  in reverse. Legacy `pack_end` places them at the far edge, first one
  outermost.

The replacement keeps a single insertion point: once any `-` child has been
packed, every later child is inserted after the last start-packed child with
`insert_child_after`, which reproduces both groups' legacy order including
interleaved `-a b -c d`. `insert_child_after($widget,undef)` prepends, which is
correct when no start child exists yet.

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

Commands that were actually run and passed:

	prove -I. t/02_LayoutParser.t t/03_FrontendContract.t \
	      t/04_Gtk4LayoutRenderer.t t/05_FrontendLegacy.t t/06_LifecycleLegacy.t
	perl -c gmusicbrowser_gtk4_layout.pm
	perl -c t/04_Gtk4LayoutRenderer.t
	perl -c t/gtk4/20_Paned.t
	perl -c t/gtk4/30_Box.t
	sh -n tools/run-gtk4-smoke
	make test-modernization
	make test-gtk4
	git diff --check

`make test-modernization`: 261 executed assertions passed, no skips.

`make test-gtk4` on the real Wayland connection: 160 TAP results, comprising
154 executed assertions passed and the same six pre-existing feasibility
probes skipped, 0 failures. That is 84 pane, 34 box, and 20 icon assertions
plus the binding and proof-of-life files. Do not restate this as 160 passing
assertions.

Pane tests exercise both orientations, saved-size reconstruction, notification
state before saving, focus/action signals, and real window resizing under all
four resize policies. Box tests exercise allocated offsets and widths for
mixed, interleaved, and expand/fill rows in both axes. Physical pointer and
keyboard input is not covered by either.

GTK3 comparison: the unchanged production `BoxPack` was extracted from
`gmusicbrowser_layout.pm` and driven by the same fixture, parser, width, child
size request and text direction. GTK3 and GTK4 produced identical offsets and
widths in all three rows; the table is in `TESTING.md`. GTK3 also started with
`-layout "with playlist"`, accepted `-cmd Quit`, wrote its configuration and
exited zero, with only the three pre-existing warnings. That is a startup and
shutdown smoke plus a focused packing comparison, not a full GTK3 application
regression pass. No shared or GTK3 production code changed.

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
(`size=button`, `size=large-toolbar`, `size=menu`), `relief=none`, the
`stock="on:... off:..."` two-state form used by `LockAlbum`, and symbolic
variants are all unhandled. No GTK3 icon code was touched.

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

1. Keep running `make test-gtk4` on the real Wayland connection with the system
   packages, outside the execution sandbox when needed. Count explicit skips.
2. Write the `DECISIONS.md` entries for `AB` and `WB`. These are the oldest
   outstanding item and they block those two rows from ever reaching parity.
3. Add a D006 evidence note that this binding cannot marshal graphene types,
   so `compute_bounds`/`compute_point` are unavailable and geometry must go
   through `translate_coordinates`.
4. Move D023 from Proposed to Accepted, or push back on it, before more
   icon-bearing widgets are added.
5. Investigate the queue clipping properly: make `QueueList` propagate a
   minimum width from its configured columns. See the dead-end section above
   before touching `layouts/shimmer.layout`; the obvious `+` fix is disproven.
6. Integrate renderer saved options with an isolated configuration round trip,
   then compare physical pane input and accessibility against GTK3.
7. Consider right-to-left packing. GTK4 `insert_child_after` is direction
   independent, but the legacy far-edge meaning of `-` is not, and no bundled
   layout has been checked under `rtl`.
8. Then menus, `SM`/`MB`/`BM`, 54 uses. **Do not start these without asking the
   user first.** GTK4 replaced `GtkMenu` with `GMenu` and `PopoverMenu` models,
   so this is a design change rather than mechanical translation, and
   `plugins/appindicator.pm` is explicitly marked "do not port its GTK3 menu".

## Working notes

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
- Only `Label`, `Text`, `Play`, and `Quit` widget elements exist in the GTK4
  renderer. A fixture needing an expanding filler must use `Text`, not the
  legacy `Filler` widget.
- The GTK3 reference geometry is best obtained by extracting `BoxPack` from
  `gmusicbrowser_layout.pm` with a regex and `eval`, so the comparison uses
  production code rather than a copy. That module is not standalone
  compilable: `perl -c` fails on its `_"..."` gettext idiom, for the committed
  file too.
- `t/layouts/packing.layout` is the box fixture. Its rows deliberately include
  an expanding child, because a `-` child only reaches the far edge when some
  child expands.
