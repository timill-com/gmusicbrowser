# Modernization roadmap

Status: proposed

Estimate confidence: low until milestone M1 is complete

The estimates below are person-weeks for an experienced contributor working
primarily on this project. They are planning ranges, not deadlines. Several
workstreams can overlap once the interfaces introduced in M2 are stable.

## Milestones

| Milestone | Outcome | Estimate |
|---|---|---:|
| M0 | Reproducible GTK3 baseline | 3–5 weeks |
| M1 | GTK4/Perl feasibility proven | 2–3 weeks |
| M2 | Core and frontend boundaries established | 5–9 weeks |
| M3 | GTK3 code prepared for GTK4 concepts | 6–10 weeks |
| M4 | GTK4 application shell and simple layouts | 8–14 weeks |
| M5 | Signature library views reach parity | 12–20 weeks |
| M6 | Remote libraries and URI-based storage | 14–22 weeks |
| M7 | Audio and desktop integration complete | 4–8 weeks |
| M8 | Compatibility, packaging, and stable release | 8–12 weeks |

Expected total: roughly 14–24 person-months. Remote read-only support can land
earlier than remote mutation and cache hardening. Calendar time will be longer
for a part-time or mostly single-maintainer effort.

## M0 — Reproducible GTK3 baseline

Goal: make existing behaviour measurable before structural changes begin.

Work:

- Define a small fixture library and generated 10k/100k-song performance
  libraries.
- Store legally redistributable metadata and media fixtures locally.
- Make the existing test suite run without network access.
- Add core tests for filters, nested conditions, sorting, locks, queues, saved
  lists, weighted random modes, and configuration parsing.
- Add playback contract tests using a fake backend.
- Add a fake URI storage backend covering high latency, access denial,
  disconnects, partial scans, and stale metadata.
- Add regression fixtures for startup with an absent NAS, disconnect during
  enumeration, a bare empty mountpoint, permission denial, and an apparently
  successful scan that reports an unexpected mass disappearance.
- Add layout parser tests for all bundled layouts.
- Capture reference screenshots and interaction recordings for the default,
  browser, queue, search, fullscreen, popup, and desktop layouts.
- Record startup, library-load, filtering, scrolling, and memory baselines.
- Document a repeatable GTK3 smoke-test procedure on Wayland and X11.

Exit gate:

- Tests run offline with one documented command.
- The reference library and configuration are deterministic.
- Every critical user workflow has either an automated test or an explicit
  manual test case.
- Every source-unavailability fixture preserves song count and all user-owned
  metadata, queues, history, and saved-list references.
- Performance results are stored in a comparable format.

## M1 — GTK4/Perl feasibility spike

Goal: eliminate binding and packaging uncertainty before committing to the full
port.

The spike may be throwaway code. It must demonstrate:

- Loading GTK4 through a maintained or locally packaged Perl binding.
- `GtkApplication` activation and a correctly identified Wayland window.
- A 100,000-row `GListModel` displayed through `GtkListView` or
  `GtkColumnView` with usable selection and scrolling.
- A custom GTK4 widget or drawing area using snapshot/draw-function APIs.
- Click, motion, scroll, keyboard, context-menu, and drag-and-drop controllers.
- A simple parsed gmusicbrowser layout rendered by a GTK4 renderer.
- GStreamer bus integration with the GLib event loop.
- Asynchronously enumerate a test GIO remote root and play one URI directly or
  through a local staging lease without freezing the GTK main loop.
- A reproducible package containing the Perl binding and required typelib
  dependencies.

Exit gate:

- No known binding limitation prevents SongTree, custom models, or custom
  widgets from being implemented.
- The list prototype meets an initial scrolling and memory budget.
- At least one packaging route works without modifying the host Perl install.
- Decision D006 in `DECISIONS.md` is resolved.

If the gate fails, pause the port and compare repairing the Perl binding with a
separate GTK4 frontend process. Do not begin a whole-application rewrite by
default.

## M2 — Establish application boundaries

Goal: keep toolkit replacement from changing library and playback behaviour.

Work:

- Define frontend-neutral commands and state events.
- Define a playback interface covering open, play, pause, resume, stop, seek,
  volume, mute, position, duration, end-of-stream, and errors.
- Define storage interfaces for URI identity, asynchronous enumeration, file
  attributes, read streams, local staging leases, monitoring, and mutations.
