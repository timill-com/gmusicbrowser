# Modernization tests

Status: Wave 2 infrastructure

The GTK-free modernization tests are deterministic and offline:

```sh
make test-modernization
```

This runs the neutral layout parser, frontend contract and lifecycle, legacy
adapter and lifecycle integration, and GTK4 renderer contract tests. The
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

On 2026-09-06 the GTK4 binding and proof-of-life tests passed 22 assertions on
a real Wayland connection using privately extracted Ubuntu archives. This is
valid local evidence but is not a replacement for the pinned, reproducible
package required by M1. A normal `make test-gtk4` still exits 77 on this host
until the packages are installed or the project supplies that package.

The GTK3 entry point also completed an isolated Wayland startup and orderly
shutdown smoke. That run reported an unavailable optional MPRIS2 dependency,
an inactive mpv backend, and one GTK widget assertion; it is not yet a clean
GTK3 acceptance result.

`t/01_ModFileMetadata.t` remains outside the offline target because it downloads
media samples at runtime and the repository contains none of those samples.
M0 remains open until redistributable local fixtures replace that download.
Do not run it in an offline or network-restricted job and do not interpret its
exclusion as a pass.

Real frontend comparisons must use the same fixture library, configuration,
layout, action sequence, theme, scale, and window size. Record the backend,
skips, screenshots, interaction results, timings, and memory measurements with
the test artifacts.
