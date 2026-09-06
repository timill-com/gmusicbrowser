# Modernization technical plan

This document describes how to reach GTK4 without losing gmusicbrowser's
application model or layout system. It is subordinate to the preservation
contract in the repository-level `MODERNIZATION.md`.

## Current architecture

The current application is modular by file, but toolkit, application state, and
business logic frequently cross module boundaries through globals and package
methods.

| Area | Principal source | Notes |
|---|---|---|
| Application lifecycle, state, commands, preferences | `gmusicbrowser.pl` | GTK initialization and application logic share one module |
| Songs, fields, filters, arrays, random modes | `gmusicbrowser_songs.pm` | Mostly reusable logic; includes GTK list/combo implementations |
| File identity, scanning, missing-file detection | `gmusicbrowser.pl`, `gmusicbrowser_songs.pm`, `gmusicbrowser_list.pm` | Assumes POSIX paths and synchronous `opendir`/`stat`-style operations |
| Layout parser, windows, controls, skins | `gmusicbrowser_layout.pm` | Central compatibility surface for user layouts |
| SongList, SongTree, filters, mosaic, cloud | `gmusicbrowser_list.pm` | Highest GTK4 migration risk and large-library performance risk |
| Tags and tag editors | `gmusicbrowser_tags.pm` | Metadata operations and substantial GTK editor code coexist |
| GStreamer playback | `gmusicbrowser_gstreamer-1.x.pm` | Correct modern foundation, with old sink choices and compatibility workarounds |
| Other playback | `gmusicbrowser_mpv.pm`, `gmusicbrowser_mplayer.pm`, `gmusicbrowser_123.pm` | Keep mpv during transition; review obsolete backends later |
| D-Bus and MPRIS | `gmusicbrowser_dbus.pm`, `plugins/mpris2.pm` | Useful implementation built on old Net::DBus integration |
| Tray | core `GtkStatusIcon`, `plugins/appindicator.pm` | Must become StatusNotifierItem for GTK4/Wayland |
| Notifications | `plugins/notify.pm` | Already based on the desktop notification service |

## Target boundaries

The target is one process unless the GTK4 binding feasibility spike proves that
impractical.

```text
GMB::Core
  Library, Song, Filter, Queue, Random, Configuration, Commands, Events
      |
      +-- GMB::Storage contract
      |      +-- local/GIO resources
      |      +-- desktop portal grants
      |      +-- local staging and bounded caches
      |
      +-- GMB::Playback contract
      |      +-- GStreamer 1.x
      |      +-- mpv (optional transition backend)
      |
      +-- GMB::Layout model
      |      +-- parser and validation
      |      +-- stable layout/widget identifiers
      |
      +-- GMB::Desktop services
      |      +-- MPRIS2
      |      +-- notifications
      |      +-- StatusNotifierItem
      |      +-- portals/session integration
      |
      +-- GMB::UI::GTK3 (shipping transition frontend)
      +-- GMB::UI::GTK4 (new frontend)
```

The namespaces are illustrative. Moving code should be driven by tested
boundaries rather than a mechanical rename.

### Core rules

- Core modules must not import `Gtk3`, `Gtk4`, GDK, or Wnck.
- Core state changes emit named events with documented payloads.
- Commands operate on application state without requiring a widget reference.
- Frontends translate toolkit input into commands and state events into views.
- Playback backends do not call widget functions directly.
- Core song identity uses storage resources/URIs, never an assumed native path.
- Remote storage calls are asynchronous, cancellable, capability-checked, and
  cannot run on the GTK main thread.
- Desktop services consume the same state/command API as the GUI.
- Configuration preserves unknown keys so a GTK4 test run does not destroy
  settings needed by GTK3 rollback.
- Scan results are generation-based and non-destructive. Only a complete,
  source-identity-verified generation may change missing state; no scan hard
  deletes a song record.

## Layout compatibility architecture

The layout system is a core feature, not an implementation detail.

### Parse once, render by frontend

The parser should return a neutral tree containing:

- Layout ID, type, name, and metadata.
- Containers and ordered children.
- Packing/alignment constraints.
- Stable widget identifiers.
- Typed and unrecognized widget options.
- References to SongTree column/group definitions and skins.
- Source file and line information for diagnostics.

The renderer maps that tree through a widget registry. Registry entries expose:

- Constructor for a frontend implementation.
- Supported options and defaults.
- Child/container rules.
- Commands produced by user input.
- State events consumed.
- Compatibility warnings and fallback behaviour.