- Replace `path + filename` as the authoritative song location with a source
  and canonical URI/relative-location model; retain legacy fields as computed
  compatibility values for local files.
- Move GTK-free song/library logic behind a documented API.
- Separate layout parsing from GTK widget construction.
- Introduce a stable widget registry keyed by existing layout element names.
- Isolate configuration reads, migrations, and writes.
- Isolate desktop services: MPRIS, notifications, tray, portals, and session
  integration.
- Add dependency rules preventing core modules from importing GTK.

Exit gate:

- Core acceptance tests run without initializing a display server.
- Local-path and remote-URI resources pass the same storage contract where
  their declared capabilities overlap.
- A fake frontend can execute the critical command/state workflow.
- A fake playback backend can run queue and end-of-stream tests.
- Layout parsing returns a toolkit-neutral representation.

## M3 — Prepare on GTK3

Goal: adopt concepts shared with GTK4 while the shipping frontend still works.

Work:

- Introduce `GtkApplication`, `GAction`, and `GMenuModel` application structure.
- Replace legacy widget event signals with event controllers and gestures where
  GTK3 supports them.
- Replace legacy drag-and-drop setup behind a frontend adapter.
- Remove direct uses of global pointer and root-window coordinates.
- Isolate `GdkWindow`, XID, Wnck, and X11-only code.
- Replace stock items and stock icons with named project/symbolic icons.
- Replace generic container traversal with explicit ownership APIs.
- Centralize dialogs, file selection, URI opening, and transient-window rules.
- Stop stripping or rejecting non-`file://` URIs at file chooser, command-line,
  drag-and-drop, scan, and playlist boundaries.
- Add warnings or validation for layout constructs that cannot map exactly to
  GTK4.

Exit gate:

- The GTK3 acceptance suite remains green.
- Normal operation on Wayland does not require an XID.
- Application commands are exposed as actions rather than menu-widget
  callbacks.
- All remaining GTK3-only APIs are listed in the technical inventory.

## M4 — GTK4 shell and layout renderer

Goal: run a useful GTK4 application before porting every complex view.

Work:

- Add the GTK4 application entry point and lifecycle.
- Implement GTK4 layout containers and the stable widget registry.
- Port labels, images, buttons, playback controls, text widgets, progress/volume
  controls, panes, tabs, scrollers, and basic windows.
- Port CSS, fonts, colors, scaling, icons, and simple custom drawing.
- Port action-based menus and popovers.
- Port asynchronous file, font, color, alert, and URI dialogs.
- Use native/portal file selection so desktop-provided remote locations and
  persistent document access can enter the source registry.
- Implement preferences sufficient to select layouts and playback settings.
- Render the simple/default compatibility layout set.

Exit gate:

- The application starts, loads a library, renders a main layout, and controls
  playback on GTK4.
- Configuration is read without rewriting or losing unknown values.
- Basic layouts pass agreed screenshot and interaction comparisons.
- Wayland and X11 smoke tests pass.

## M5 — Signature views and full layout compatibility

Goal: preserve the interface features that distinguish gmusicbrowser.

Suggested order:

1. Simple lists used by preferences and dialogs.
2. Filter lists and filter panes.
3. SongList with columns, selection, search, sorting, editing, and DnD.
4. SongTree grouping and custom rendering.
5. Mosaic, cloud, album/artist, and filesystem views.
6. Picture browser and fullscreen drawing paths.
7. Mass tagging and remaining editor views.

Work for every view:

- Define its model independent of its GTK view.
- Port input, selection, accessibility, focus, tooltips, menus, and DnD.
- Preserve layout options and saved column/group definitions.
- Add screenshot and behavioural comparisons.
- Benchmark large datasets before moving to the next view.

Exit gate:

- The compatibility layout set and all critical views pass tests.
- SongList and SongTree meet performance targets at 100,000 songs.
- Keyboard-only operation and screen-reader roles have been checked.
- Any unsupported legacy layout feature has an approved decision and migration
  message.

## M6 — Remote libraries and URI-based storage

Goal: let users add and use locations exposed by their operating-system file
browser without manually mounting them as conventional Unix paths.

Detailed design and capability requirements are in `REMOTE_FILES.md`.

Foundation work:

- Introduce a source registry with stable source IDs, root URIs, display names,
  capability flags, availability/access state, cache policy, and scan history.
