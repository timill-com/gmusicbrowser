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
- `get_size_request` and `set_size_request` work and agree with GTK3: an unset
  dimension is `-1` in both toolkits, so the legacy `ApplyCommonOptions`
  read-then-merge can be ported unchanged.
- `set_size_request` on a mapped Wayland window raises a minimum but cannot
  lower a size the compositor already granted, so a window cannot be shrunk in
  a test. This is the counterpart of the `set_default_size` limitation already
  recorded for `t/gtk4/20_Paned.t`. Assert a widget's minimum through
  `measure($orientation,-1)`, which returns
  `(minimum, natural, min_baseline, nat_baseline)` and marshals correctly.
- An out-of-range enum nickname is a **fatal** error through this binding, not
  a warning or a silent no-op: `Image->set_icon_size('menu')` dies with
  `FATAL: invalid enum GtkIconSize value menu, expecting: inherit / normal /
  large`. So a legacy GTK3 enum nickname cannot be passed through and probed
  for afterwards; it has to be mapped before the call. `GtkIconSize` measures
  16px for both `inherit` and `normal` and 32px for `large`.
- `Button->set_icon_name` creates a `Gtk4::Image` child reachable through
  `get_child`, and `set_pixel_size` on it works and is reflected in
  `measure()`. `set_label` replaces that child. `Button->get_icon_name`
  returns undef once the child is replaced with an explicit image, so styling
  the button's own image is the route that keeps both working.
- `Button->set_relief`/`get_relief` are absent, as expected for GTK4.
  `set_has_frame`/`get_has_frame` are present; `get_has_frame` returns `1` and
  the empty string rather than `1`/`0`, so compare it loosely or against `''`.
  `add_css_class('flat')` also works and `get_css_classes` reads it back.
- `Label->set_xalign`/`set_yalign` accept and return fractional values exactly
  (0.25 reads back 0.25), and so does the GTK3 `set_alignment` they replace.
  `Label->get_layout_offsets` returns the rendered text position, which is the
  only way to show a label's alignment actually took effect — the widget itself
  fills its slot, so `translate_coordinates` cannot see it.
- **Floating-point properties are formatted in the current locale.** A GTK3
  probe under this host's locale printed `xalign=0,5` with a comma and made
  `set_alignment` look broken. Run numeric probes under `LC_ALL=C`.

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

Production evidence added on 2026-09-07, when the `Next` and `Prev` widgets
were rendered: they are the first widgets in the port that actually depend on
this fallback. Their defaults are `gtk-media-next` and `gtk-media-previous`,
which `%StockNames` maps to `media-skip-forward` and `media-skip-backward`, and
Adwaita carries neither unsuffixed. Measured in the runner environment, both
resolve to the `-symbolic` spelling while `Stop` still resolves the unsuffixed
`media-playback-stop`, confirming that the unsuffixed pass keeps priority where
the artwork exists. Without this decision the two most-used unported buttons in
the bundled layouts — 34 and 29 instances — would render as text labels on
stock GNOME, which D022 makes a required target. The Wayland assertions accept
either spelling so they do not pin one theme's convention.

## D025 — `AB` becomes alignment properties on its child

Status: **Proposed**

Gate: before any `AB` row is advanced past `GTK4 in progress`

Context:

The legacy `AB` container is `Gtk3::Alignment->new(xalign,yalign,xscale,yscale)`
with defaults `.5, .5, 1, 1` (`gmusicbrowser_layout.pm:2333`). `GtkAlignment` was
deprecated in GTK 3.14 and **removed in GTK4**; its documented replacement is the
`halign`, `valign`, `hexpand`, `vexpand`, and margin properties that every
`GtkWidget` now carries. There is no container to construct.

`AB` is a layout-visible identifier under D002, and 14 bundled declarations use
it. All of them set only `xalign`, `yalign`, or `yscale`.

Decision:

The GTK4 renderer builds `AB` as a plain vertical `Gtk4::Box` holding the single
child, and translates the four legacy numbers into `halign`/`valign` on that
child. A scale of 0 means "do not expand", so the corresponding alignment is
applied; any other scale means "fill". The continuous alignment value is bucketed
into GTK4's three-valued enum: `<= .25` is `start`, `>= .75` is `end`, otherwise
`center`.

Alternatives:

1. Implement a custom `GtkWidget` subclass reproducing `GtkAlignment` exactly,
   including fractional scales. Rejected for now: it needs `measure`/`size_allocate`
   vfunc overrides through the introspection binding, which D006 has not yet
   established, for a construct no bundled layout exercises fractionally.
2. Drop `AB` and require layouts to set alignment on the child directly.
   Rejected: `AB` is a layout-visible identifier and D002 makes it a
   compatibility API.
