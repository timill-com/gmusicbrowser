# gmusicbrowser modernization

Status: planning

Target: GTK4, Wayland, modern Linux audio, remote libraries, and first-class
desktop integration

Initial desktop support targets: stock GNOME, Ubuntu's GNOME session, and KDE
Plasma. Standards-based behaviour on other desktops is welcome but is not an
initial release gate.

Primary constraint: preserve the interface and workflows that make gmusicbrowser unique

This is the entry point for the modernization project. The work is an incremental
port of the existing application, not a product redesign and not an immediate
language rewrite.

Detailed planning documents:

- [Progress](docs/modernization/PROGRESS.md) — measured GTK4 port coverage,
  what is implemented, the current bottleneck, and test position. Start here
  for "where are we".
- [Roadmap](docs/modernization/ROADMAP.md) — milestones, ordering, estimates,
  and release gates.
- [Technical plan](docs/modernization/TECHNICAL_PLAN.md) — current and target
  architecture, GTK replacement strategy, audio, KDE, testing, and packaging.
- [Migration inventory](docs/modernization/INVENTORY.md) — source-by-source
  ownership, risk, intended treatment, and tracking status.
- [Parity checklist](docs/modernization/PARITY_CHECKLIST.md) — GTK4 status for
  legacy layouts, commands, preferences, interactions, plugins, and services.
- [Modernization tests](docs/modernization/TESTING.md) — offline contract tests,
  isolated Wayland smoke tests, and current dependency gates.
- [Wave ownership](docs/modernization/WAVE_OWNERSHIP.md) — exclusive file
  ownership, interface freezes, integration, and review state.
- [Remote files](docs/modernization/REMOTE_FILES.md) — URI-based libraries,
  GIO/GVfs/KIO interoperability, desktop-provided access, caching, and safe
  remote mutations.
- [Decisions](docs/modernization/DECISIONS.md) — accepted constraints and open
  architectural decisions.

## Vision

Keep gmusicbrowser's large-library performance, layouts, SongTree, filters,
weighted random modes, tagging, and keyboard/mouse workflows alive on current
Linux desktops, whether music is stored locally or in a remote location exposed
by the desktop file browser. Modernization is successful when an existing user
can install the new version, open the same library and configuration, and
recognize the same application.

The compatibility target is 1:1 wherever the modern platform permits it:
existing data, layouts, commands, shortcuts, mouse behaviour, filters, queue
semantics, tagging workflows, and information density come forward unchanged.
Modernization replaces obsolete infrastructure underneath the application; it
is not an opportunity to simplify away established behaviour.

## Project principles

1. Preserve behaviour before changing implementation.
2. Treat layout files and saved configuration as compatibility APIs.
3. Separate application behaviour from toolkit code before replacing the
   toolkit underneath it.
4. Keep a working GTK3 application while GTK4 reaches feature parity.
5. Port one vertical slice at a time; avoid a flag-day conversion.
6. Prefer freedesktop standards over desktop-specific dependencies.
7. Make Wayland the primary windowing target while retaining X11 support where
   GTK provides it.
8. Do not redesign the interface during the compatibility port. Visual changes
   require a separate proposal after parity.
9. Treat a file as a URI-addressed resource. A POSIX path is one possible local
   representation, not the application-wide identity.
10. Never turn source unavailability into destructive library reconciliation.
    Offline is a source state, not evidence that every song was deleted.

## Non-negotiable data-safety invariants

- Starting while a disk, NAS, portal grant, or remote source is unavailable
  preserves every song and all associated ratings, labels, history, artwork,
  queue entries, and saved-list membership.
- Losing a source before or during a scan invalidates that scan generation. It
  cannot mark songs missing and cannot commit removals.
- An empty directory at a former mountpoint is not proof that the remote source
  is empty. The source/mount identity must match the registered source before
  reconciliation is allowed.
- A completed scan may mark individually absent files as missing, but scanning
  never hard-deletes their library records. Permanent purge is an explicit user
  action with a reviewable count.
- An unexpectedly large disappearance is quarantined as a source problem even
  after an apparently successful scan. It requires a later confirming scan or
  explicit user review.
- Failed playback changes availability/error state; it never removes the song
  from the library or queue.
- Configuration and database migrations create recoverable backups and are
  idempotent.

## What must be preserved

- Existing `.layout` syntax and bundled layouts.
- User-created layouts wherever GTK4 can represent the same behaviour.
- Existing library and tag data without lossy migration.
- SongList and SongTree grouping, columns, selection, sorting, and actions.
- Queue behaviour, locks, filters, saved lists, and weighted random modes.
- ReplayGain, gapless playback, seeking, equalizer support, and useful playback
  backend options.
