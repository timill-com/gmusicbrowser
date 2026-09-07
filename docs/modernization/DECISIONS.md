# Modernization decisions

This is a lightweight architecture decision log. Accepted decisions constrain
implementation work; proposed decisions must be resolved before the milestone
listed in their gate.

Statuses:

- **Accepted** — current project direction.
- **Proposed** — preferred direction, awaiting validation or agreement.
- **Open** — alternatives still need evidence.
- **Superseded** — retained for historical context.

## D001 — Preserve Perl for the compatibility port

Status: **Accepted**

Decision:

Keep the existing Perl application and domain logic while introducing a GTK4
frontend. Do not combine the toolkit port with a whole-application language
rewrite.

Reason:

The library, filter, layout, queue, tagging, and random-mode behaviour is the
largest body of proven application knowledge. Rewriting it at the same time as
the UI would make compatibility failures difficult to isolate.

Revisit only if M1 demonstrates a binding limitation that cannot reasonably be
fixed or packaged.

## D002 — Layouts and saved configuration are compatibility APIs

Status: **Accepted**

Decision:

Existing layout identifiers, syntax, meaningful options, and saved application
data are part of the supported interface. Parse them into frontend-neutral
representations and preserve unknown data.

Consequence:

GTK4 widgets adapt to the layout model; the layout language is not rewritten to
mirror GTK4 APIs. Incompatible constructs require explicit diagnostics and an
approved exception.

## D003 — Use an incremental dual-frontend transition

Status: **Accepted**

Decision:

Keep GTK3 releasable while GTK4 is developed behind shared core contracts. Port
vertical slices and retain rollback until the GTK4 stable gate is met.

Consequence:

Some temporary adapter code and duplicated widget implementations are
acceptable. New application behaviour belongs in the shared core rather than
being implemented twice.

## D004 — GStreamer 1.x is the primary playback engine

Status: **Accepted**

Decision:

Modernize the current GStreamer backend rather than implementing direct
PulseAudio or PipeWire clients.

Reason:

GStreamer already owns decoding, timing, seeking, gapless playback, ReplayGain
pipeline elements, device integration, and output-sink selection. Direct audio
server APIs would duplicate policy and increase backend-specific maintenance.

## D005 — KDE integration uses cross-desktop standards

Status: **Accepted**

Decision:

Use MPRIS2, StatusNotifierItem, desktop notifications, desktop entries, and XDG
portals. Do not require Qt or KDE Frameworks for the main application.

Consequence:

Plasma receives native media and shell integration while the same services work
on other Linux desktops. KDE-specific code is reserved for features that have
no suitable cross-desktop interface.

## D006 — GTK4 Perl binding source and support policy

Status: **Open**

Gate: M1

Question:

Which GTK4 Perl binding source/version can the project maintain and package,
and what local overrides are required?

Evidence required:

- Custom GObject/widget subclass.
- `GListModel` and selection models at 100,000 rows.
- List item factory closures and recycling.
- Event controllers and drag-and-drop.
- Async dialog finish calls and error propagation.
- GStreamer/GLib main-loop coexistence.
- Reproducible Flatpak or equivalent bundle.

Options:

1. Use and pin an upstream Perl GTK4 distribution.
2. Maintain a small project wrapper/override layer over GObject Introspection.
3. Repair or contribute missing behaviour upstream.
4. If all are impractical, evaluate a separate frontend process in another
   language while retaining the Perl core.

Evidence recorded so far, against the system
`libglib-object-introspection-perl` binding and GTK 4.14.5:

- Graphene types cannot be marshalled. `compute_bounds` and `compute_point`
  both die with `GType GrapheneRect/GraphenePoint ... is not registered with
  gperl`, so widget geometry must go through `translate_coordinates`, which
  returns `($ok,$x,$y)`. Every geometry assertion in `t/gtk4/20_Paned.t` and
  `t/gtk4/30_Box.t` uses that route.