3. Map `AB` onto `Gtk4::Box` alignment without a wrapper widget at all, so `AB`
   contributes no box to the tree. Rejected: `AB` can be named as a packing
   target by its siblings and appears in `$renderer->{widgets}`, so removing the
   node would change the tree the layout describes.

Consequences — where this is exact and where it is not:

Exact for every bundled layout. The only alignment values that appear anywhere in
`layouts/` are `0`, `0.0`, `.5`, `0.5`, and `1`, and the only scale values are `0`
and `0.0`. Each maps onto the GTK4 enum without loss, so no bundled layout is
approximated.

Two documented losses remain for a hand-written user layout:

- A fractional alignment such as `xalign=0.3` collapses to `start`. GTK3 would
  position the child 30% of the way across the slack.
- A fractional scale such as `yscale=0.5` is treated as `fill`. GTK3 would expand
  the child to half the available slack.

Neither is reachable from a bundled layout, and neither is silently wrong in a way
a user could mistake for correct behaviour: the child is visibly aligned or
visibly filled. Until alternative 1 is implemented, an `AB` row cannot be
advanced past `GTK4 in progress`, because "exact for the layouts we ship" is not
parity for the layout language.

Evidence or removal condition:

Construction and option handling are covered in `t/04_Gtk4LayoutRenderer.t`
against in-process doubles. There is no real-Wayland allocation test for `AB`
alignment yet; that is required before the row moves. Revisit if a user layout is
found relying on a fractional alignment or scale, which would promote
alternative 1 from deferred to required.

## D026 — `WB` becomes a plain box, and its purpose is not ported

Status: **Proposed**

Gate: before any `WB` row is advanced past `GTK4 in progress`

Context:

The legacy `WB` container is `Gtk3::EventBox->new` (`gmusicbrowser_layout.pm:2337`).
`GtkEventBox` was **removed in GTK4**: every `GtkWidget` can now take event
controllers directly, so a widget no longer needs a wrapper with its own
`GdkWindow` to receive input.

`WB` exists in gmusicbrowser for exactly one reason, stated in the source at
`gmusicbrowser_layout.pm:1247`: `hover_layout` "only works with widgets/boxes that
have their own gdkwindow (put it into a WB box otherwise)". `WB` is the escape
hatch for that limitation.

Two measurements matter here:

- **No bundled layout uses `WB` at all.** Zero declarations across all 13 files.
- The three `hover_layout` uses in `layouts/` reach it through the `EventBox`
  *widget* and the `Cover` widget, not through a `WB` container.

Decision:

The GTK4 renderer builds `WB` as a plain vertical `Gtk4::Box` holding the single
child, so a layout naming `WB` still parses, still builds, and still produces the
node its siblings may reference. The `GdkWindow` behaviour it existed to provide
is **not** ported, and does not need to be: in GTK4 the child can carry its own
event controllers, which is what removes the original limitation.

`hover_layout` itself is not implemented in the GTK4 renderer — it needs a popup
window — so `WB`'s reason for existing has no GTK4 consumer yet either.

Alternatives:

1. Reject `WB` with a diagnostic, on the grounds that its purpose no longer
   exists. Rejected: D002 makes it a layout-visible identifier, and a user layout
   naming it must keep working even though the bundled ones do not.
2. Implement `WB` as the widget that owns the hover controllers, folding
   `hover_layout` into it. Deferred, not rejected: this is the likely correct
   long-term shape, but it belongs with the `hover_layout` port rather than with
   the container, and it needs a popup-window design that does not exist yet.
3. Treat `WB` as a pass-through contributing no widget. Rejected for the same
   reason as D025 alternative 3: the node can be a packing target.

Consequences:

A layout naming `WB` renders its child in the right place. Anything that depended
on `WB` supplying a `GdkWindow` does not work, but nothing in the shipped layouts
does, and the GTK4 replacement for that dependency is event controllers on the
child rather than a wrapper. A `WB` row cannot be advanced past `GTK4 in
progress` until `hover_layout` is ported and alternative 2 is decided, because
until then the container is a shape with none of its behaviour.

Evidence or removal condition:

Construction is covered in `t/04_Gtk4LayoutRenderer.t`. Revisit when
`hover_layout` is ported: that is the point at which alternative 2 must be
accepted or rejected, and at which `WB` either gains real behaviour or is
formally recorded as a compatibility shim with none.

## D027 — Legacy icon `size=` becomes a pixel size, and `relief=` becomes has-frame

Status: **Proposed**

Gate: before any button row is advanced past `GTK4 in progress`

Context:

`Layout::Button` sets `relief => 'none'` and `size => SIZE_BUTTONS` in
`@default_options` (`gmusicbrowser_layout.pm:3001`), so both apply to *every*
button widget, not only to a layout that names them. `SIZE_BUTTONS` is
`large-toolbar` and `SIZE_FLAGS` is `menu` (`:18-19`). The GTK4 renderer
implemented neither, so every button it built was wrong in the same way
`minwidth=` was before the previous session: silently, and by default.

