# Modernization tests

Status: Wave 2 infrastructure

The GTK-free modernization tests are deterministic and offline:

```sh
make test-modernization
```

This runs the neutral layout parser, frontend contract and lifecycle, legacy
adapter and lifecycle integration, and GTK4 renderer contract tests. On
2026-09-07 it reported 261 executed assertions passed and no skips. The
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
2026-09-07 the full `make test-gtk4` run reported 160 TAP results: 154 executed
assertions passed and the same six feasibility probes were skipped. The box file
contributes 34 executed assertions and the icon file 20. They read allocated child offsets with
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

`t/gtk4/40_Icons.t` covers GTK4 icon resolution with 20 executed assertions on
real Wayland. It uses `t/layouts/icons.layout`, which exercises a legacy `gtk-*`
name, the `stock=` option, a bundled `gmb-*` file, a bundled alias with no file
of its own, an unresolvable name, and a widget with no icon option.

Measured on this host (GTK 4.14.5, Yaru theme), which is why the resolution
chain exists rather than a direct pass-through:

- 14 of the 15 legacy `gtk-*` names used by bundled layouts resolve to nothing
  in GTK4; only `gtk-fullscreen` is still found. GTK4 removed the stock-item
  system, so these need explicit mapping.
- Bundled `gmb-*` names resolve straight from the flat `pix/` directory once it
  is on the search path; no themed `index.theme` hierarchy and no file moves.
- `gmb-queue0`, `gmb-queue-window`, `gmb-random-album`, and
  `gmb-view-fullscreen` ship no file of their own and need the same fallback
  indirection GTK3 applies through `%IconsFallbacks`.
- Several freedesktop names are themselves absent here, including
  `application-exit`, `view-refresh`, and `edit-find`. A mapped name that the
  active theme lacks still renders: `lookup_icon` returns a paintable because
  GTK substitutes its missing-image icon, confirmed with a mapped button that
  allocated 188x70 and displayed. So the resolver keeps a mapped name even when
  `has_icon` is false, and only an unmapped unknown name falls back to text.

With `icon_path` omitted or pointing at a missing directory, rendering still
succeeds: standard names resolve, bundled names return nothing and the widget
keeps its text label.

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
GTK3 acceptance result. Repeated on 2026-09-07 after the box change with
`-layout "with playlist"` and temporary XDG directories, GTK3 started, accepted
`-cmd Quit`, wrote its configuration and exited zero with the same three
pre-existing warnings. `perl -c gmusicbrowser_layout.pm` fails on the `_"..."`
gettext idiom for the committed file as well; that module is not standalone
compilable and the failure is not a regression.

`t/01_ModFileMetadata.t` remains outside the offline target because it downloads
media samples at runtime and the repository contains none of those samples.
M0 remains open until redistributable local fixtures replace that download.
Do not run it in an offline or network-restricted job and do not interpret its
exclusion as a pass.

Real frontend comparisons must use the same fixture library, configuration,
layout, action sequence, theme, scale, and window size. Record the backend,
skips, screenshots, interaction results, timings, and memory measurements with
the test artifacts.
