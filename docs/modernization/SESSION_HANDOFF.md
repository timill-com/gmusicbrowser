# Session handoff

Status: `HEAD` is `4ed26ad` "gtk4: render the Stop widget from a stateless
button table". Uncommitted on top of it: the `Next`/`Prev` increment, which
includes the first shared-boundary change of the port and a working GTK3
regression smoke.

Last session: 2026-09-07. Branch `gtk4-alpha`.

Read `MODERNIZATION.md` and `AGENTS.md` first. This file only records where the
previous session stopped and what the next one should verify before continuing.

## Actual state of the port

The GTK4 work is an early spike, not a partly-finished migration. Do not assume
otherwise from the size of the planning documents.

- `gtk4-alpha` is six commits past `master`: `initial plan`, `agents file`,
  `initial gtk4 stubs`, then the box/icon, `-symbolic`, and `Stop` commits.
- All 1,444 `Gtk3::` references are still present and unmodified across 27
  files. None has been ported.
- GTK3 is the complete, working application (about 33,000 lines in the main
  modules). It is not a beta layer. The port direction is GTK3 to GTK4.
- The current branch is `gtk4-alpha`. A separate `gtk4` branch exists but points
  at the same commit as `master`.

## What is committed and what is not

Everything through the `Stop` widget is committed; `HEAD` is `4ed26ad` and
`gtk4-alpha` is six commits past `master`.

Uncommitted in the tree is the `Next`/`Prev` increment:

	M Makefile
	M docs/modernization/DECISIONS.md
	M docs/modernization/PARITY_CHECKLIST.md
	M docs/modernization/SESSION_HANDOFF.md
	M docs/modernization/TESTING.md
	M gmusicbrowser_frontend_legacy.pm
	M gmusicbrowser_gtk4.pl
	M gmusicbrowser_gtk4_layout.pm
	M t/04_Gtk4LayoutRenderer.t
	M t/05_FrontendLegacy.t
	M t/06_LifecycleLegacy.t
	M t/gtk4/20_Paned.t
	M t/gtk4/30_Box.t
	M t/gtk4/40_Icons.t
	M t/layouts/buttons.layout
	?? tools/run-gtk3-smoke

No GTK3 production code, bundled layout, or file in `pix/` has been touched.
`gmusicbrowser.pl` is unmodified. `tools/run-gtk3-smoke` is the only added
file this session; `t/layouts/buttons.layout` was added by the previous one.

## Renderer widget state

Widget elements implemented: `Label`, `Text`, `Play`, `Quit`, `Stop`, `Next`,
`Prev` — 7 of the ~100 in the layout compatibility surface. This is still the
real bottleneck: containers cover 8 of 15 types and are well ahead of anything
to put in them.

The three `%Buttons` entries (`Prev`, `Stop`, `Next`) exhaust the stateless
transport buttons whose commands the bridge exposes. Adding another means
either widening `@Commands` again — now a proven, cheap operation with
`make test-gtk3` available — or implementing a stateful button, which needs a
state getter and an event subscription the way `Play` does.

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

## This session: `Next` and `Prev`, and the first shared-boundary change

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

### The labels hash is now at twelve call sites

The renderer constructor rejects a `labels` hash missing any `%Buttons`
tooltip, so `next` and `prev` had to be added at eleven test call sites plus
`gmusicbrowser_gtk4.pl`. The duplicated literal is now a genuine maintenance
cost — the next widget with a tooltip will touch all twelve again. Extracting
a fixture constant was deliberately **not** bundled here, per the previous
handoff, but it should be the next cleanup.

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

The `Next`/`Prev` assertions cannot pass against the previous tree either. The
proof was run by extracting `git archive HEAD` to a scratch directory — the
whole tree, so no file is missing — and overlaying only the changed test files
and the fixture:

- `t/04_Gtk4LayoutRenderer.t` and `t/gtk4/40_Icons.t` both die at
  `t/layouts/buttons.layout:4: GTK4 widget 'Prev' is not implemented`.
- `t/05_FrontendLegacy.t` fails 7 of 47 assertions, because the pristine bridge
  neither exposes nor requires `NextSong`/`PrevSong`.
- `t/06_LifecycleLegacy.t` passes against pristine. That is honest rather than
  a gap: the two added names ride along in its command fixture, and its role is
  startup/shutdown ordering, not the command allowlist. Do not cite it as
  proof of this increment.

Commands that were actually run and passed this session:

	perl -I. -c gmusicbrowser_frontend_legacy.pm
	perl -I. -c gmusicbrowser_gtk4_layout.pm
	perl -I. -c gmusicbrowser_gtk4.pl
	perl -I. -c t/04_Gtk4LayoutRenderer.t t/05_FrontendLegacy.t \
	      t/06_LifecycleLegacy.t t/gtk4/40_Icons.t     # one file per invocation
	sh -n tools/run-gtk3-smoke
	prove --norc -I. t/02_LayoutParser.t t/03_FrontendContract.t \
	      t/04_Gtk4LayoutRenderer.t t/05_FrontendLegacy.t t/06_LifecycleLegacy.t
	make test-modernization
	make test-gtk4
	make test-gtk3
	git diff --check

`make test-modernization`: **298** executed assertions passed, no skips, up
from 269. The skip count was read from `prove -v`, not assumed.

`make test-gtk4` on the real Wayland connection: **184** TAP results,
comprising **178 executed assertions passed** and the same six pre-existing M1
feasibility probes skipped, 0 failures. Per file: 18 binding (which is where
all six skips live), 4 proof-of-life, 84 pane, 34 box, 44 icon. Do not restate
this as 184 passing assertions. The six skips were counted from `prove -v`
output run through a copy of the runner in a scratch directory, not assumed.

`make test-gtk3`: 1 assertion passed on the real Wayland connection, and the
same command passed identically against a pristine `git archive` of HEAD with
byte-identical diagnostics. Both runs emit the pre-existing missing
`Net::DBus::Annotation` for the MPRIS2 plugin, the disabled mpv backend, and
one `gtk_widget_get_scale_factor` GTK critical, and both exit 0. `Net::DBus`
itself is still not installed, so `perl -I. -c gmusicbrowser.pl` still fails at
line 512 — on the committed file too, so that is not a regression.

`gmusicbrowser_layout.pm` was not changed and still is not standalone
compilable: `perl -c` fails on its `_"..."` gettext idiom for the committed
file as well.

Pane tests exercise both orientations, saved-size reconstruction, notification
state before saving, focus/action signals, and real window resizing under all
four resize policies. Box tests exercise allocated offsets and widths for
mixed, interleaved, and expand/fill rows in both axes. Physical pointer and
keyboard input is not covered by either.

GTK3 regression status for this session: **shared code did change**, so the
"cannot be affected" reasoning used by previous sessions does not apply here.
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

0. **Highest-value cleanup, now overdue:** extract the `labels` hash into a
   test fixture constant. It is duplicated at eleven test call sites plus
   `gmusicbrowser_gtk4.pl`, and every future tooltip-bearing widget touches all
   twelve. Deliberately not bundled with this increment.
1. Keep running `make test-gtk4` on the real Wayland connection with the system
   packages, outside the execution sandbox when needed. Count explicit skips.
   Also run `make test-gtk3` after any shared-code change; it works now.
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
   **New evidence for D024 this session:** `Next` and `Prev` are its first
   production consumers. Adwaita carries `media-skip-forward` and
   `media-skip-backward` only as `-symbolic`, so without the fallback both
   would render as text on stock GNOME, a D022 target.
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