### Compatibility policy

- Existing identifiers retain their meaning.
- Unknown options are preserved and reported, not silently deleted.
- A layout failing validation must produce a useful source-located error.
- GTK4 implementation details must not appear in `.layout` syntax during the
  compatibility release.
- New layout capabilities require explicit versioning or feature detection.
- Golden tests cover parse output separately from rendered screenshots.

## GTK3 to GTK4 replacement map

| Existing pattern | GTK4 direction | Migration note |
|---|---|---|
| `Gtk3::Window` created ad hoc | `GtkApplication` and application windows | Establish identity, activation, and lifecycle first |
| `Gtk3::VBox` / `HBox` and `pack_*` | `GtkBox`, orientation, append/prepend, layout properties | Implement in layout renderer |
| `GtkContainer`, `GtkBin`, generic `add/get_children` | Explicit single-child or collection APIs | Remove generic container subclass assumptions |
| Widget event signals and event masks | Event controllers and gestures | Port on GTK3 where possible |
| `GtkEventBox` | Controllers on the actual widget or a simple wrapper | Preserve hit target and accessibility |
| `draw` signal and style render calls | `GtkDrawingArea::set_draw_func` or widget snapshot | Prefer child widgets for themed controls |
| Direct `GdkWindow`, root coordinates, XID | `GdkSurface`, `GtkNative`, relative coordinates | Required for Wayland |
| `GtkMenu`, `GtkMenuItem`, `GtkMenuBar` | `GMenuModel`, `GAction`, `GtkPopoverMenu` | Separate action from presentation |
| `GtkToolbar` and tool items | Normal boxes/buttons/actions | Preserve layout appearance through CSS |
| `GtkStatusIcon` / AppIndicator GTK menus | D-Bus StatusNotifierItem and DBusMenu where required | Toolkit-independent service |
| Legacy drag signals and target entries | `GtkDragSource` and `GtkDropTarget` | Define application payload types explicitly |
| Synchronous dialogs and `run` | Asynchronous GTK4 dialog APIs | Centralize continuation/error handling |
| `GtkTreeView`, tree models, cell renderers | `GListModel`, selection models, ListView/ColumnView/TreeListModel | Required for long-term support |
| `GtkComboBox` backed by tree models | `GtkDropDown` or purpose-built chooser | Searchable large choosers may need custom popovers |
| Stock icons and stock IDs | Freedesktop/project symbolic icon names | Map legacy layout icon names centrally |

GTK4's TreeView family may be used only as a documented temporary bridge. It is
deprecated in GTK 4.10 and planned for removal in GTK5, so it cannot be the
final implementation of primary library views.

References:

- <https://docs.gtk.org/gtk4/migrating-3to4.html>
- <https://docs.gtk.org/gtk4/migrating-4to5.html>
- <https://docs.gtk.org/gtk4/section-list-widget.html>

## List and SongTree strategy

### Application models

Do not make every song a large copied hash owned by GTK. The view-model layer
should expose stable lightweight row objects or IDs backed by the existing song
store. It needs:

- Incremental `items-changed` notifications.
- Lazy field formatting and cover loading.
- Explicit filter and sort adapters.
- Stable identity across reorder/filter operations.
- Selection restoration by song ID, not row number.
- Batched changes during scans and mass edits.
- Cancellation/generation handling for asynchronous searches and artwork.

### SongList

Map configurable columns to `GtkColumnViewColumn` factories. Each factory owns
setup/bind/unbind/teardown behaviour and must avoid accumulating signal handlers
or heavyweight artwork while rows are recycled.

Required parity tests include:

- Column order, width, visibility, sort, and saved settings.
- Multi-selection and current-playing indication.
- Editable fields and validation.
- Keyboard incremental search.
- Context actions and middle-click behaviour.
- Internal reordering and external file/URI drag-and-drop.
- Smooth scrolling and bounded memory at 100,000 songs.

### SongTree

SongTree is a dedicated workstream. A normal TreeListModel may represent its
group hierarchy, but it does not by itself replace the existing custom column,
skin, overlay, and group drawing engine.

The M1 spike must compare two approaches:

1. A `GtkListView`/`GtkColumnView` with factories for group and song rows.
2. A custom virtualized widget using GTK4 snapshot APIs and explicit accessible
   children/selection.

Choose using measured scrolling, memory, layout expressiveness, input parity,
and accessibility. Do not choose solely by how quickly the first screenshot can
be reproduced.