- `->can(...)` on an introspected class segfaults. Probe for a method by
  calling it inside `eval` instead.
- Creating any widget before `Gtk4::init` segfaults, so
  `GMB::Gtk4::Binding::try_init` (introspection setup only) is not sufficient;
  `backend_probe` must run first.
- Boolean arguments must be passed as explicit `0`/`1`. An empty string, such
  as the result of a failed `$opt=~m/_/`, is mishandled and produces
  allocations that look like a packing bug.
- `Gtk4::IconTheme::get_for_display` returns the display singleton, on which
  `set_theme_name` is refused with an `is_display_singleton` assertion and
  silently leaves the theme unchanged. Testing icon resolution against a
  specific theme requires `Gtk4::IconTheme->new`.

## D007 — Canonical application ID

Status: **Open**

Gate: before M4 installs desktop metadata

Question:

Choose the canonical reverse-DNS application ID and migration strategy. The ID
must align the GTK application, desktop filename, D-Bus activation, Wayland
window identity, packaging metadata, and MPRIS `DesktopEntry`.

The decision must account for existing `gmusicbrowser.desktop` installations,
taskbar pins, autostart entries, command-line control, and package upgrades.

## D008 — Minimum supported platform versions

Status: **Open**

Gate: end of M1

Question:

Set minimum versions for GTK4, GLib/GIO, GStreamer, Perl, the Perl introspection
stack, PipeWire compatibility, and supported Plasma releases.

Criteria:

- Availability in selected supported distributions.
- GTK list/dialog APIs required by the implementation.
- Binding coverage and known fixes.
- Reasonable security and maintenance lifetime.
- Cost of compatibility branches.

## D009 — Transitional use of deprecated GTK4 TreeView APIs

Status: **Proposed**

Gate: M4 planning

Decision proposal:

Permit GTK4 TreeView/ListStore/CellRenderer APIs only as a temporary bridge for
secondary dialogs. Primary library views and all new implementations use the
modern list/model stack.

Removal condition:

No deprecated TreeView-family use remains at the stable GTK4 release unless it
has an approved, time-bounded exception.

## D010 — SongTree GTK4 rendering architecture

Status: **Open**

Gate: M1 prototype, final choice early in M5

Options:

1. ListView/ColumnView and reusable row factories.
2. A purpose-built virtualized snapshot widget.
3. A hybrid: standard selection/list mechanics with a custom row/group widget.

Choose based on compatibility, measured performance, memory, accessibility,
input behaviour, and maintainability.

## D011 — Initial packaging format

Status: **Proposed**

Gate: end of M1

Decision proposal:

Use Flatpak as the first reproducible GTK4 distribution while continuing to
support native packages where maintainers can provide the required Perl
bindings.

Reason:

Flatpak can bundle the binding and typelibs while integrating with host audio,
D-Bus services, and portals. It avoids modifying system Perl at application
startup.

This does not make Flatpak the only supported format.

## D012 — Legacy playback backends

Status: **Proposed**

Gate: M7

Decision proposal:

- Keep GStreamer as default.
- Keep mpv as a supported fallback through the first GTK4 release.
- Deprecate mplayer and the mpg123/ogg123 family after documenting usage and
  compatibility gaps.
- Remove obsolete audio sink choices from the normal preferences interface,
  retaining advanced access only where there is a verified use case.

## D013 — No UI redesign in the parity release

Status: **Accepted**

Decision:

Changes required by GTK4, accessibility, Wayland, or desktop standards may
adjust mechanics and small presentation details. Product-level navigation,
information architecture, visual redesigns, and removal of established
workflows are deferred until after the compatibility release.

Reason:

Keeping parity and redesign as separate efforts makes regressions measurable
and protects the application qualities this project exists to preserve.

## D014 — Canonical URI and source-based file identity

Status: **Accepted**

Decision:

Represent every library file as a resource owned by a stable source. Canonical
URI/source-relative location is authoritative; a POSIX path is an optional
native representation. Existing `path`, `file`, and `fullfilename` behaviour is
retained as a compatibility view for local resources during migration.