GTK4 removed both APIs. `gtk_button_set_relief` is gone, and `GtkIconSize` was
cut from the GTK3 set down to three values. Measured through the system
binding on GTK 4.14.5, every legacy name is a hard failure:

	set_icon_size('menu') -> FATAL: invalid enum GtkIconSize value menu,
	  expecting: inherit / normal / large

`inherit` and `normal` both measure 16px and `large` measures 32px, so the
enum cannot express the legacy set: `large-toolbar` is 24 and `dialog` is 48.

Decision:

Translate `size=` to `set_pixel_size` on the button's image, using the pixel
size GTK3 resolves each legacy name to, and translate `relief=` to
`set_has_frame`.

The pixel sizes are read from `Gtk3::IconSize::lookup` on GTK 3.24.41 rather
than assumed:

| legacy `size=` | GTK3 pixels | uses in `layouts/` |
|---|---:|---:|
| `menu` (`SIZE_FLAGS`) | 16 | 54 |
| `button` | 16 | 46 |
| `large-toolbar` (`SIZE_BUTTONS`) | 24 | 16 |
| `dialog` | 48 | 9 |
| `small-toolbar` | 16 | 4 |
| `dnd` | 32 | 0 |

Those five plus `dnd` are the whole GTK3 icon-size set, and the first five are
exactly the values that appear in the bundled layouts. `set_pixel_size`
reproduces each one exactly, so **this translation is lossless**, not a
bucketing approximation — unlike D025's fractional alignment case.

`Gtk4::Button->set_icon_name` builds the `GtkImage` itself, so the pixel size
is set on that child. This keeps `Button->get_icon_name` working, which the
renderer's own `_SetIcon`/`_SetPlayLabel` and the icon tests rely on;
substituting an explicit `Gtk4::Image` child would leave `get_icon_name`
undefined.

A `size=` value outside the mapping is left to the theme and keeps being
reported through `Unhandled`, so it is recorded rather than silently accepted.

Alternatives:

1. Map the legacy names onto the three-valued GTK4 enum (`menu`/`button` to
   `normal`, the rest to `large`). Rejected: it is lossy where
   `set_pixel_size` is not. `large-toolbar`, the default for every button,
   would render at 32px instead of 24, and `dialog` at 32 instead of 48.
2. Ignore `size=` and let the theme decide every icon size. Rejected: it
   silently changes the size of every button in every bundled layout, and
   `size=` is a layout-visible option under D002.
3. Use `add_css_class('flat')` for `relief=none` instead of
   `set_has_frame(0)`. Both work; `set_has_frame` was chosen because it is the
   documented property replacing `set_relief` rather than a style-class
   convention, and it is readable back through `get_has_frame` for testing.

Consequences:

Every button the renderer builds now gets the legacy defaults, so `Play`,
`Quit`, `Prev`, `Stop`, and `Next` are frameless 24px icon buttons as GTK3
draws them, rather than framed buttons at the theme's default size. `size=`
and `relief=` leave `%ButtonHandled`'s ignored list. No layout-visible name
changes and no artwork is added, removed, or restyled, so this stays inside
D013 on the same ground as D023 and D024: it repairs a mechanism GTK4 removed.

The bundled layouts already exercise this on widgets the renderer builds
today, so it is not forward-looking work: `layouts/fullscreen.layout` gives
`Play`, `Prev`, `Stop`, and `Next` `size=dialog`, which is **48px** against the
24px default, and `layouts/contrib.layout` gives `Play`, `Prev`, `Stop`,
`Next`, `Quit1`, and `Quit2` explicit sizes. Before this decision every one of
those rendered at the theme's default size inside a framed button.

This does not cover the `Total(size=small)` uses in `layouts/contrib.layout`.
That is a font size on a different widget, not an icon size, and does not
belong in this mapping.

Evidence or removal condition:

`t/gtk4/40_Icons.t` asserts the pixel size and the measured natural width for
all six mapped names against a real theme on Wayland, plus the unset case for
an unmapped name and both relief states. Run against the previous renderer it
fails 16 of 74; `t/04_Gtk4LayoutRenderer.t` fails 5 of 160. Revisit if a
supported desktop is found where a legacy pixel size is visibly wrong against
its GTK3 rendering under the same layout.

Note for anyone extending the assertions: a `measure()` check only
discriminates above 16px, because GTK4's own default icon size is 16. The
`menu`, `button`, and `small-toolbar` rows measure correctly even against a
renderer that ignores `size=` entirely, so `get_pixel_size` is what actually
pins those three. This is the same class of trap as the recorded
`set_size_request` one in D006.

## D028 — `Layout::Label` alignment and ellipsize port unchanged

Status: **Proposed**