## Drawing, skins, and artwork

- Keep original images and layout skin definitions as source assets.
- Port Cairo drawing that remains appropriate through draw functions.
- Use snapshot/render-node paths only where they materially improve scrolling
  or effects.
- Replace theme-part rendering with real child widgets or CSS classes.
- Make artwork decoding/caching independent of widget lifetime.
- Include scale factor, size, crop mode, and source revision in cache keys.
- Test transparent images, embedded covers, animation, HiDPI, dark themes, and
  missing/broken artwork.

Visual comparison tolerances must account for legitimate GTK3/GTK4 font and
theme differences. Geometry, hierarchy, information density, and interaction
targets are stronger compatibility requirements than identical antialiasing.

## Playback and modern Linux audio

GStreamer 1.x remains the primary engine. `playbin` already provides decoding,
bus events, gapless hooks, seeking, and selectable audio sinks.

Playback receives a canonical URI or a managed local staging lease from the
storage service. It does not convert every song back into a POSIX filename.

### Output policy

- Default: GStreamer's system-selected audio output (`autoaudiosink` or the
  corresponding modern playback default).
- PipeWire: allow explicit `pipewiresink` when present, primarily for advanced
  use and testing.
- PulseAudio: retain `pulsesink`; on PipeWire desktops it normally connects via
  the `pipewire-pulse` compatibility service.
- ALSA: retain as an emergency/direct fallback.
- JACK and other specialist sinks: advanced-only when detected.
- OSS, ESD, aRts, and other obsolete outputs: remove from the normal UI after a
  documented compatibility review.

Gmusicbrowser should not duplicate WirePlumber's device-policy role. Normal
device selection, Bluetooth routing, and hot plugging belong to the desktop
audio session manager. If per-device selection remains a requirement, build it
from GStreamer device discovery rather than parsing server-specific command
output.

### Playback contract

Backends must expose consistent asynchronous state and error events. Contract
tests cover:

- State transitions and invalid operations.
- URI/path encoding.
- Duration/position and seeks near boundaries.
- End-of-stream and gapless handoff.
- Volume and mute round trips.
- ReplayGain and equalizer pipeline construction.
- Sink loss, decode failure, and recovery.
- Shutdown without callbacks into destroyed frontend objects.

Reference: <https://gstreamer.freedesktop.org/documentation/playback/playbin.html>

## Remote libraries and storage resources

Local paths, NAS files, and desktop-provided remote files share a URI-native
storage contract built on GIO `GFile`. This is a core data-model migration, not
a GTK file chooser enhancement.

The design covers:

- Stable source IDs and canonical credential-free URIs.
- Asynchronous enumeration and file attributes.
- Offline source state distinct from a missing song.
- Conservative scan reconciliation after complete, source-identity-verified
  traversals only, with mass-disappearance quarantine and explicit purge.
- Stream-capable metadata readers with safe local staging fallback.
- Direct GStreamer URI playback with managed staging fallback.
- Bounded metadata, artwork, and optional audio caches.
- Consumption of desktop-authorized resources without application-owned
  authentication or mount operations.
- Capability-gated, transactional tag writes and file mutations.
- GIO/GVfs backends plus portal/KIOFuse projected paths on Plasma.

The full product contract, source/song schema, protocol tiers, caching rules,
write algorithm, and acceptance matrix are in
[REMOTE_FILES.md](REMOTE_FILES.md).

Reference: <https://docs.gtk.org/gio/iface.File.html>

## Supported desktop integration

The tested targets are KDE Plasma, stock GNOME, and Ubuntu's GNOME session.
Integration uses freedesktop services, so the same work may benefit other
desktops, but Xfce, Cinnamon, and other environments are best-effort rather
than initial support or release-gate targets.

### MPRIS2

Modernize the existing plugin into a default desktop service:

- Use the canonical bus name and object path.
- Emit correct property changes without fixed-delay coalescing where possible.
- Validate `PlaybackStatus`, `Metadata`, `Position`, `Volume`, loop, shuffle,
  seek, and capability properties.
- Use persistent or safely managed artwork URIs.
- Add MPRIS command and introspection tests.
- Confirm Plasma and KDE Connect discovery.

Reference: <https://specifications.freedesktop.org/mpris/latest/>

### Tray/status item