Reason:

SMB, SFTP, FTP, AFP, portal documents, and KIO/GVfs resources do not reliably
have ordinary paths. Fabricating paths would preserve the current failure mode
and spread protocol checks throughout the code.

## D015 — Consume access established by the desktop

Status: **Accepted**

Decision:

Use GIO/GVfs for URI resources, desktop portals for user-approved access, and
KIOFuse/portal projections on Plasma. Gmusicbrowser consumes only locations the
desktop has already made accessible. It does not initiate network
authentication, implement credential prompts, embed protocol client libraries,
or store credentials.

Consequence:

Protocol availability is capability-detected and depends on installed desktop
backends. An inaccessible location is reported clearly with an action directing
the user to connect or authorize it through the desktop file browser, then
retry. The file chooser/portal may display its own desktop-owned access UI.

## D016 — Offline source is not missing media

Status: **Accepted**

Decision:

Source availability and song existence are separate states. An unsuccessful,
partial, cancelled, access-denied, or disconnected source scan cannot mark
songs missing or remove them. Missing reconciliation is committed only after a
complete successful traversal of that source.

Reason:

Treating a powered-off NAS as an empty directory would risk mass removal and
break saved lists, history, ratings, and metadata while offline.

## D017 — Remote writes require transactional safety

Status: **Accepted**

Decision:

Tag edits and file mutations are enabled per source capability. A remote tag
write must stage and validate locally, detect version conflicts, upload a
temporary sibling, and replace safely. If the backend cannot provide the
required preconditions and replacement semantics, the source remains read-only
for that operation.

Consequence:

Read/index/play support may ship for a protocol before tag editing. Feature
availability is explicit in the UI; gmusicbrowser never progressively
overwrites the only remote copy across an unreliable connection.

## D018 — Remote support is capability-based

Status: **Accepted**

Decision:

Advertise operations from detected capabilities rather than equating a URI
scheme with full support. Distinguish enumerable library roots, playable URIs,
seekable resources, monitors, and safe mutations.

Initial acceptance prioritizes desktop-projected paths, SMB, and SFTP. FTP,
FTPS, AFP, DAV/DAVS, and other GIO schemes are supported to the level that the
installed backend advertises and the project has tested. Ordinary HTTP(S)
remains playback-only unless an enumerable source contract is supplied.

## D019 — Remote cache policy

Status: **Proposed**

Gate: M6

Decision proposal:

Cache metadata and artwork locally for offline browsing and use bounded,
lease-based staging for metadata readers and playback. Do not mirror complete
remote libraries or cache all audio by default. A user-pinned offline music
feature can be proposed after the base remote-library milestone.

## D020 — Scans never hard-delete library records

Status: **Accepted**

Decision:

Source scanning is generation-based and non-destructive. A failed, incomplete,
cancelled, access-denied, disconnected, or source-identity-mismatched scan
cannot change missing state. A complete verified scan may mark specific songs
missing, but it does not erase their records or user metadata. Permanent purge
is a separate explicit action showing the affected source and count.

An unexpectedly large disappearance is quarantined as a degraded/offline
source condition until a later complete scan confirms it or the user explicitly
reviews it.

Reason:

A powered-off NAS can look like a missing directory, an inaccessible URI, or an
empty underlying mountpoint. None is reliable evidence that the user intended
to remove every song. Ratings, labels, history, queue membership, and saved
lists must survive ordinary storage outages.

## D021 — Preserve advanced tray interaction through layered integration

Status: **Accepted**

Gate: M7

Decision:

The modern tray is not reduced to a passive icon and menu. The standard
StatusNotifierItem preserves the camel icon, actions, current-song tooltip, and
wheel-controlled gmusicbrowser volume. Activating it opens a GTK4 compact
player with the legacy tray layout's essential controls, including seek and
rating.