- Represent songs by source plus canonical relative location/URI; never include
  passwords in stored URIs.
- Implement a local `GFile` adapter and an asynchronous GIO adapter.
- Accept desktop-portal document paths and KIOFuse projections as native
  resources while preserving source identity where available.
- Detect supported URI schemes at runtime rather than promising protocols whose
  backend is not installed.

Read/index work:

- Enumerate remote directories asynchronously in bounded batches.
- Query only the attributes required for discovery and change detection.
- Refactor metadata readers toward seekable streams; use managed local staging
  when a format parser or backend needs a POSIX filename.
- Keep metadata and artwork indexes available while a source is offline.
- Commit scan reconciliation only after a root completes successfully; an
  interrupted or offline scan cannot mark unseen tracks deleted.
- Verify the registered source/mount identity before reconciliation so a bare
  local mountpoint is not mistaken for an empty NAS.
- Treat a large unexpected disappearance as a degraded/offline source and
  quarantine the diff pending a confirming scan or user review.
- Make scan removal non-destructive: individually absent files may become
  `missing`, but purging their records is a separate explicit action.
- Fall back from file monitoring to explicit or scheduled rescans where remote
  monitoring is unavailable.

Playback/cache work:

- Pass supported canonical URIs to GStreamer and use its URI buffering.
- Fall back to a cancellable local staging lease when direct playback is not
  supported or sufficiently seekable.
- Add bounded, configurable LRU caches for artwork, metadata staging, and
  optional audio; do not download an entire remote library by default.
- Expose useful states such as connecting, access required, buffering, offline,
  cached, and retrying. "Access required" sends the user back to the desktop
  file browser; it does not open a gmusicbrowser login prompt.

Mutation work:

- Query backend capabilities before enabling tagging, rename, move, delete, or
  artwork writes.
- For remote tag edits, stage locally, validate the result, upload to a sibling
  temporary object, and replace only if the original version/etag still
  matches. Disable writing where safe replacement is unavailable.
- Use GIO async copy/move/replace operations and report conflicts explicitly.
- Provide local staging leases to legacy external commands, with defined
  lifetime and upload behaviour; never silently pass a remote URI where a
  command expects a filename.

Protocol acceptance tiers:

- Tier 1: desktop-projected local paths, portal document paths, CIFS/NFS mounts,
  and KIOFuse paths.
- Tier 2: GIO/GVfs SMB, SFTP, FTP/FTPS, AFP, DAV/DAVS, and other installed
  enumerable backends.
- Tier 3: playback-only URIs such as ordinary HTTP streams, which are not
  necessarily enumerable library roots.

Exit gate:

- Local-path behaviour remains compatible after the URI data migration.
- SMB and SFTP pass add, scan, play, disconnect, reconnect, rescan, and change
  reconciliation tests.
- At least one read-only and one safely writable remote backend pass their
  declared capability suites.
- A source becoming unreachable never removes its songs or blocks normal local
  library use.
- Starting with an offline source, losing it mid-scan, exposing an empty
  mountpoint, and receiving a suspicious empty/partial listing all preserve the
  previous committed scan generation and complete song metadata.
- No automatic scan path hard-deletes library records; explicit purge presents
  the affected source and count before confirmation.
- No synchronous remote I/O runs on the GTK main thread.
- Gmusicbrowser contains no network authentication flow or credential storage.
  Tests receive locations that the desktop has already made accessible;
  credential-bearing URIs are rejected from configuration and exports.
- Cache size, eviction, cancellation, and cleanup tests pass.

## M7 — Audio and Linux desktop integration

Goal: make the GTK4 build a well-behaved modern Linux media application.

Audio work:

- Keep GStreamer 1.x as the primary backend.
- Make system-default output the recommended selection.
- Support native PipeWire output when available, PulseAudio compatibility, and
  ALSA fallback without making gmusicbrowser a device-policy manager.
- Remove obsolete output choices from the normal preferences UI.
- Test gapless playback, ReplayGain, equalizer, seek, suspend/resume, Bluetooth
  profile/device changes, output loss, and error recovery.
- Retain mpv as an optional fallback until a separate decision removes it.

Desktop work:

- Make MPRIS2 a maintained, default service and add compliance tests.
- Implement StatusNotifierItem over D-Bus; do not depend on `GtkStatusIcon`.
- Preserve the camel icon and map the StatusNotifierItem `Scroll` method to the
  existing configurable volume-step command, including high-resolution wheel
  delta accumulation and volume clamping.