Replace both `GtkStatusIcon` and the GTK3 AppIndicator dependency with a
toolkit-independent StatusNotifierItem implementation. Preserve the existing
tray command model so GTK3 and GTK4 can share actions during the transition.

The old tray feature is more than an icon and menu. `layouts/tray.layout`
defines compact layouts with cover and song metadata, a `TimeBar`, editable
`Stars`, playback buttons, and a `VolumeScroll` region. The current
`GtkStatusIcon` path opens that layout on hover and maps icon scroll events to
the application volume command. Treat those behaviours as compatibility
requirements.

Use a layered replacement:

1. The cross-desktop StatusNotifierItem publishes the camel icon, current-song
   tooltip, menu, activate/secondary-activate actions, and `Scroll`. Convert
   vertical scroll deltas into the existing configurable volume-step command;
   accumulate smooth/high-resolution deltas and ignore unsupported horizontal
   input unless testing establishes a consistent mapping.
2. `Activate` can open a GTK4 compact-player window backed by the same
   frontend-neutral tray-layout model. It provides seeking and rating where the
   host offers no richer surface. Position is best effort: under Wayland the
   notifier is owned by another process and the application cannot assume
   global icon geometry.
3. For Plasma, prototype a separately packaged system-tray Plasma widget. Mark
   it with `X-Plasma-NotificationArea` and bind its exact
   `X-Plasma-DBusActivationService` to gmusicbrowser's MPRIS bus name so Plasma
   loads and unloads it with the application. Its camel compact representation
   lives directly inside System Tray; its expanded/hover representation
   recreates the interactive compact player. It talks to gmusicbrowser through
   MPRIS for transport, position, and volume plus a small application D-Bus
   action for setting rating. When the companion announces itself, suppress the
   generic StatusNotifierItem so the user never sees two camel icons; restore
   the notifier if the companion disappears. This companion must not introduce
   a Qt/KDE dependency into the main application.
4. On stock GNOME Shell, rely on MPRIS, notifications, and the activated GTK4
   compact player because GNOME does not provide an application system tray.
   Publish the generic StatusNotifierItem anyway so it appears when the user has
   a distribution-provided AppIndicator/KStatusNotifier host, including Ubuntu
   configurations that supply one, but treat wheel forwarding and tooltip
   display as host capabilities rather than guarantees. Do not develop, bundle,
   require, or recommend a gmusicbrowser-specific GNOME Shell extension.

The standard StatusNotifierItem `ToolTip` is descriptive rather than an
application-owned interactive surface, and the host renders DBusMenu itself;
neither can contain the legacy seek and rating widgets. Do not claim exact
hover parity from the standard notifier alone.

Reference:
<https://specifications.freedesktop.org/status-notifier-item/latest/>
<https://develop.kde.org/docs/plasma/widget/properties/#x-plasma-notificationarea-system-tray>

### Portals and notifications

- Use the desktop notification service for track changes and actions.
- Use file chooser and URI-opening portals where appropriate.
- Evaluate the GlobalShortcuts portal instead of desktop-specific multimedia
  key plugins; MPRIS remains the first choice for media keys.
- Ensure parent window identifiers work on both Wayland and X11.

Reference: <https://flatpak.github.io/xdg-desktop-portal/docs/>

### Application identity

GTK4 expects the application ID, desktop filename, D-Bus identity, and Wayland
app ID to agree. Changing the existing identity affects task grouping, MPRIS
metadata, autostart, packaging, and upgrades. Resolve D007 before changing any
installed filename.

## Perl GTK4 binding and packaging

Binding feasibility is a release-engineering risk, not just a developer setup
issue. The project needs:

- A pinned binding source and version.
- Tests for overrides used by models, closures, async finish calls, subclassing,
  boxed values, and signal marshalling.
- A reproducible developer environment.
- A package that bundles non-standard Perl modules rather than writing into the
  user's system Perl.
- A documented minimum GTK/GStreamer/GLib/Perl version matrix.

Flatpak is the leading first distribution candidate because it can bundle Perl
modules and typelibs while using host portals, PipeWire, and desktop services.
Native distribution packages remain desirable and should be built in CI after
the dependency strategy is proven.

Remote-library tests must verify that the package can persist a user-approved
directory grant, receive portal file transfers, reach GIO backends allowed by
the sandbox, and play through host audio without broad filesystem permissions.

## Test architecture

### Core tests