- Keyboard shortcuts, mouse actions, context menus, and drag-and-drop.
- The camel tray identity and advanced tray interactions: wheel-controlled
  volume plus a compact current-song view with seeking and rating, using the
  closest host-supported interaction on each desktop.
- Usable performance with collections of at least 100,000 songs.
- Correct behaviour when a removable disk or remote music source is offline;
  temporary source loss must never be interpreted as permission to delete
  library entries.
- One-to-one compatibility with established workflows unless an exception is
  documented, tested, and accepted in the decision log.

When exact compatibility is impossible, the change must be documented, tested,
and approved in [DECISIONS.md](docs/modernization/DECISIONS.md).

## Scope

The modernization includes:

- A GTK4 frontend and modern GTK application lifecycle.
- Replacement of removed/deprecated GTK data-view, input, menu, drawing,
  dialog, and drag-and-drop APIs.
- Removal of direct X11 assumptions from normal application paths.
- A maintained GStreamer 1.x playback backend with PipeWire-friendly defaults.
- First-class local and remote library sources selected through the desktop,
  including SMB, SFTP, FTP/FTPS, AFP where available, and other URI schemes
  provided by the installed desktop storage backend.
- MPRIS2, StatusNotifierItem where hosted, notifications, portals, and correct
  desktop metadata for KDE Plasma, stock GNOME, and Ubuntu's GNOME session.
- Reproducible packaging of Perl and introspection dependencies.
- Automated core, integration, GUI, compatibility, and performance tests.

## Explicit non-goals for the compatibility release

- Rewriting the whole application in Rust, Python, C++, or another language.
- Replacing the layout system with a fixed interface.
- Converting the application into a Qt/Kirigami application.
- Redesigning SongTree, navigation, preferences, or tagging workflows.
- Adding streaming-service accounts or unrelated new features.
- Embedding separate SMB, SSH, FTP, or AFP protocol stacks when the desktop
  storage layer already provides them.
- Supporting GTK5 before the GTK4 release is stable.

## Current baseline

The September 2026 source inventory found:

- About 37,600 lines in the principal application, layout, list, song, tag,
  playback, and plugin modules.
- 1,444 `Gtk3::` references across 27 Perl source files.
- 84 classes that directly subclass GTK3 types.
- 126 legacy input, drag, or drawing signal sites.
- 168 references to the TreeView/ListStore/TreeStore/CellRenderer/ComboBox
  family.
- 13 bundled layout files containing more than 1,000 layout declarations.
- One automated test file. It requires network downloads and is not currently
  a reliable offline baseline.

The concentration of risk is in `gmusicbrowser.pl`,
`gmusicbrowser_layout.pm`, `gmusicbrowser_list.pm`, and
`gmusicbrowser_tags.pm`. The GStreamer and desktop-integration work is much
smaller and can progress independently after application boundaries are clear.
Remote storage is cross-cutting: it affects song identity, scanning, missing
file detection, metadata, artwork, playback, tagging, external commands, and
configuration, so it has a dedicated milestone and design document.

## Completion definition

The first stable GTK4 release requires all of the following:

- Supported existing configuration opens without data loss.
- The default layouts and agreed compatibility layout set pass visual and
  behavioural tests.
- Library, queue, filtering, random selection, playback, and tagging acceptance
  suites pass.
- Supported remote sources can be selected through the desktop, scanned,
  played, disconnected, reconnected, and rescanned without blocking the UI or
  losing library data.
- Power-off-before-startup, disconnect-during-scan, empty-mountpoint, revoked
  access, and unexpected mass-disappearance regression tests demonstrate that
  no library record is deleted.
- Remote access is established by the desktop file browser, portal, or mount
  service. Gmusicbrowser has no authentication UI or credential store and
  rejects credential-bearing canonical URIs.
- Remote tag writes and renames are transactional where the backend provides
  the required guarantees, and are clearly disabled otherwise.
- Performance targets pass with the reference 100,000-song library.
- PipeWire, PulseAudio compatibility, Bluetooth device changes, suspend/resume,
  and playback error recovery have been exercised.
- Plasma discovers the application through MPRIS, groups its windows correctly,
  shows notifications, and can display its StatusNotifierItem when enabled.
- Both Wayland and X11 smoke suites pass.
- Installation does not depend on downloading modules at first launch.
- Upgrade, rollback, and configuration backup procedures are documented.

The roadmap deliberately ends with a period in which GTK3 remains available as
a fallback. It is removed only after the GTK4 release has survived real-world
library and layout testing.
