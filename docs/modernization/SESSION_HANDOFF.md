# Session handoff

Status: uncommitted work in the tree, GTK4 icon resolution given a `-symbolic`
fallback; several earlier verification claims corrected after re-measurement

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

## What is committed and what is not

The previous session's work **is committed**. `HEAD` is `e016554`
"gtk4: correct box packing geometry and resolve icons by theme name", and
`gtk4-alpha` is four commits past `master`. An earlier revision of this file
claimed that work was uncommitted and listed a `git status` that no longer
applies; that listing has been removed rather than corrected, because it
described a tree state that no longer exists.

This session's changes are uncommitted:

	M docs/modernization/DECISIONS.md
	M docs/modernization/PARITY_CHECKLIST.md
	M docs/modernization/SESSION_HANDOFF.md
	M docs/modernization/TESTING.md
	M gmusicbrowser_gtk4_layout.pm
	M t/gtk4/40_Icons.t

No GTK3 production code, bundled layout, or file in `pix/` was touched. No file
was added or removed.

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

## This session: the `-symbolic` fallback (D024)

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

Three recorded results were wrong. They are corrected in `TESTING.md`; the
method that produced each bad reading is recorded because the same traps are
easy to hit again.

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
  "exited zero" was most likely `tail`'s exit status from a pipeline. There is
  currently **no** working scripted GTK3 startup/shutdown smoke on this host:
  `-nodbus` does not deliver the command, the window stays open, and the
  process outlives `timeout` and must be killed.

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

The icon assertions added this session are also behaviour, not construction.
Against the previous `_IconName`, `t/gtk4/40_Icons.t` fails 2 assertions,
returning `application-exit` and `view-refresh` where Adwaita can render only
the symbolic spellings. Confirmed by running the new test against a scratch
copy of the tree carrying the old resolver.

Commands that were actually run and passed this session:

	prove -I. t/02_LayoutParser.t t/03_FrontendContract.t \
	      t/04_Gtk4LayoutRenderer.t t/05_FrontendLegacy.t t/06_LifecycleLegacy.t
	perl -c gmusicbrowser_gtk4_layout.pm
	perl -c t/gtk4/40_Icons.t
	make test-modernization
	make test-gtk4
	git diff --check

`make test-modernization`: 261 executed assertions passed, no skips. Unchanged
by this session; the renderer doubles never reach a real icon theme.

`make test-gtk4` on the real Wayland connection: 167 TAP results, comprising
161 executed assertions passed and the same six pre-existing feasibility
probes skipped, 0 failures. That is 84 pane, 34 box, and 27 icon assertions
plus the binding and proof-of-life files. Do not restate this as 167 passing
assertions. The six skips were counted from `prove -v` output, not assumed, and
they are the same six M1 probes as before: the icon test's own theme-premise
guards did not fire on this host, so all three symbolic assertions executed.

Pane tests exercise both orientations, saved-size reconstruction, notification
state before saving, focus/action signals, and real window resizing under all
four resize policies. Box tests exercise allocated offsets and widths for
mixed, interleaved, and expand/fill rows in both axes. Physical pointer and
keyboard input is not covered by either.

GTK3 comparison: the unchanged production `BoxPack` was extracted from
`gmusicbrowser_layout.pm` and driven by the same fixture, parser, width, child
size request and text direction. GTK3 and GTK4 produced identical offsets and
widths in all three rows; the table is in `TESTING.md`. That is a focused
packing comparison, not a full GTK3 application regression pass. The GTK3
startup/shutdown smoke that previously accompanied it does not actually pass
on this host; see the corrections section above. No shared or GTK3 production
code changed this session, and this session's change is confined to the GTK4
renderer, so the GTK3 path cannot be affected by it.

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

1. Keep running `make test-gtk4` on the real Wayland connection with the system
   packages, outside the execution sandbox when needed. Count explicit skips.
2. Write the `DECISIONS.md` entries for `AB` and `WB`. These are the oldest
   outstanding item and they block those two rows from ever reaching parity.
   **Still not done.** This session did the D006 note and the symbolic
   fallback instead; `AB`/`WB` remain approximations and must not be advanced
   to parity until their entries are accepted.
3. Add a D006 evidence note about graphene types. **Done this session.** D006
   now records the graphene marshalling failure, the `->can` segfault, the
   widget-before-`Gtk4::init` segfault, the empty-string boolean artifact, and
   the `set_theme_name` display-singleton refusal.
4. Move D023 from Proposed to Accepted, or push back on it, before more
   icon-bearing widgets are added. D024 is now in the same position: both are
   Proposed and both concern icon resolution, so decide them together.
   Decide also whether to propose mapping `gmb-*` to freedesktop names, which
   D023 alternative 2 currently defers and which this session did not do.
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
- GTK3 with `-cmd` and no `Net::DBus` exits 2 at `gmusicbrowser.pl:512`, and
  with `-nodbus` it hangs past `timeout` and must be `pkill`ed. Budget for
  cleaning up stray `gmusicbrowser.pl` processes if you try either.