Run without GTK, audio hardware, network, or a user configuration directory.
Cover library operations, metadata, filters, random modes, queue, configuration,
layout parsing, command handling, URI/source identity, offline reconciliation,
and migrations. A fake storage provider supplies deterministic latency,
disconnect, access-denied, and conflict cases.

### Contract tests

Run every playback backend and frontend state adapter against shared expected
behaviour. Use fakes for deterministic error and timing cases.

### GUI tests

- Launch each frontend with isolated temporary XDG directories.
- Exercise widgets through accessibility/input APIs where possible.
- Render reference layouts at fixed font, scale, theme, and window sizes.
- Store failure images and image diffs as CI artifacts.
- Run a smaller smoke set under both Wayland and X11.

### Integration tests

Use private D-Bus sessions and inspect MPRIS, notifications, StatusNotifierItem,
and portal calls. Use a deterministic GStreamer test sink for most CI and real
PipeWire/PulseAudio sessions in scheduled or pre-release testing.

Remote integration jobs provide ephemeral SMB, SFTP, FTP/FTPS, and selected
other servers, connected by the test environment before gmusicbrowser starts.
Scheduled desktop jobs cover GTK/GVfs and Plasma portal/KIOFuse paths,
including disconnects and revoked access.

### Performance tests

Record median and tail values for:

- Startup to interactive window.
- Library load and initial display.
- Filter/search latency.
- Sort/group rebuild time.
- SongList and SongTree scrolling frame time.
- Artwork loading under rapid scrolling.
- Unchanged remote rescan requests/bytes, metadata throughput, and uncached
  playback start time at representative latency.
- Memory after load, scroll, filter, and repeated layout changes.

Budgets should be set from the M0 GTK3 baseline and approved before M5.

## Compatibility and data safety

- Never test migrations against the user's only configuration copy.
- Add explicit configuration schema/version metadata.
- Back up before the first GTK4 write.
- Make migrations idempotent and unit tested.
- Preserve unknown plugin and layout options.
- Avoid writing GTK4-only defaults until a meaningful setting changes.
- Document downgrade behaviour while GTK3 remains supported.
- Preserve remote-source entries and their last complete scan while offline.
- Preserve song records and user metadata when files become missing; physical
  purge is explicit and separately tested.
- Strip credentials from URIs before configuration, logging, playlist export,
  or error reporting.

## Highest risks

| Risk | Mitigation / gate |
|---|---|
| Perl GTK4 bindings cannot support models or subclassing reliably | M1 prototypes the exact difficult operations before the port |
| SongTree loses performance or expressiveness | Dedicated prototype comparison, golden layouts, 100k benchmark |
| Refactor changes library behaviour before GTK4 work | M0 fixtures and M2 headless contracts |
| Layout/config migration damages user customization | Neutral layout model, unknown-value preservation, backup and round-trip tests |
| Wayland breaks popup/fullscreen/tray assumptions | Remove root-coordinate/XID dependencies in M3; use standards and surfaces |
| Port stalls while GTK3 becomes unusable | Maintain releasable GTK3 until GTK4 stable; small reviewable vertical slices |
| Distribution cannot provide Perl dependencies | Exercise bundled packaging in M1 and continuously in CI |
| A UI redesign becomes mixed into the port | Preservation contract and separate decision process |
| NAS disconnect is misread as mass deletion | Source availability state and generation-based reconciliation committed only after a complete scan |
| An unmounted NAS leaves a valid but empty local mountpoint | Persist and verify source/mount identity; quarantine unexpected mass disappearance |
| Remote scanning freezes the UI or overloads a NAS | Async bounded enumeration, cancellation, batching, and configurable concurrency |
| Remote tag write corrupts the only copy | Stage, validate, version-check, upload temporary, and atomically replace; otherwise remain read-only |
| KDE and GTK expose different remote backends | Prefer portal/KIOFuse projection on Plasma; use capability-detected GIO URIs rather than assuming shared sessions |

## Definition of a porting unit

A widget or feature is not considered ported merely because it renders. A
complete porting unit includes:

- Neutral model/state boundary.
- GTK4 rendering and lifecycle.
- Commands, keyboard, pointer, focus, menus, and drag-and-drop.
- Accessibility names, roles, states, and actions.
- Layout options and saved-setting compatibility.
- Local-path and remote-URI behaviour, including offline/cancellation states,
  where the feature touches media resources.
- Automated tests and documented manual cases.
- Wayland and X11 smoke results.
- Large-library measurement where relevant.
- Removal or explicit inventory of the superseded GTK3-only code.
