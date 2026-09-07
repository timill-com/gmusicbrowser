# Modernization tests

Status: Wave 2 infrastructure

The GTK-free modernization tests are deterministic and offline:

```sh
make test-modernization
```

This runs the neutral layout parser, frontend contract and lifecycle, legacy
adapter and lifecycle integration, and GTK4 renderer contract tests. On
2026-09-07 it reported 269 executed assertions passed and no skips. The
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

`t/gtk4/30_Box.t` adds real `HB`/`VB` packing geometry to the runner. On
2026-09-07 the full `make test-gtk4` run reported 173 TAP results: 167 executed
assertions passed and the same six feasibility probes were skipped. The box file
contributes 34 executed assertions and the icon file 33. They read allocated child offsets with
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

`t/gtk4/40_Icons.t` covers GTK4 icon resolution with 33 executed assertions on
real Wayland. It uses `t/layouts/icons.layout`, which exercises a legacy `gtk-*`
name, the `stock=` option, a bundled `gmb-*` file, a bundled alias with no file
of its own, an unresolvable name, and a widget with no icon option. It then
pins a standalone icon theme to Adwaita to check the `-symbolic` fallback added
for D024.

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

The symbolic fallback is a behaviour change, not a construction detail. Run
against the previous `_IconName` in a scratch copy of the tree,
`t/gtk4/40_Icons.t` fails 2 assertions, returning `application-exit` and
`view-refresh` where Adwaita can render only the symbolic variants.

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

The GTK3 entry point also completed an isolated Wayland startup and orderly
shutdown smoke. That run reported an unavailable optional MPRIS2 dependency,
an inactive mpv backend, and one GTK widget assertion; it is not yet a clean
GTK3 acceptance result.

Correction recorded on 2026-09-07: an earlier revision of this file stated that
`perl gmusicbrowser.pl -layout "with playlist" -cmd Quit` with temporary XDG
directories "wrote its configuration and exited zero". It does not on this
host. It exits **2**, because `Net::DBus` is not installed: `gmusicbrowser.pl`
warns that `gmusicbrowser_dbus.pm` failed to load and then calls
`GMB::DBus::simple_call` at `gmusicbrowser.pl:512` regardless, which is an
undefined subroutine. The earlier "exited zero" reading was probably the exit
status of a `tail` at the end of a pipeline rather than of perl.

This is pre-existing and unrelated to the GTK4 work: a pristine `git archive`
of HEAD fails identically with the same error and the same exit status. It is
only reached when `-cmd` is passed without `-nodbus`. Passing `-nodbus`
instead does not give a usable smoke either: the command is not delivered, the
window stays open, and the process outlives `timeout`, so it has to be killed.
Until `Net::DBus` is available or that code path is fixed, there is no
scripted GTK3 startup/shutdown smoke on this host. Do not cite one as passing.

`perl -c gmusicbrowser_layout.pm` fails on the `_"..."`
gettext idiom for the committed file as well; that module is not standalone
compilable and the failure is not a regression.

The `Stop` widget increment is covered on both sides. `t/layouts/buttons.layout`
is the fixture. Offline in `t/04_Gtk4LayoutRenderer.t` there is no icon theme
behind the doubles, so every icon resolves to nothing and the assertions cover
the text fallback, the default tooltip, a layout `tip=` override, and repeated
stateless dispatch. On real Wayland in `t/gtk4/40_Icons.t` the same fixture
resolves `media-playback-stop` from the host theme, carries no text label, keeps
its tooltip, honours a layout `stock=` override, and dispatches `Stop` when
`clicked` is emitted.

Both are behaviour, not construction: run against HEAD before the increment,
each file dies with `GTK4 widget 'Stop' is not implemented`, so neither can pass
against the previous renderer.

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