- Preserve the current tray layout as a compact-player model containing cover,
  title/artist/album, playback controls, seek position, and editable rating.
- Provide a standard rich tooltip and click-activated GTK4 compact player on
  StatusNotifier hosts. Prototype an optional Plasma system-tray widget for
  the original interactive hover experience, because a standard notifier
  tooltip and DBusMenu cannot host interactive controls.
- Make the Plasma companion a direct System Tray plasmoid activated by the
  exact gmusicbrowser MPRIS bus name. Add a presence handshake so it replaces,
  rather than duplicates, the generic camel notifier.
- On stock GNOME, test the MPRIS/notification and GTK4 compact-player baseline
  without requiring a tray host. On Ubuntu's GNOME session, additionally test
  the generic notifier when the distribution-provided
  AppIndicator/KStatusNotifier host is present. Do not build or require a
  gmusicbrowser GNOME Shell extension.
- Use standard desktop notifications.
- Use desktop portals for file selection, URI opening, and other appropriate
  cross-desktop services.
- Align application ID, desktop filename, D-Bus identity, icon, and Wayland app
  ID after providing an upgrade strategy.
- Test Plasma media controls, task grouping, KDE Connect control, notification
  actions, tray behaviour, Breeze, dark mode, fractional scaling, and global
  shortcuts.

Exit gate:

- The audio, Plasma, stock GNOME, and Ubuntu GNOME acceptance matrices pass.
- MPRIS reports correct playback state, metadata, position, volume, and
  capabilities.
- On Plasma, scrolling over the camel notifier changes only gmusicbrowser's
  volume by the configured step; horizontal and high-resolution input are
  tested.
- Seeking and rating are available from the compact tray experience. The
  acceptance matrix records whether each host provides the standard activated
  popup or the richer Plasma hover companion.
- Installing the Plasma companion produces one camel entry directly in System
  Tray, which appears and disappears with gmusicbrowser and falls back to the
  generic notifier if the companion fails.
- Stock GNOME remains fully controllable through MPRIS and the GTK4 compact
  player without requiring a Shell extension.
- Ubuntu uses its distribution-provided notifier host when available, without
  making that host a gmusicbrowser dependency.
- No required desktop feature depends on XEmbed or an X11 global coordinate.

## M8 — Beta and stable release

Goal: ship safely without forcing early adopters to risk their library or
configuration.

Work:

- Provide upgrade-time configuration backup and schema/version handling.
- Run compatibility tests with real user layouts and anonymized large-library
  fixtures.
- Add crash reporting instructions and useful structured diagnostics.
- Build reproducible Flatpak and selected native distribution packages.
- Document installation, migration, known differences, rollback, and bug-report
  requirements.
- Run an opt-in beta period while GTK3 remains available.
- Resolve severity-one and severity-two compatibility defects.

Stable release gate:

- No known data-loss defect.
- No critical workflow regression without an accepted exception.
- Supported packages pass clean-install and upgrade tests.
- Performance is within the approved budget.
- The rollback procedure has been tested.

## Workstream dependencies

- M0 and M1 should begin first and may run in parallel.
- M2 must stabilize before multiple contributors port widgets independently.
- M3 reduces M4/M5 risk and should not be skipped to create a quick demo.
- The storage interface and URI identity portion of M2 must land before remote
  scanning or before GTK4 file selection starts persisting library sources.
- M6 can overlap M4/M5 after that interface stabilizes, but remote metadata
  editing depends on tag-operation separation from M2/M5.
- Audio internals can begin after the playback contract in M2.
- MPRIS and StatusNotifier work can begin after the command/state service
  boundary in M2.
- Packaging must be exercised in M1 and maintained continuously, not postponed
  until M8. Remote acceptance must run both outside and inside the selected
  sandbox/package format.

## Issue structure

Each implementation issue should identify:

- Milestone and workstream.
- Existing behaviour being preserved.
- Source modules and layout elements affected.
- GTK3 and GTK4 API involved.
- Automated and manual acceptance criteria.
- Wayland/X11 and desktop-specific impact.
- Local-path, remote-URI, offline, and sandbox impact where applicable.
- Performance or configuration-compatibility risk.
- Whether an entry in `DECISIONS.md` is required.