Because the StatusNotifier host owns the icon, tooltip, and menu, its standard
interfaces cannot reproduce an application-owned interactive hover window. A
separately packaged Plasma system-tray companion will be prototyped for exact
hover interaction. It is a direct System Tray plasmoid, activated by
gmusicbrowser's D-Bus presence, and replaces the generic notifier while active
to avoid duplicate icons. It communicates over MPRIS and a minimal application
action interface and does not add Qt or KDE Framework dependencies to the main
process.

Stock GNOME has no application tray surface. There the required baseline is
MPRIS, notifications, and the activated GTK4 compact player; the generic
notifier appears only when a compatible distribution-provided host is present.
The project will not develop, bundle, require, or recommend a
gmusicbrowser-specific GNOME Shell extension.

Reason:

The compact hover player and icon-wheel volume control are distinctive,
high-value gmusicbrowser workflows. StatusNotifierItem directly supports
scroll input, so volume parity is practical on Plasma. Separating the optional
Plasma presentation from the application retains cross-desktop standards while
allowing KDE to provide the richer interaction its shell can host.

## D022 — Initial desktop scope is GNOME, Ubuntu, and Plasma

Status: **Accepted**

Decision:

The initial modernization release tests and supports stock GNOME, Ubuntu's
GNOME session, and KDE Plasma. It uses MPRIS, notifications, portals,
StatusNotifierItem where a host exists, and the Plasma companion described in
D021. Stock GNOME must work without installing any Shell extension.

Other Linux desktops may work through the same freedesktop interfaces, but they
are best-effort until separately added to the support and acceptance matrix.

Reason:

A defined desktop matrix keeps the compatibility port testable and avoids
turning optional shell-specific integrations into dependencies. It also allows
the project to provide a richer Plasma experience while respecting stock GNOME
and the integration Ubuntu already supplies.

## D023 — GTK4 icons use themed icon names, not a stock factory

Status: **Proposed**

Gate: before the GTK4 renderer grows icon-bearing widgets

Context:

GTK3 registers the 28 bundled `gmb-*` images through `Gtk3::IconFactory`
(`gmusicbrowser.pl:1579`) and resolves the rest by icon name through
`Gtk3::IconTheme`. Layouts name icons in widget options, for example
`ToggleButton3(icon=gmb-picture)` and `Fullscreen(stock=gmb-view-fullscreen)`,
so those names are part of the layout compatibility surface (D002).
`GtkIconFactory`, `GtkIconSet`, and the whole stock-item system were removed in
GTK4.

Decision:

The GTK4 frontend resolves every icon by name through `GtkIconTheme` and sets
it on widgets with `set_icon_name` / `Gtk4::Image->new_from_icon_name`. The
bundled `pix/` directory is added to the icon theme search path so the existing
`gmb-*` names keep resolving. No stock-item replacement is introduced, and the
`gmb-*` names are retained rather than renamed.

Verified on 2026-09-07 against GTK 4.14.5 through the system binding:

- `Gtk4::IconTheme::get_for_display`, `add_search_path`, and `has_icon` work.
- `has_icon('gmb-random')` is false with the stock search path and true after
  adding `pix/`, so the flat directory resolves without a themed
  `index.theme` hierarchy and without moving any file.
- `Button->set_icon_name`, `Button->new_from_icon_name`, and
  `Image->new_from_icon_name` all work.
- `Image->new_from_file` and `Gdk::Texture->new_from_filename` work as an
  explicit-path fallback for layout options that give a file rather than a name.

Alternatives:

1. Reorganize `pix/` into a themed hierarchy. Rejected as unnecessary: GTK4
   already resolves the flat directory, and moving the files would churn
   packaging for no functional gain.
2. Replace the `gmb-*` names with freedesktop equivalents. Deferred: that is a
   presentation change to a layout-visible name, which D013 postpones until
   after the parity release. Where a legacy name has an obvious standard
   equivalent, the mapping can be proposed separately.

Consequences:

Icon-bearing widget options (`icon=`, `stock=`) keep working unchanged in GTK4
layouts. Presentation is unchanged, so this stays inside D013: it replaces
removed infrastructure rather than restyling the interface. Any actual visual
refresh of the `gmb-*` artwork is a separate proposal after parity.

Evidence or removal condition:

Covered by renderer tests once icon-bearing widgets exist. Revisit if a bundled
icon fails to resolve on a supported desktop, or if packaging cannot ship
`pix/` on the icon search path.

## D024 — Icon resolution falls back to the `-symbolic` variant

Status: **Proposed**

Gate: before the GTK4 renderer grows more icon-bearing widgets

Context:

D023 resolves every icon by name through `GtkIconTheme` so that standard
freedesktop names follow the host icon theme. Measurement on 2026-09-07 showed
that resolving the unsuffixed name alone is not enough to reach that goal.

GNOME's Adwaita ships many action icons *only* as `<name>-symbolic`. Checked
with a standalone `Gtk4::IconTheme` retargeted at each theme, Adwaita has no
`application-exit`, `view-refresh`, `help-about`, `edit-clear`,
`view-fullscreen`, `media-skip-forward`, or `media-skip-backward`, but carries
all of them with the `-symbolic` suffix. KDE's Breeze and Ubuntu's Humanity
carry both spellings. So the unsuffixed name silently fails on stock GNOME,
which D022 lists as a required desktop target.

This is measurable inside the test runner itself: because
`tools/run-gtk4-smoke` isolates the session bus, GTK cannot read the desktop's
icon-theme preference and falls back to Adwaita. The pre-existing assertion
that `stock=gtk-quit` resolves to `application-exit` was therefore asserting a
name that the active theme could not render.

Decision:

`_IconName` tries every candidate in the existing chain unsuffixed first, then
tries the same candidates with `-symbolic` appended. The unsuffixed pass keeps
priority so a theme that still carries full-colour artwork keeps supplying it;
the suffixed pass is a fallback, not a preference. A candidate that already
ends in `-symbolic` is not suffixed twice. An unmapped unknown name is never
turned into a fabricated `<name>-symbolic`, so it still resolves to nothing and
the widget keeps its text label.

Alternatives:

1. Prefer `-symbolic` everywhere. Rejected: it would override full-colour
   artwork that Breeze, Humanity, and the bundled packs deliberately provide,
   which is a presentation change rather than a resolution fix.
2. Map each legacy name directly to a `-symbolic` name in `%StockNames`.
   Rejected: it hard-codes one theme's convention into the compatibility
   mapping and loses full-colour artwork where a theme has it.
3. Leave resolution unsuffixed. Rejected: it does not meet the stated goal of
   having the host icon theme supply the artwork, because the names fail on a
   D022 target desktop.

Consequences:

Standard names now follow the host icon theme on stock GNOME as well as Plasma
and Ubuntu. No layout-visible name changes, so the `icon=`/`stock=`
compatibility surface under D002 is untouched, and no artwork is added,
removed, or restyled. This stays inside D013 for the same reason D023 does: it
repairs resolution of removed infrastructure rather than restyling the
interface. The `gmb-*` bundled names are unaffected — none of them exists in
any host theme measured, so they continue to resolve from `pix/`.

Evidence or removal condition:

`t/gtk4/40_Icons.t` pins a standalone `Gtk4::IconTheme` to Adwaita and asserts
that `gtk-media-play` stays unsuffixed while `gtk-quit` and `gtk-refresh` fall
back to the symbolic variant. Run against the previous resolver those two
assertions fail, returning `application-exit` and `view-refresh`. Revisit if a
supported theme is found where the suffixed name is worse than the unsuffixed
one.

## Decision template

Copy this section for new decisions:

```markdown
## DNNN — Title

Status: **Open | Proposed | Accepted | Superseded**

Gate: milestone or date, if applicable

Context:

Decision:

Alternatives:

Consequences:

Evidence or removal condition:
```