Gate: before any `Layout::Label` row is advanced past `GTK4 in progress`

Context:

`Layout::Label` sets `xalign => 0, yalign => .5` in `@default_options`
(`gmusicbrowser_layout.pm:3105`) and applies them through
`Gtk3::Label::set_alignment`, which GTK3 deprecated in 3.14. `ellipsize` is
passed straight to `Gtk3::Label::set_ellipsize` (`:3127`).

Measured through the system binding on GTK 4.14.5 and GTK 3.24.41:

- **`Gtk4::Label` defaults to `xalign=0.5`**, not 0. So a `Label` or `Text`
  built without applying the legacy default is centred where GTK3
  left-aligns it. This affected every `Label`/`Text` the renderer had built.
- `set_xalign`/`set_yalign` accept **fractional values exactly** — 0.25 reads
  back as 0.25 — and so does the GTK3 `set_alignment` they replace. There is
  no enum, so nothing is bucketed.
- `set_ellipsize` accepts the same four Pango names in both toolkits.

Decision:

Apply the legacy `@default_options` and translate `xalign`/`yalign` to
`set_xalign`/`set_yalign`, and `ellipsize` to `set_ellipsize` unchanged.

Both translations are **lossless**. This is the important contrast with D025:
`AB` loses a fractional alignment because GTK4's `halign` is a three-valued
enum, but a label's alignment is a float property in both toolkits, so the
same fractional value that GTK3 accepted is preserved.

Two values are filtered rather than passed on, because an out-of-range value
is a **fatal** enum error through this binding rather than a warning:

- An `ellipsize` outside `none`/`start`/`middle`/`end`. Note
  `Layout::Button` maps `'1'` to `'end'` (`:3051`) but `Layout::Label`
  deliberately does not, so `ellipsize=1` on a label is not silently
  upgraded.
- A non-numeric `xalign`/`yalign`. GTK3 accepts it with a Perl
  `isn't numeric` warning and coerces it to 0, which is verified, not
  assumed; since the legacy `xalign` default is also 0 the renderer falls back
  to the default and reaches the same rendering.

Both keep being reported through `Unhandled`, so nothing is silently accepted.

Alternatives:

1. Map `xalign`/`yalign` onto `halign`/`valign` as the `AB` container does.
   Rejected: it would bucket a value the label can represent exactly, and
   `halign` positions the whole widget in its parent rather than the text
   inside the widget, which is a different effect.
2. Follow `Layout::Button` and map `ellipsize=1` to `end`. Rejected: it would
   change behaviour relative to GTK3, where a label with `ellipsize=1` does
   not ellipsize. The asymmetry between the two legacy classes is real and is
   preserved.
3. Also port `markup` (76 uses), `font`, `color`, and `minsize`. Deferred, not
   rejected. `markup` runs through `::UsedFields` and per-song substitution,
   `font` and `color` moved from widget overrides to CSS in GTK4, and
   `minsize`/`expand_max` drive the legacy scrolling-label machinery. Each is
   a larger unit than a presentation property and belongs with a real
   `Layout::Label` port.

Consequences:

`Label` and `Text` now render their text where GTK3 renders it. No
layout-visible option name changes, so the D002 compatibility surface is
untouched, and nothing about the text itself changes — this stays inside D013
on the same ground as D023, D024, and D027: it applies a default GTK4 does not
share and replaces a deprecated setter.

The `Layout::Label` family is `Text`, `Pos`, `Title`, `Title_by`, `Artist`,
`Album`, `Year`, `Comment`, `Length`, `PlayingTime`, `Volume`, `Visuals`, and
`LabelToggleButtons`, with `Label` an alias for `Text`. Only `Text`/`Label` is
implemented, so this decision currently reaches two elements, but the option
handling is where the rest of the family will land.

Evidence or removal condition:

`t/gtk4/30_Box.t` asserts the rendered text position through
`get_layout_offsets` for `xalign` 0, .5, and 1, that the no-option default
renders where `xalign=0` does and far from centred, and that `ellipsize=end`
lowers the label's minimum width. `t/04_Gtk4LayoutRenderer.t` covers the
fractional values, the defaults, and both filtered cases. Run against the
previous renderer, `t/gtk4/30_Box.t` fails 7 of 78 and
`t/04_Gtk4LayoutRenderer.t` fails 10 of 177.

Two things that make these assertions non-vacuous, both found by running them
against pristine:

- **Every alignment label must carry identical text.** With differing text the
  centred offsets already differ by a few pixels on their own (measured 186,
  190, 188, 187 for four centred labels), so an `isnt` or ordering comparison
  passes against a renderer that ignores alignment entirely.
- **The two ellipsize labels must carry identical text** for the same reason:
  an un-ellipsized minimum tracks the text width, so comparing two different
  strings measures the strings rather than the option.

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
