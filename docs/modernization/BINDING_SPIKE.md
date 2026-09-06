# GTK4 Perl binding spike

Status: in progress

This spike tests direct GTK4 use through `Glib::Object::Introspection`. It is
isolated from the GTK3 frontend and does not establish GTK4 behavioural parity.
Decision D006 remains open until every required binding behaviour and a
reproducible package have passed.

`gmusicbrowser_gtk4.pl` is the separate GTK4 entry point required while
`gmusicbrowser.pl` still imports Gtk3. Its hard-coded proof state is temporary;
new behaviour belongs in shared core contracts and frontend adapters, not in a
second independent application model.

## Binding initializer

`gmusicbrowser_gtk4_binding.pm` initializes these introspection namespaces:

| Namespace | Version | Perl package |
|---|---:|---|
| Gio | 2.0 | `Gio` |
| Gtk | 4.0 | `Gtk4` |
| Gdk | 4.0 | `Gtk4::Gdk` |
| Gsk | 4.0 | `Gtk4::Gsk` |

The module has no GTK3 import. `try_init` reports a stable dependency failure,
`version_probe` reports the loaded Perl, GLib, introspection, and GTK versions,
and `backend_probe` reports the requested and opened display backend. No
minimum-version decision is inferred here; that remains D008.

On Ubuntu 24.04, the minimum distribution packages for this direct
introspection experiment are:

```sh
sudo apt install gir1.2-gtk-4.0 libglib-perl \
  libglib-object-introspection-perl
```

`libgtk-4-dev` is needed only if a later binding override adds compiled code;
the direct introspection initializer does not require GTK headers.

The repository does not yet pin or package an upstream Perl GTK4 distribution.
The direct initializer is evidence for D006 option 2, not resolution of D006.

## Running the probe

The dependency test is deterministic and offline:

```sh
prove --norc -I. t/gtk4/00_Binding.t
```

When a prerequisite is absent the complete file is skipped with a reason that
names the missing Perl modules or introspection namespaces. A skipped test is
not a successful binding proof.

The Wayland check must use an existing real Wayland connection:

```sh
sh tools/run-gtk4-smoke
```

The runner exits with status 77 when no Wayland socket or binding prerequisite
is available. It creates temporary config, data, cache, state, and runtime
directories, exposes only the existing Wayland socket in the temporary runtime
directory, forces `GDK_BACKEND=wayland`, avoids the user session bus and Perl
environment overrides, and removes the temporary tree on exit. It does not use
the gmusicbrowser user profile. The proof does not currently require a session
bus.

## Local evidence

On 2026-09-06 the binding and proof tests passed on a real Wayland connection
using privately extracted Ubuntu archives and an isolated session bus. GTK
4.14.5 loaded with Gio, Gdk, and Gsk; `Gtk4::Application` inherited
`Gio::Application::run`; the display backend was Wayland; and the GTK4 entry
point did not load Gtk3. The binding and proof-of-life files completed 22
assertions.

This run proves the checkpoint on the development host. The extracted archives
are not a pinned or reproducible project package, so D006 and the full M1 gate
remain open.

## Probe inventory

| Required evidence | Automated status | Remaining work |
|---|---|---|
| Load Gio/Gtk/Gdk/Gsk | Passed locally | Pin and package the selected binding set |
| Dependency and version reporting | Passed locally | Use results when resolving D008 |
| Wayland backend identification | Passed locally | Repeat from the reproducible package |
| `GtkApplication` activation | Passed locally | Repeat from the reproducible package |
| 100,000-row `GListModel` and ListView/ColumnView | Blocked | Add selection, recycling, scrolling, time, and memory measurements |
| Custom widget or drawing area | Blocked | Add draw-function and snapshot/subclass probes |
| Click, motion, scroll, keyboard, and context-menu controllers | Blocked | Add input and focus assertions |
| Drag-and-drop | Blocked | Add drag source, drop target, and payload assertions |
| Async finish calls and error propagation | Blocked | Add success, cancellation, and failure cases |
| GLib/GStreamer loop coexistence | Blocked | Add a deterministic test pipeline and bus assertions |
| Parsed gmusicbrowser layout | Passed locally | Extend beyond the proof layout |
| Async GIO enumeration and URI playback | Blocked | Use an offline fixture and deterministic GStreamer sink |
| Reproducible package | Blocked | Pin the binding source and build the selected package format |

The M1 exit gate has not passed. In particular, this slice supplies no evidence
for list performance, widget subclassing, factory recycling, asynchronous API
marshalling, GStreamer integration, or packaging.
