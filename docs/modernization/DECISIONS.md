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
- **A custom `GtkWidget` subclass registers and instantiates.**
  `Glib::Type->register_object('Gtk4::Widget','My::Class')` succeeds, the class
  instantiates, and the instance passes `->isa('Gtk4::Widget')`. Custom
  subclassing is therefore proven to that extent, and is no longer merely
  unestablished.
- **Layout vfunc overrides on such a subclass are silently ignored.** This is
  the decisive limitation. With `MEASURE`, `SIZE_ALLOCATE`, `do_measure`, and
  `do_size_allocate` all defined on one `Gtk4::Widget` subclass, **none** was
  called during real layout in a mapped Wayland window, and the introspected
  `measure('horizontal',-1)` returned `0,0,-1,-1` rather than the override's
  values. The widget was allocated height 0 against an override claiming 40.
  There is no warning and no error. Those vfuncs are C struct fields and are
  not introspectable, so a Perl sub cannot install itself into the class
  vtable. **Consequence: reimplementing a removed container as a custom widget
  is not possible through this binding.** Composing GTK4's existing layout
  managers is the available route. See D025.

  Method note: a sub named `measure` (lowercase) *does* get called, but only
  because it shadows the introspected `measure` method when Perl code calls
  `$widget->measure(...)` directly. That is a Perl method call, not GTK
  invoking a vfunc, and mistaking one for the other overstates what the
  binding supports. Probe with the uppercase/`do_`-prefixed names only, and
  judge by whether GTK's own layout pass calls them.
- **`Glib::Type->from_package` does not exist on this binding.** The call dies
  with `Can't locate object method "from_package" via package "Glib::Type"`.
  The available `Glib::Type` methods are `list_ancestors`, `list_interfaces`,
  `list_signals`, `list_values`, `package_from_cname`, `register`,
  `register_enum`, `register_flags`, and `register_object`. An earlier reading
  recorded it as *reporting classes absent*, which implied it worked and
  answered wrongly; it simply is not there. `Glib::Type->list_values` on an
  introspected enum such as `Gtk4::ConstraintStrength` also does not return an
  arrayref. Probe a class by constructing it inside `eval`, never by type
  lookup — the same lesson as the `->can` segfault.
- These construct successfully: `Gtk4::Fixed`, `Gtk4::Overlay`,
  `Gtk4::CenterBox`, `Gtk4::ConstraintLayout`, `Gtk4::BinLayout`.
  `Gtk4::CustomLayout->new` requires 4 arguments and `Gtk4::Constraint->new`
  requires 8 after the class name
  (`target, target_attribute, relation, source, source_attribute, multiplier,
  constant, strength`), so a bare `->new` reports `passed too few parameters`.
- **`Gtk4::Constraint` strength must be the numeric enum.** Passing the
  nickname `'required'` warns `Argument "required" isn't numeric` and silently
  coerces the strength to **0**, producing a constraint that does not bind at
  all while the object still constructs. `GTK_CONSTRAINT_STRENGTH_REQUIRED` is
  `1001001000`, which reads back correctly through `get_strength`. A
  non-binding size pin read back as a plausible-looking but wrong geometry in
  an earlier probe.
- **`backend_probe` never sets an `ok` key.** It returns either `error` or the
  display fields (`class`, `name`, `requested`, `session`, `wayland`,
  `wayland_display`). Checking `->{ok}` reports failure against a perfectly
  good Wayland display; check `->{error}`.
- **A widget's own CSS padding falsifies a geometry probe.** A
  `Gtk4::Button` given `set_size_request(40,24)` measured `get_width` **26**
  at origin **7,7** inside its slot, because the theme's button style insets
  the allocation. The same probe with a `Gtk4::Label` child measured exactly
  40 at origin 0. A uniform offset across every row of a geometry table is
  the signature of this, not of a layout bug: use a CSS-neutral child such as
  a `Gtk4::Label` when measuring a container's placement.
- **Pango is not reachable at all through the GTK4 binding.**
  `Pango::FontDescription::from_string` and `Pango::FontDescription->new` are
  both undefined, so the legacy `Pango::FontDescription::from_string($font)`
  that `Layout::Label` uses (`gmusicbrowser_layout.pm:3118`) cannot be ported
  directly; a font string has to be parsed in Perl. Pango *is* available
  alongside Gtk3, so a GTK3 probe can still read one for reference.
- **CSS works, and is the only route to a per-widget font or colour.**
  `Gtk4::CssProvider->new`, `load_from_data`,
  `Gtk4::StyleContext::add_provider_for_display`, and
  `remove_provider_for_display` all work. Two details:
  `load_from_data($css,length $css)` needs the **byte length as a second
  argument** — a one-argument call dies with `passed too few parameters
  (expected 3, got 2)` — and a rule body needs a **trailing semicolon** or
  GTK warns `Expected ';' at end of block` for every rule while still
  applying it.
- **A `font-size` in a CSS rule is only observable above the theme size.**
  The desktop font here is `Roboto 10`, and a `font-size: 10pt` rule measures
  identically to no rule at all, so an assertion at the theme size passes
  against a renderer that ignores the option. 8pt, 9pt, 11pt, 12pt, 14pt,
  16pt, 20pt, and 30pt all measure distinctly. This is the same class of trap
  as the 16px icon-size one recorded above.
- **A percentage `font-size` computed from the live theme size cancels out.**
  `20/16 * 16pt` is `20pt` again, so deriving a ratio from
  `gtk-font-name` reproduces the absolute size and the desktop font never
  reaches the widget. A ratio only follows the theme if it is fixed against a
  constant baseline. See D031.
- **`gtk-font-name` round-trips through `Gtk4::Settings` and can be set in a
  test,** which is how the theme-following behaviour above was measured. Its
  trailing number is the point size.
- **`dim-label` has no observable.** GTK4's de-emphasis style class styles by
  opacity at draw time: `get_style_context->get_color` returns the unmodified
  theme colour and `get_opacity` returns 1. `has_css_class` is the only
  check available, so a `dim-label` assertion is construction coverage. An
  **explicit** CSS colour is fully observable —
  `get_style_context->get_color` returned `rgb(255,255,255)` for
  `color: white`.
- **`gtk-application-prefer-dark-theme` is a GTK3 setting with no effect in
  GTK4.** Setting it changed no colour. The dark variant is selected by theme
  name instead (`Breeze` vs `Breeze-Dark`), and switching
  `gtk-theme-name` does move the reported colour. This host reports
  `prefer-dark-theme = 1` and theme text at `rgb(249,250,251)`, so it is
  genuinely in a dark context.
- **`Glib::Type->list_values` does not return an arrayref** for an
  introspected enum such as `Gtk4::ConstraintStrength`; the call yields
  `Not an ARRAY reference`. Enum values have to be obtained another way.
- **`Gtk4::StyleContext->get_property('opacity')` dies** with `type
  Gtk4::StyleContext does not support property 'opacity'`. Style values are
  not readable as GObject properties through this binding.
- **`Gtk4::SizeGroup` survives unchanged and works fully.** All four modes
  (`horizontal`, `vertical`, `both`, `none`) construct; `add_widget` raises a
  36px label to a grouped 180px; `remove_widget` returns it to 36; `get_mode`
  and `get_widgets` read back. This is what makes D034 a direct translation.
- **`Gtk4::Notebook` retains the whole legacy API surface** this project needs:
  `append_page`, `get_n_pages`, `set_current_page`/`get_current_page`,
  `set_scrollable`, `set_tab_pos`, `popup_enable`, and
  `set_tab_reorderable` all work. So the legacy `TB` container is portable;
  `NB` is gated on `Layout::NoteBook`'s own subsystem, not on the binding.
- **Event controllers work, and the whole legacy input surface is carried.**
  `Gtk4::GestureClick`, `GestureSingle`, `GestureDrag`, `GestureLongPress`,
  `EventControllerKey`, `EventControllerMotion`, `EventControllerFocus`,
  `ShortcutController`, `DragSource`, `Popover` and `PopoverMenu` all construct;
  click, scroll, and key controllers all **fire** with correct payloads in a
  mapped Wayland window. `EventControllerScroll->new` requires scroll flags and
  `DropTarget->new` a type plus actions, in the same way as `Gtk4::Constraint`.
  `add_controller`, `observe_controllers` and `remove_controller` all work, the
  last mattering for a renderer `Destroy`. This closes the M1 gate row; see
  `t/gtk4/50_Input.t`.
- **`GdkEvent` is not marshallable, like the graphene types.**
  `GestureClick->get_current_event` dies with `interface_to_sv: Don't know how
  to handle fundamental type GdkEvent (200)`. **Inside a signal handler Glib
  catches that and prints `unhandled exception in callback` to stderr**, so an
  `eval` there succeeds and an assertion written inside a handler passes without
  ever seeing the failure — probe it outside one. Consequence for any port: a
  handler's own arguments are the entire available payload.
- **A synthetic `pressed` reports button 0 however the gesture is filtered.**
  `set_button(3)` reads back as 3 through `get_button`, but
  `get_current_button` returns 0 under `signal_emit` because no GDK event backs
  it. The legacy contract keys actions on the button number
  (`gmusicbrowser_layout.pm:1284`), so a port must register **one gesture per
  button** and let GTK do the filtering, rather than one gesture that inspects
  the event. That is also the only shape a test can drive.
- **Baseline controller counts differ by widget type**: `Gtk4::Box` has 0,
  `Gtk4::Label` 1 (a `ShortcutController`), `Gtk4::Button` 3 (a key controller,
  a click gesture, and a shortcut controller). An assertion counting a widget's
  controllers therefore passes or fails for the wrong reason depending on the
  widget; identify a controller instead of counting.
- **`Gtk4::Fixed` covers only the static half of the legacy `FB`.** Both
  bundled `FB` uses are the fractional form (`.1,0,.8,0`), whose dynamic
  position and size are computed in `SFixed`'s `size_allocate` override
  (`gmusicbrowser_layout.pm:2443`) — the vfunc route this entry records as
  silently ignored. So "`Gtk4::Fixed` works" does **not** make `FB` a small
  increment; it needs a composed layout manager as `AB` does under D030. See
  D035, which fixed the parser side.
- **`Gtk4::Fixed` works, but `get_child_position` reads `0 0` until the widget
  is mapped.** After `put($child,10,20)` it returns `0 0`, and only after the
  window is presented and the main loop has run does it return `10 20`.
  `translate_coordinates` is correct immediately. A `Fixed` placement
  assertion written before mapping therefore reads zero and looks like a
  placement bug — the same class of trap as the unrealized-`Gtk3::Image`
  measuring 0.

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

Status: **Accepted**

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

Accepted 2026-09-07, together with D024, since both concern icon resolution.
No code change was required. Alternative 2 — replacing the `gmb-*` names with
freedesktop equivalents — remains deferred and was explicitly left deferred on
acceptance: those 28 files back gmusicbrowser's own "Icon theme :" preference
at `gmusicbrowser.pl:7023`, with three packs in `pix/`, so proposing the
mapping needs its own entry.

Covered by renderer tests once icon-bearing widgets exist. Revisit if a bundled
icon fails to resolve on a supported desktop, or if packaging cannot ship
`pix/` on the icon search path.

## D024 — Icon resolution falls back to the `-symbolic` variant

Status: **Accepted**

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

Accepted 2026-09-07, together with D023. No code change was required. The
production evidence below was decisive: without this fallback the two
most-used unported buttons in the bundled layouts render as text labels on
stock GNOME, which D022 makes a required target.

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

Status: **Accepted**, with the fractional case superseded by D030

Gate: before any `AB` row is advanced past `GTK4 in progress`

Superseded in part on 2026-09-07: the bucketing this entry accepted still
applies to every integral value, but a fractional alignment or scale now goes
through a `Gtk4::ConstraintLayout` instead of being bucketed. See **D030**,
which the user approved after the exactness measurement recorded below. The
two documented losses in the consequences section are therefore closed rather
than outstanding.

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
   including fractional scales. **Not merely deferred — currently impossible
   through this binding.** The earlier wording said this needed
   `measure`/`size_allocate` vfunc overrides "which D006 has not yet
   established", which implied an open question. It is now established as a
   negative: a `Gtk4::Widget` subclass registers and instantiates, but its
   layout vfunc overrides are **silently ignored** — `MEASURE`,
   `SIZE_ALLOCATE`, `do_measure`, and `do_size_allocate` were all defined on
   one subclass and none was called during real layout, with no warning. See
   D006. This alternative cannot be revived until D006's binding question is
   resolved (a project wrapper layer, or a different binding).
2. Drop `AB` and require layouts to set alignment on the child directly.
   Rejected: `AB` is a layout-visible identifier and D002 makes it a
   compatibility API.
3. Map `AB` onto `Gtk4::Box` alignment without a wrapper widget at all, so `AB`
   contributes no box to the tree. Rejected: `AB` can be named as a packing
   target by its siblings and appears in `$renderer->{widgets}`, so removing the
   node would change the tree the layout describes.
4. Compose GTK4's `Gtk4::ConstraintLayout` on the `AB` container, expressing
   the legacy `xalign`/`yalign`/`xscale`/`yscale` arithmetic as linear
   constraints. **This is the route that replaces alternative 1**, and it is
   measured exact — see the consequences section below.

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

Accepted 2026-09-07 **as a documented approximation**. The fractional
alignment/scale gap was neither closed nor waived: the user's call was to
accept the translation with the gap recorded, so the `AB` row deliberately
stays at `GTK4 in progress` and alternative 1 stays deferred rather than
promoted. Acceptance removes the decision gate on the row; it does not
advance it.

Construction and option handling are covered in `t/04_Gtk4LayoutRenderer.t`
against in-process doubles. Real-Wayland allocation coverage for `AB`
alignment now exists in `t/gtk4/30_Box.t`, but it covers the implementation
that already existed rather than proving new behaviour, and the fractional gap
above is what still blocks the row. Revisit if a user layout is
found relying on a fractional alignment or scale, which would promote
alternative 1 from deferred to required.

**2026-09-07, measured: `Gtk4::ConstraintLayout` reproduces `GtkAlignment`
exactly, so the gap above is closable without a custom widget.** Alternative 1
is impossible (D006), but alternative 4 is not. A single container whose
layout manager is a `Gtk4::ConstraintLayout`, given the legacy arithmetic as
two linear constraints per axis

	width = xscale*slot + (1-xscale)*child_min
	left  = xalign*(1-xscale)*slot - xalign*(1-xscale)*child_min

was measured against `Gtk3::Alignment` on the same fixture, the same 400px
slot, and the same `Gtk4::Label`/`Gtk3::Label` child with
`set_size_request(40,24)`, on the real Wayland connection under `LC_ALL=C`:

| `xalign` | `xscale` | GTK3 `x,w` | GTK4 `x,w` |
|---:|---:|---:|---:|
| 0 | 0 | 0,40 | 0,40 |
| 0.3 | 0 | 108,40 | 108,40 |
| 0.5 | 0 | 180,40 | 180,40 |
| 0.7 | 0 | 252,40 | 252,40 |
| 1 | 0 | 360,40 | 360,40 |
| 0 | 0.5 | 0,220 | 0,220 |
| 0.3 | 0.5 | 54,220 | 54,220 |
| 0.5 | 0.5 | 90,220 | 90,220 |
| 0.7 | 0.5 | 126,220 | **125**,220 |
| 1 | 0.5 | 180,220 | 180,220 |
| 0 | 1 | 0,400 | 0,400 |
| 0.3 | 1 | 0,400 | 0,400 |
| 0.5 | 1 | 0,400 | 0,400 |
| 0.7 | 1 | 0,400 | 0,400 |
| 1 | 1 | 0,400 | 0,400 |

Fourteen of fifteen agree exactly; one differs by 1px from constraint-solver
rounding. Both fractional losses this entry documents — a fractional alignment
and a fractional scale — are reproduced correctly, which the `halign`/`valign`
translation cannot express at all.

Two probe artifacts had to be removed before these numbers were trustworthy,
and both are recorded in D006 because they produce plausible wrong readings
rather than obvious failures: a `Gtk4::Button` child reports a 26px width at a
7px inset from its own theme CSS, which offsets every row of the table
uniformly; and a `Gtk4::Constraint` built with the strength nickname
`'required'` coerces to strength 0 and does not bind, so the size pin silently
has no effect. An earlier probe hit both and read as "uniformly +10 off with
the child stuck at its natural size".

## D026 — `WB` becomes a plain box, and its purpose is not ported

Status: **Accepted**

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

Accepted 2026-09-07 **as a documented approximation**, with alternative 2
left deferred rather than decided: folding `hover_layout` into `WB` needs a
popup-window design that does not exist yet. The `WB` row therefore stays at
`GTK4 in progress`, because until `hover_layout` is ported the container is a
shape with none of its behaviour. Acceptance removes the decision gate on the
row; it does not advance it.

Construction is covered in `t/04_Gtk4LayoutRenderer.t`. Revisit when
`hover_layout` is ported: that is the point at which alternative 2 must be
accepted or rejected, and at which `WB` either gains real behaviour or is
formally recorded as a compatibility shim with none.

## D027 — Legacy icon `size=` becomes a pixel size, and `relief=` becomes has-frame

Status: **Accepted**

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
   **Rejected on acceptance (2026-09-07):** the user confirmed
   `set_has_frame`. The `flat` style class would also entangle button relief
   with the still-undecided `font=`/`color=` CSS work.

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

Accepted 2026-09-07 as implemented, with `set_has_frame` confirmed over
alternative 3 and no code change required. This unblocks the
`size=`/`relief=` parity row from its decision gate; the row itself stays at
`GTK4 in progress`, because input, focus, and accessibility comparison against
GTK3 are still missing.

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

Status: **Accepted**

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

- An `ellipsize` outside `none`/`start`/`middle`/`end`, once the `'1'`
  shorthand below has been normalised.
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
2. Follow `Layout::Button` and map `ellipsize=1` to `end`. **Accepted
   2026-09-07**, reversing this entry's original recommendation, which was to
   preserve the asymmetry. The user's call was to normalise.

   The asymmetry between the two legacy classes is real: `Layout::Button` maps
   `'1'` to `'end'` (`:3051`) and `Layout::Label` passes the value straight to
   `set_ellipsize` (`:3128`), so a label written `ellipsize=1` does not
   ellipsize in GTK3. Normalising the label to the button's reading is
   therefore a **deliberate parity exception**, not a translation, and it is
   recorded as one rather than as a bug fix.

   What makes the exception cheap is that it is unreachable from anything the
   project ships. All **37** `ellipsize=` uses across `layouts/` name `end`;
   isolated with `[(,]ellipsize=` so `lmarkup`-style prefixes and
   `minsize=` cannot inflate the count. Not one bundled layout uses the `'1'`
   form, so no shipped layout changes appearance. The change is reachable only
   from a hand-written layout, where a user writing `ellipsize=1` plainly
   intends ellipsizing and GTK3 silently gave them none.
3. Also port `markup` (76 uses), `font`, `color`, and `minsize`. Deferred, not
   rejected. `markup` runs through `::UsedFields` and per-song substitution,
   `font` and `color` moved from widget overrides to CSS in GTK4, and
   `minsize`/`expand_max` drive the legacy scrolling-label machinery. Each is
   a larger unit than a presentation property and belongs with a real
   `Layout::Label` port.

Consequences:

`Label` and `Text` now render their text where GTK3 renders it, with one
accepted exception: a label written `ellipsize=1` ellipsizes at the end where
GTK3 leaves it un-ellipsized. No layout-visible option name changes, so the
D002 compatibility surface is untouched, and nothing about the text itself changes — this stays inside D013
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

Accepted 2026-09-07. The alignment and `ellipsize` translation landed
unchanged; alternative 2 was reversed in the same pass and is covered by its
own assertions.

Coverage for the normalisation, added when it was accepted:
`t/gtk4/30_Box.t` measures a third label carrying **identical text** to the
`ellipsize=end` and `ellipsize=none` labels and asserts its minimum width
equals the ellipsized one. Against the un-normalised renderer that label
measures **64px**, the full text width, against **12px** ellipsized, so the
assertion turns on the option rather than on the string. A fourth label
carries a genuinely out-of-range `ellipsize=sideways`, which keeps the
fatal-enum filter covered now that `'1'` is no longer out of range, and both
its assertions pass on the un-normalised tree as well — so the comparison
discriminates rather than merely failing everything. Run against the
un-normalised renderer, `t/gtk4/30_Box.t` fails 3 of 81 and
`t/04_Gtk4LayoutRenderer.t` fails 2 of 179.

Two things that make these assertions non-vacuous, both found by running them
against pristine:

- **Every alignment label must carry identical text.** With differing text the
  centred offsets already differ by a few pixels on their own (measured 186,
  190, 188, 187 for four centred labels), so an `isnt` or ordering comparison
  passes against a renderer that ignores alignment entirely.
- **The two ellipsize labels must carry identical text** for the same reason:
  an un-ellipsized minimum tracks the text width, so comparing two different
  strings measures the strings rather than the option.

## D029 — Prefer the native GTK4 mechanism, and build the equivalent when none exists

Status: **Accepted**

Context:

A standing instruction from the user, given at the end of the 2026-09-07
session and clarified through two rounds of questions:

> Basically I would rather simplify and implement things the GTK4 native way
> than trying to port the exact GTK3 thing.

and, when asked whether a not-yet-ported option such as `markup=` should make
the renderer refuse to render:

> we should try to find equivalent in this case in GTK4, if none exists, we
> must implement

This governs how every future increment chooses between mechanisms, which is
why it is recorded as a decision rather than only as a handoff note.

Decision:

1. **Native mechanisms, preserved behaviour.** Use the idiomatic GTK4 API for
   everything, and keep the legacy behaviour that API produces. Reach for the
   GTK4-native mechanism first; stop reproducing legacy quirks for their own
   sake.
2. **Fail loudly** on a construct that is genuinely unsupported: refuse to
   render rather than silently approximate.
3. **Find the GTK4 equivalent; if none exists, build it.** Nothing is
   deliberately dropped.

This does **not** override D002 or D013, and that was the point of the two
clarifying rounds:

- **D002** still holds: layout identifiers, syntax, meaningful options, and
  saved data remain compatibility APIs. "Native mechanism" is about the
  toolkit call underneath, never about rewriting the layout language to mirror
  GTK4.
- **D013** still holds: no UI redesign in the parity release. Choosing the
  native mechanism is not licence to restyle. D023, D024, D027, and D028 are
  the model — each replaced a mechanism GTK4 removed while keeping the
  rendering GTK3 produced.

Consequences and bounds:

- **The emphasis changes, not the accepted direction.** D023–D028 already did
  this; nothing accepted is reversed.
- **Clause 3 is bounded by the binding, not by ambition.** "We must implement"
  cannot mean a custom widget reproducing a removed container: a
  `Gtk4::Widget` subclass registers, but its layout vfunc overrides are
  silently ignored (D006). Until D006's binding question is resolved, native
  means **composing GTK4's existing layout managers** —
  `Gtk4::ConstraintLayout` being the demonstrated case, which closed D025's
  fractional gap without a subclass.
- **Clause 2 is close to moot in practice, and must not be over-applied.** The
  realistic failure case is a construct nobody has implemented *yet*, not one
  abandoned. Clause 2 does not mean the renderer refuses every layout using an
  unported option: `markup=` alone has 76 uses, and refusing those would take
  the renderer from rendering 8 widget types to refusing nearly every real
  layout, destroying the incremental path. The existing `Unhandled` accessor
  stays the mechanism for a not-yet-ported option — read but reported, never
  silently accepted.

Evidence or removal condition:

Accepted 2026-09-07 as a standing instruction from the user. Revisit if a
native mechanism is found that cannot preserve legacy behaviour, which would
force a choice between this entry and D002/D013 rather than the coexistence
recorded here.

## D030 — A fractional `AB` alignment or scale uses a constraint layout

Status: **Accepted**

Supersedes: the fractional half of D025

Context:

D025 accepted bucketing the legacy `AB` numbers into GTK4's three-valued
`halign`/`valign` enum, with two documented losses reachable only from a
hand-written layout: a fractional alignment collapsed to `start`/`center`/`end`,
and a fractional scale became a full fill. It deferred a custom `GtkWidget`
subclass as the exact route.

Two findings changed the picture:

- That custom-widget route is **impossible** through this binding, not merely
  unestablished. A `Gtk4::Widget` subclass registers and instantiates, but its
  layout vfunc overrides are silently ignored. See D006.
- `Gtk4::ConstraintLayout` reproduces `GtkAlignment` **exactly**, with no
  subclass. Measured against `Gtk3::Alignment` on the same fixture, the same
  400px slot, and the same label child, 14 of 15 fractional
  `xalign`/`xscale` combinations agree exactly and one differs by 1px from
  constraint-solver rounding. The table is in D025.

D029 makes composing GTK4's own layout managers the native answer here, and
its "find the equivalent; if none exists, build it" clause is satisfied by an
equivalent that exists.

Decision:

The `AB` container takes a `Gtk4::ConstraintLayout` when any of its four
numbers has no enum equivalent, and keeps the D025 `halign`/`valign` path
otherwise. Per axis the layout carries two constraints:

	size = scale*slot + (1-scale)*minimum
	pos  = align*(1-scale)*slot - align*(1-scale)*minimum

The second is the substituted form of `align*(slot-size)`, which keeps each
constraint linear in a single source term as `GtkConstraint` requires. The
child's `minimum` comes from `measure($orientation,-1)`, which returns the
right value before realization.

An alignment of `0`, `.5` or `1` and a scale of `0` or `1` keep the plain
property path, so **every bundled layout is unaffected**: D025 established
that the only values appearing in `layouts/` are `0`, `0.0`, `.5`, `0.5`, `1`
for alignment and `0`, `0.0` for scale. Note a scale of `.5` needs the
constraint path even though an alignment of `.5` does not, because `center`
expresses the latter and nothing expresses "half fill".

A value that is non-numeric or outside 0..1 cannot drive the arithmetic. It
falls back to the legacy default and is reported through `Unhandled`. The
refusal is expressed by the internal `_number` helper returning nothing, which
is what keeps the `.5`, `0.0` and `1.0` spellings the bundled layouts use from
being reported as refused.

Alternatives:

1. Keep D025's bucketing and record the gap permanently. Rejected: D029 asks
   for the native equivalent where one exists, and one does.
2. A custom widget reproducing `GtkAlignment`. Impossible through this
   binding; see above and D006.
3. Use a constraint layout for every `AB`, including the integral cases.
   Rejected: it would put the whole bundled-layout surface onto a new
   mechanism to no benefit, where the property path is already exact for it.

Consequences:

The two losses D025 documented are closed, so the reason that entry gave for
holding the `AB` row at `GTK4 in progress` no longer applies. The row still
does not advance, for the reasons that apply to every row: input, focus,
accessibility, and saved-profile comparison against GTK3 are unfinished.

One behaviour change beyond the fractional case: a non-numeric `xalign` now
renders **centred** rather than bucketing to `start`. Centred is the legacy
`@default_options` value, so this is a correction toward GTK3, and it is
covered by an assertion that fails against the previous renderer with
`got 'start' / expected 'center'`.

The `Gtk4::Constraint` strength must be passed as the numeric enum
(`1001001000`); the nickname `'required'` warns `isn't numeric` and coerces to
strength 0, building a constraint that does not bind. See D006.

Evidence or removal condition:

`t/gtk4/30_Box.t` asserts the real allocated size and offset for a fractional
`xalign`, a fractional `xscale`, both together, and a refused value, and
asserts that the integral cases keep a non-constraint layout manager so the
common path cannot regress. `t/04_Gtk4LayoutRenderer.t` asserts the constraint
count, multipliers, relation, source attribute, numeric strength, and the
`Unhandled` bookkeeping.

Run against the previous renderer, `t/gtk4/30_Box.t` fails 11 of 107 on real
Wayland and `t/04_Gtk4LayoutRenderer.t` fails 11 of 199 offline. Controls that
pass on both trees: the five "keeps the plain box layout" assertions, the
slack sanity checks, `a fractional xalign with xscale=0 leaves the child at
its natural size`, and `a fractional alignment the constraint path implements
is not reported`.

Two assertions were vacuous when first written and were strengthened after
running them against pristine, which is worth knowing before extending them:
"not collapsed to the near edge" passes against the old renderer because it
buckets `0.3` to `center`, not `start` (its threshold is `<=.25`); and
"places the child 70% across the remaining slack" passes when the child fills
the slot, because the target offset is then 0 and so is the measured one. Both
are now paired with an assertion that the slack exists.

## D031 — Legacy label `font=` and `color=` become theme-relative CSS

Status: **Accepted**

Gate: before any `Layout::Label` row citing `font=`/`color=` is advanced past
`GTK4 in progress`

Context:

`Layout::Label` applies `font=` with `Gtk3::Label::modify_font` and `color=`
with `override_color` (`gmusicbrowser_layout.pm:3118-3122`). GTK4 **removed
both**: there is no per-widget font or colour override left, and styling goes
through `GtkCssProvider`.

Usage in the bundled layouts, isolated with `[(,] *(font|color)=`:

| option | uses | where |
|---|---:|---|
| `color=` | 5 | 4 on `Text` in `desktop.layout`, 1 on the drawing layer in `shimmer.layout:132` |
| `font=` | 4 | `Title`/`Artist`/`Album`/`Date` in `shimmer.layout` |

`desktop.layout` also sets `DefaultFontColor= white` in three of its layouts
and `DefaultFont=8` in a fourth, and `fullscreen.layout` sets
`DefaultFont = 20` in both of its. Those are layout-wide globals read at
`gmusicbrowser_layout.pm:971`, so `color=grey` there overrides an inherited
`white`. Their inheritance is D032, done after this entry.

Measured through the system binding on GTK 4.14.5, and this is what shaped the
decision: **the OS theme font and colours already reach the renderer's labels
with no code at all.** The desktop font is `Roboto 10`, an unstyled
`Gtk4::Label` measures 19x17, and GTK3 on the same host reports the same font
and the same 19x17. So the starting point already satisfies the project goal
that the desktop theme supply the presentation; anything this decision adds is
an *override* of that.

Decision:

Both options become a style class on one `Gtk4::CssProvider` that the renderer
installs on the display with `add_provider_for_display` and takes off again in
`Destroy`. Rules are keyed by value, so two widgets asking for the same font
or colour share one rule.

**`font=` is emitted as a percentage of the theme font, not as absolute
points.** The ratio is fixed against a 10pt baseline — the GTK3 default the
bundled layouts were authored against, verified on this host rather than
assumed — so `font=20` is always `200%` and `font=8` always `80%`.

Measured, this is what makes the desktop font reach the widget:

| desktop font | unstyled | `font=20` | `font=8` |
|---|---:|---:|---:|
| Roboto 10 | 17px | 32px | 13px |
| Roboto 16 | 26px | 51px | 21px |
| Roboto 8 | 13px | 26px | 11px |

At the 10pt baseline the rendering is identical to GTK3's absolute 20pt. Away
from it the layout's *relative* emphasis is preserved instead of its absolute
size, which is the deliberate exception this entry records.

**`color=` maps a grey onto GTK4's `dim-label` style class**, which follows the
theme including its dark variant, because every bundled use is a grey
expressing de-emphasis rather than a request for one specific shade. A grey is
either a named grey (`grey`, `gray`, `silver`, `dimgrey`, …) or a hex value
whose channels are equal, so `#ccc` and `#888888` classify the same way. Any
other colour is emitted literally as `color: <value>`.

A value that cannot be translated — a `font=` naming no size, a colour CSS
cannot parse — and any value at all on a display where no provider can be
installed, leaves the option reported through `Unhandled`. Only known-safe
colour spellings are emitted, because one unparseable declaration makes GTK
drop the whole sheet.

Alternatives:

1. Emit `font=` as absolute points, reproducing GTK3 exactly. Rejected by the
   user after measurement: it is mathematically what deriving the percentage
   from the *live* theme size also does (20/16 of a 16pt theme is 20pt again),
   and it shuts the user's font preference out of exactly the widgets a layout
   styles. This is the one place where D002 fidelity and the D022/D029 goal of
   letting the desktop theme through genuinely conflict, and the user chose the
   theme.
2. Emit every `color=` literally. Rejected for greys: a fixed mid-grey is
   theme-blind, and on a dark desktop — this host reports
   `gtk-application-prefer-dark-theme = 1` with theme text at
   `rgb(249,250,251)` — it no longer reads as de-emphasis relative to its
   surroundings. Kept for non-greys, where the layout is naming a colour rather
   than an intent.
3. Map every `color=` onto `dim-label`, discarding the value. Rejected: a
   layout asking for red would silently get grey.
4. Clamp the font ratio to a narrow band. Rejected as an extra rule to justify
   with no bundled layout needing it; `font=20` at a 16pt desktop is large by
   the layout's own intent.
5. Port `DefaultFont`/`DefaultFontColor` inheritance in the same increment.
   Deferred, not rejected: they are layout-wide globals rather than widget
   options, so they belong with a scoped port of layout-level option
   inheritance. **Done as D032**, which reuses this entry's provider and
   extends the theme-relative exception to a whole-layout scope.

Consequences:

`Label` and `Text` now honour `font=` and `color=`, and both leave
`%LabelHandled`'s ignored list. No layout-visible option name changes, so the
D002 surface is untouched. This stays inside D013 on the same ground as D023,
D024, D027, and D028: it replaces a mechanism GTK4 removed. Under D029 the CSS
provider is the native answer, and the theme-relative form is what keeps the
native mechanism from overriding the OS theme.

Two limits worth stating plainly:

- **`dim-label` has no observable through this binding.** It styles by opacity
  at draw time, so `get_color` returns the unmodified theme colour and
  `get_opacity` returns 1. It can only be asserted as a CSS class, which makes
  the grey path construction coverage rather than rendered-colour coverage. An
  explicit colour *is* observable through
  `get_style_context->get_color`.
- The four bundled `font=` uses are on `Title`/`Artist`/`Album`/`Date`, none of
  which the renderer builds yet, so `font=` is exercised only by the fixture
  until those elements land. `color=` on `Text` is reachable today, and so is
  an inherited `DefaultFontColor` under D032.

Evidence or removal condition:

`t/gtk4/30_Box.t` measures the rendered height for `font=20` and `font=8`
against an unstyled label carrying identical text, asserts the ratio classes,
reads an explicit colour back from the style context, and asserts the
`dim-label` class and the `Unhandled` bookkeeping for a refused value.
`t/04_Gtk4LayoutRenderer.t` covers the grey classification, the refusal cases,
the baseline constant, and that `Destroy` releases the provider.

Run against the previous renderer, `t/gtk4/30_Box.t` fails 8 of 124 on real
Wayland and `t/04_Gtk4LayoutRenderer.t` fails 14 of 230 offline. The offline
comparison needs `_IsGrey`, `_ColorRule`, `_FontRule`, and the baseline
constant stubbed into the pristine copy, or the helper block dies before its
assertions are reached. Controls passing on both trees: every "is not a grey"
and "is refused" assertion, `a label with no font= gets no font class`, `an
unparseable font= leaves the theme font alone`, and the three `Unhandled`
assertions for values pristine also refuses.

Note for anyone extending these assertions: the theme colour differs between
environments — near-white on this desktop, `rgb(46,52,54)` inside
`tools/run-gtk4-smoke`, whose Adwaita and unset session bus are already
recorded in D006. Compare against the measured theme colour rather than
hard-coding one.

## D032 — Layout-wide `DefaultFont`/`DefaultFontColor` are inherited through the same CSS

Status: **Accepted**

Supersedes: D031 alternative 5, which deferred this

Context:

`DefaultFont` and `DefaultFontColor` are layout-wide globals, not widget
options. Legacy `InitLayout` reads them into `{global_options}`
(`gmusicbrowser_layout.pm:971`) and `NewWidget` merges that hash into every
widget's options (`:1162`). The GTK4 renderer never read the parser's
`{metadata}`, where both land, so a label inheriting either was drawn at the
theme font and colour.

**Do not infer the precedence from the `:1162` merge order.** `%$global_opt`
is merged *last*, which reads as though the global wins, but neither option
actually lets it: `:1163` is `$options{font} ||= $global_opt->{DefaultFont}`
and `Layout::Label` at `:3120` is `$opt->{color} || $opt->{DefaultFontColor}`.
Both spell the fallback with `||`, so **a widget's own `font=`/`color=`
wins**. This was read from production code, and the trap is why it is spelled
out here.

Usage in the bundled layouts, all six occurrences:

| layout | `Type` | value | reachable today |
|---|---|---|---|
| `desktop.layout` `[D_insens_song_cover]` | D | `DefaultFontColor= white` | no |
| `desktop.layout` `[D_buttons_song_cover]` | D | `DefaultFontColor= white` | no |
| `desktop.layout` `[D_clementine]` | D | `DefaultFontColor= white` | **yes** |
| `desktop.layout` `[D_screenlet]` | D | `DefaultFont=8` | no |
| `fullscreen.layout` `[default fullscreen]` | F | `DefaultFont = 20` | no |
| `fullscreen.layout` `[Fullscreen simple]` | F | `DefaultFont = 20` | no |

They are three separate `Type=D` layout definitions in `desktop.layout`, not
nested scopes. `[D_clementine]` is the reachable one: it contains `Text5`, a
`Text` widget the renderer builds today with no `color=` of its own, so it
inherits the `white`. The other five carry only `Title`/`Artist`/`Album`/
`Date`/`Cover`-family widgets, none of which is implemented. An earlier
reading of this entry's ground missed `[D_screenlet]`'s `DefaultFont=8`
entirely and described the whole item as forward-looking; the `Text5` case
makes it a fix to a shipped layout.

Decision:

`Render` reads both keys from `$layout->{metadata}` into `$self->{globals}`,
and `_ApplyLabelOptions` falls back to them per option. Consequences of that
shape:

1. **The legacy precedence is preserved**: a widget's own `font=`/`color=`
   wins, matching the `||` in both legacy call sites.
2. **Each global is inherited independently.** Overriding the font leaves the
   inherited colour applied and vice versa, because the fallback is per option
   rather than for the pair. Measured on real Wayland: a label carrying
   `font=8` under `DefaultFont=20, DefaultFontColor=white` renders at 80% *and*
   in white.
3. **A widget's own refused value is taken rather than falling through to the
   global.** `font=oops` renders at the theme font, not at the inherited
   ratio, which is what `||` does with a truthy but invalid value.
4. `DefaultFont` reuses D031's `_FontRule`, **so the theme-relative ratio
   applies to it too**: `DefaultFont = 20` becomes `200%` of the desktop font
   for every label in that layout at once, and `DefaultFont=8` becomes `80%`.
   The user was asked specifically about the whole-layout scope of that and
   chose consistency with D031.
5. `DefaultFontColor` reuses `_ColorRule`, so an inherited grey would become
   `dim-label`. Every bundled use is `white`, which is emitted literally.

`PATH`, `SkinPath`, and `SkinFile` are read into the same legacy hash and are
**not** ported: they belong to the skin machinery, which has no GTK4 work yet.

An inherited value the renderer cannot translate is reported through a new
`UnhandledGlobals` accessor rather than the per-widget `Unhandled` list. No
widget's options named it, so attributing it to every inheriting widget would
misreport which options a layout actually wrote.

Alternatives:

1. Emit an inherited `DefaultFont` as absolute points while keeping a widget
   `font=` theme-relative. Rejected by the user: it would create two rules for
   one concept, and the D031 reasoning — that the desktop font should reach the
   widget — applies at least as strongly to a global that styles a whole
   layout.
2. Implement `DefaultFontColor` only, deferring `DefaultFont` until
   `Title`/`Artist`/`Album` land and it can be measured on a real fullscreen
   layout. Offered to the user and declined; the fixture measures it fully
   today, and splitting the two would leave half a mechanism.
3. Report an untranslatable global against every inheriting widget. Rejected:
   it would put an option name in `Unhandled` for a widget whose layout never
   wrote it, which is the one thing that list is supposed to mean.
4. Merge the globals into each widget's parsed option values, mirroring
   `NewWidget:1162` literally. Rejected: it would mutate the parsed catalog,
   which D002 keeps as a round-trippable compatibility surface, and the
   renderer's `Unhandled` bookkeeping reads `{options}{order}` to decide what
   the layout named.

Consequences:

`Label` and `Text` now honour both globals. No layout-visible name changes, so
the D002 surface is untouched, and this stays inside D013 on the same ground as
D031: it restores inheritance GTK4's removal of `modify_font`/`override_color`
had broken. The theme-relative exception D031 records now extends to a
whole-layout scope, which is the substantive parity note on this entry.

`{metadata}` is now load-bearing for the renderer, where previously only
`{nodes}` and `{roots}` were. `Type` remains metadata the renderer ignores,
which is what lets a `Type=G` fixture carry both keys.

Evidence or removal condition:

`t/gtk4/30_Box.t` measures the rendered height and reads the style-context
colour for an inheriting label, a label overriding the font, a label overriding
the colour, and a label whose own values are both refused, against an unstyled
baseline taken from a separate layout carrying no globals.
`t/04_Gtk4LayoutRenderer.t` covers the metadata read, the grey inheritance path
that works without a provider, the precedence, the `UnhandledGlobals`
reporting, and that `Destroy` drops both.

Run against the previous renderer, `t/gtk4/30_Box.t` fails **6 of 143** on real
Wayland and `t/04_Gtk4LayoutRenderer.t` fails **7 of 250** offline. The
pristine failure values were confirmed to be the right reason: `21 > 21` for
the inherited font, because the previous renderer draws every label at the
theme size, and `got rgb(46,52,54) / expected rgb(255,255,255)` for the
inherited colour, `46,52,54` being the runner's Adwaita colour recorded in
D006. The offline comparison needs only the `UnhandledGlobals` accessor stubbed
into the pristine copy; `_Globals` must be confirmed absent before the
comparison is trusted.

Controls passing on both trees, which is what makes the comparison
discriminate rather than merely fail everything: every assertion covering the
pre-existing per-widget `font=`/`color=` path, `a label in a layout with no
globals carries no styling class`, both "falls back to the theme, not to the
global" assertions, and the four `undef` bookkeeping assertions.

One assertion was vacuous as first written, in the same class as D030's two.
`a widget's own color= overrides the inherited DefaultFontColor` asserted only
that the overriding label lacks `dim-label`, which passes against a renderer
that never applies `dim-label` to anything. It is now paired with an assertion
that the inheriting and overriding labels differ from each other.

## D033 — A static `markup=` is applied; a field-bearing one waits for song state

Status: **Accepted**

Gate: the field-bearing half needs the song-field state path, which is
unported

Context:

`markup=` was the dominant unported label option. Reading
`Layout::Label` showed it is not one option but two paths, split in the legacy
code itself at `gmusicbrowser_layout.pm:3156`:

	if (exists $opt->{markup})
	{	my $m=$opt->{markup};
		if (my @fields=::UsedFields($m))
		{	$self->{EndInit}=\&init;	# WatchSelID, re-render per song
		}
		else { $self->set_markup($m) }
	}
	elsif (exists $opt->{text}) { $label->set_text($opt->{text}) }

A value naming no song field is set **once**, with no subscription and no song
data. That half is a presentation option and is what this entry ports.

**The recorded count of 76 conflates three different things.** It is
arithmetically right for `[(,] *markup=` across `layouts/`, but it reconciles
as:

| | count |
|---|---:|
| real `markup=` options in layout blocks | **56** |
| SongTree drawing-layer uses inside `{Group ...}`/`{Column ...}` skin blocks | 19 |
| commented-out layout-block line | 1 |
| total matching the recorded grep | 76 |

The 19 skin-block uses are the `text(markup=...)` drawing DSL, with `pesc()`,
`.` concatenation, `$_row` and `myfont` — the same class of thing as the
already-recorded `shimmer.layout:132` `color='#ccc'` drawing-layer trap. They
are not label options and no label port will ever reach them. The figure that
matters for a renderer increment is **56**, confirmed independently by walking
the parser's own catalog rather than by grep.

Of those 56, exactly **2 are static**:

| where | widget | value |
|---|---|---|
| `makeitlooklike.layout:481` | `Text` | `/` |
| `shimmer.layout:119` | `Label0` | `<span size="xx-large" weight="ultrabold">«</span>` |

Both land on already-implemented elements, so this is reachable from shipped
layouts today. The other 54 name fields (`%a` 13, `%t` 13, `%l` 12, `%s` 7,
`%y` 3, `%m` 2, `%Y` 1, `%g` 1, and the `$album`/`$artist`/`$length`/
`$title_or_file`/`$track` aliases) and stay reported.

Decision:

`_ApplyLabelOptions` applies a field-free `markup=` with
`Gtk4::Label::set_markup`, taking precedence over `text=` as `:3156` does. A
field-bearing value is left untouched and reported through `Unhandled`.

**Malformed markup needs a decision because GTK4 gives no usable signal.**
Measured through this binding: `set_markup` does **not** die, and its warning
is a GTK warning on stderr, not a Perl warning — `$SIG{__WARN__}` captures
nothing. On failure it leaves the *displayed* text untouched while
`get_label` still returns the raw string, so the widget silently keeps whatever
it had. Pango is unreachable through this binding, so
`Pango::parse_markup` is not available to validate with.

The renderer therefore sets the markup over a sentinel string the markup itself
cannot produce, and treats the value as refused if the text did not move. A
refused value falls back to `set_text` of the raw string, so a typo shows its
own source rather than producing an invisible widget, and the option is
reported.

Field detection counts **any** field sigil (`%<letter>`, `$name`, `${expr}`)
rather than only one `%::ReplaceFields` defines. `::UsedFields`
(`gmusicbrowser.pl:1012`) maps the letters through that table and keeps only
defined ones, but the table is built from the song field definitions at
`gmusicbrowser_songs.pm:1935` — shared core the renderer must not load. The
divergence is deliberately on the safe side: an unmapped `%X` is reported
rather than drawn as literal text. It changes nothing for the bundled layouts,
whose values name only real fields.

Alternatives:

1. Implement both halves, including `::UsedFields`, `WatchSelID`, and per-song
   re-rendering. Offered to the user and declined for this increment: it is a
   subsystem port — song selection state, field dependency tracking, and an
   update subscription — not a presentation option. It remains the gate on the
   other 54 uses and on the whole `Layout::Label` family.
2. Refuse to render any `markup=`, per D029 clause 2. Rejected on D029's own
   terms: the entry says explicitly that clause 2 must not be read as refusing
   a not-yet-ported option, and `Unhandled` is the mechanism for one.
3. Pass a malformed value straight to `set_markup` and let GTK warn. Rejected:
   the label would keep whatever text it had, the option would not be reported,
   and the warning is the only symptom — the silent acceptance the project
   constraints forbid.
4. Leave a refused label empty rather than showing its raw markup. Rejected by
   the user: a typo'd layout would give a widget that has vanished, which is
   harder to diagnose than one showing its own source.
5. Detect failure by checking for empty text. Rejected as **wrong**, not merely
   worse: `''` and `<b></b>` are both valid and legitimately render nothing, so
   this would misclassify them as refused. See the note below on how this was
   nearly recorded as the mechanism.

Consequences:

`markup` leaves `%LabelHandled`'s ignored list conditionally — reported when it
names a field or cannot be parsed, silent when applied. That conditional shape
already exists for `size=` (D027) and `font=`/`color=` (D031).

No layout-visible name changes, so the D002 surface is untouched, and there is
no presentation change beyond rendering the markup the layout asked for, which
keeps this inside D013.

**A refused value still prints one GTK warning to stderr** during the
validation attempt. It cannot be suppressed from Perl. Two appear during
`make test-gtk4`, one for each refused value in the fixture; they are expected
and must not be hidden.

Evidence or removal condition:

`t/gtk4/30_Box.t` measures that a markup naming `xx-large` renders taller than
plain text carrying the same content, reads `get_text` against `get_label` to
tell a parsed markup from one drawn literally, and covers the precedence over
`text=`, the malformed fallback, and the field-bearing report.
`t/04_Gtk4LayoutRenderer.t` covers the same offline plus the field detection
table and that the validation sentinel never survives on any label.

Run against the previous renderer, `t/gtk4/30_Box.t` fails **6 of 157** on real
Wayland and `t/04_Gtk4LayoutRenderer.t` fails **10 of 293** offline. The
pristine failure values were confirmed to be the right reason: the markup
labels are all empty, and the precedence assertion fails with
`got 'ignored' / expected 'big'`, which is the `text=` the old renderer shows.
The offline comparison needs `UnhandledGlobals` and `_MarkupUsesFields` stubbed
into the pristine copy; `_Markup`, the sentinel, and the `%LabelHandled` entry
must be confirmed absent before it is trusted.

Controls passing on both trees: every `text=` assertion, every "is reported"
assertion (pristine reports `markup` for *all* values, being wholly
unimplemented), the field-detection table, and the eight sentinel-leak
assertions.

**The near-miss worth recording, because the method produced a wrong reading
that looked convincing.** The first probe concluded "on failure `get_text`
returns empty, so empty means refused". That was an artifact of the probe's own
fixture: the labels were built with `Gtk4::Label->new('')`, so the *retained
previous text* was empty. Re-probing over a non-empty label showed `set_markup`
leaves the previous text — `SENTINEL`, then `previous` — untouched. Had the
first reading been implemented, a valid `<b></b>` would have been reported as
refused. **Probe a retained-state behaviour from a non-default starting state**,
or the default masks what is actually retained.

The offline `Gtk4::Label` double reproduces all of this, and its markup
stripper was validated against the real binding on all 11 probe cases —
including the three malformed classes (unclosed tag, unknown tag, unknown
entity) and the two validly-empty ones — rather than being written to satisfy
the test.

## D034 — `HSize`/`VSize` map onto `Gtk4::SizeGroup` unchanged

Status: **Accepted**

Context:

The legacy layout language has size groups: a declaration named `HSize`,
`VSize`, or either with a numeric suffix lists widgets that should share a
minimum size (`gmusicbrowser_layout.pm:1056-1070`). There are **27**
declarations across the bundled layouts, in four shapes, all exercised:

| shape | uses | meaning |
|---|---:|---|
| `HSize0= Filler0 LockArtist LockAlbum` | 10 | group the named widgets |
| `VSize0= 300 HBCover` | 12 | size request only — **no group** |
| `HSize1= 120 Text5 Text6` | 5 | size request **and** group |

The parser already recognised the spelling (`_is_definition`, `[HV]Size\d*`)
and kept these in `{definitions}`, correctly outside `{nodes}`/`{roots}` since
they declare no container. The renderer simply never read them.

`GtkSizeGroup` survived into GTK4 unchanged. Measured through this binding: all
four modes (`horizontal`, `vertical`, `both`, `none`) construct, `add_widget`
raises a 36px label to a grouped 180px, `remove_widget` returns it to 36, and
`get_mode`/`get_widgets` read back. So this is a **direct, lossless**
translation — unlike `AB` (D025/D030) or the icon sizes (D027).

Decision:

`Render` calls `_ApplySizeGroups` **after** building the tree, which is the
legacy order and is necessary because a declaration names widgets and
containers that must already exist. Containers are registered in the same
`{widgets}` hash as widgets, exactly as the legacy uses one hash for both, so
`VSize0= 300 HBCover` resolves.

Both legacy shapes are preserved exactly, including the early exit at
`:1063`:

- A leading all-digits token is a size request on the group's axis, leaving the
  other dimension `-1` — which both toolkits spell the same way, already
  verified for `minwidth=`.
- `next if @names==1` means a numbered declaration naming a single widget
  creates **no group at all**. That is 12 of the 27 bundled uses, so it is the
  common case rather than an edge one.
- Where a group is created as well, the group wins: the shared width is the
  widest member's natural width, which can exceed the requested number.

Legacy warns `Can't add unknown widget '$n' to sizegroup` for a name it cannot
resolve (`:1068`). The renderer records it through a new `UnhandledSizeGroups`
accessor instead, since it has no diagnostics channel of its own, and still
groups the members it *can* resolve rather than discarding the declaration.

`Destroy` releases the groups, which hold references to their widgets.

Alternatives:

1. Translate a size group into explicit `set_size_request` calls computed from
   the members' measured minima. Rejected: it would freeze the size at
   construction, where a real size group keeps tracking as content changes, and
   `Gtk4::SizeGroup` exists and does it properly.
2. Ignore the numeric shortcut and only group. Rejected: 12 of the 27 bundled
   uses are exactly that shortcut with no group, so ignoring it would drop the
   majority case.
3. Warn on an unresolvable name as the legacy does. Rejected for consistency
   with the established `Unhandled` convention — the renderer reports rather
   than warns, so a caller decides how to surface it.

Consequences:

The two options `maxwidth=`/`maxheight=` are still unimplemented and are
unrelated to this: they feed `Layout::Label`'s `expand_max` scrolling
machinery, not a size request.

This is the first thing the renderer reads from `{definitions}` other than
container declarations, which is a small widening of what the catalog surface
means to it — `{metadata}` became load-bearing under D032 the same way.

Evidence or removal condition:

`t/gtk4/30_Box.t` measures that a grouped short label is raised to a long
label's minimum width while an **ungrouped** long label in the same row keeps
its own, that a numbered `VSize` raises the named widget's height, and that a
numbered `HSize` naming two widgets both requests and groups.
`t/04_Gtk4LayoutRenderer.t` covers the group count and modes, the request/no-group
early exit, the unknown-name reporting, and that `Destroy` releases them.

Run against the previous renderer, `t/gtk4/30_Box.t` fails **6 of 166** on real
Wayland and `t/04_Gtk4LayoutRenderer.t` fails **8 of 308** offline. Pristine
failure values confirmed as the right reason: `got 7 / expected 180` for the
equalisation, `21` against `40` and `7` against `120` for the requests. Only
the `UnhandledSizeGroups` accessor needs stubbing into the pristine copy;
`_ApplySizeGroups` must be confirmed absent before the comparison is trusted.

Two things worth knowing before extending these assertions:

- **The offline block had to be guarded against an undef dereference.**
  `@{$renderer->{size_groups}}` dies on a renderer that creates no groups,
  which aborted the file at the first new assertion and hid the other
  fourteen. Guarding with `|| []` is what lets pristine reach and fail them
  honestly. This is the same "an abort hides your other assertions" trap the
  `Filler` increment recorded.
- **One assertion was vacuous and pristine caught it.** `is($t5w,$t6w)`
  compared two labels carrying different-length text — but on the old renderer
  *both* measured 7, equal because neither was touched, so it passed. The
  fixture now gives them clearly different natural widths, and the assertion is
  paired with one that the shared width exceeds the requested number. Same
  class as D030's two vacuous assertions.

### The counting correction this increment produced

Chasing a discrepancy between the recorded widget instance counts and the
parser's own found that **a raw `grep -o` also matches size-group
declarations**, which name existing widgets and instantiate nothing. Five
recorded figures were inflated by that, plus comments, `Name=` prose and option
text:

| element | recorded | actual instances | inflation |
|---|---:|---:|---|
| `Filler` | 102 | **94** | 8 names on `HSize`/`VSize` lines |
| `MenuItem` | 103 | **99** | 4 |
| `ToggleButton` | 39 | **35** | 4 |
| `SeparatorMenuItem` | 32 | **30** | 2 |
| `LockAlbum`, `LockArtist` | 22 each | **15** each | 7 each |

`LockAlbum` was verified by listing all 22 occurrences by hand: 7 are on
`HSize0=` lines. The three figures earlier sessions derived by careful
tokenizing — `Next` 34, `Prev` 29, `Stop` 20 — **match the parser exactly** and
need no correction.

An earlier revision of the handoff said these figures "reproduce and should not
be corrected". They do reproduce as grep output; they are not widget counts.

**State the basis with any instance count**, because two defensible bases
differ: widgets *declared in a layout's own block* (`Next` 34) versus
*instances across all layouts* (`Next` 36), which counts again whatever a
derived layout inherits — six bundled layouts use `based on`. This document and
`PROGRESS.md` use the own-declaration basis.

## D035 — The neutral parser applies the `FB` position prefix

Status: **Accepted**

Context:

`Layout::Parser::_extract_children` translates a container's packing prefix
before the child name. It had a branch for `HB`/`VB`, one for `HP`/`VP`, and one
for `TB`, matching three of the six `Prefix` regexes in `%Layout::Boxes::Boxes`
(`gmusicbrowser_layout.pm:2276-2322`). The `FB` one at `:2322` had no
counterpart, so the coordinate token was never consumed as a prefix.

The consequence was not a missing feature but a **silently wrong parse**, with
**0 diagnostics**. `FBLower= .1,0,.8,0 HBLower` produced two children:

| | pristine parser | legacy `::ExtractNameAndOptions` |
|---|---|---|
| children | **2** | **1** |
| first child name | `.1,0,.8,0` | `HBLower` |
| first child element | `.1,0,.8,` — trailing digit stripped as a suffix | — |
| first child kind | `widget` | — |
| `HBLower` packing | `''` | `.1,0,.8,0` |

The truncated element is the numeric-suffix rule (`$element=~s/\d+$//`) firing
on a coordinate, which is what makes the phantom look like a plausible widget
name rather than obvious corruption.

Both bundled uses are in `fullscreen.layout` (`:18` and `:39`) and both are
`.1,0,.8,0` — the **fractional** form, which is `SFixed_dynamic_pos` plus
`SFixed_dynamic_size`. So a correct prefix is a prerequisite for any `FB` port,
not merely a counting correction.

Decision:

`_extract_children` gains an `FB` branch using the legacy regex unchanged. The
prefix becomes `{packing}{raw}` exactly as the other four container families do,
and the renderer remains free to interpret or report it.

Alternatives:

1. Leave it and let a future `FB` increment fix the parser at the same time.
   Rejected: the defect corrupts the catalog *today* for anything walking it,
   and every recorded instance count is derived from that walk.
2. Emit a diagnostic for an unrecognised prefix instead of parsing it.
   Rejected: legacy accepts these layouts silently, and D002 makes the syntax a
   compatibility API — the parser's job is to agree with legacy, not to
   editorialise.

Consequences:

The bundled widget-instance total drops from **1163** to **1161**; implemented
instances are unchanged at **235**, so coverage moves 20.2% → 20.24%. Nothing
else in the catalog moves: 76 layout declarations, 19 skins, 0 errors.

**`FB` is still not portable, and this entry does not make it so.** `SFixed`
(`gmusicbrowser_layout.pm:2443`) implements the whole dynamic position/size
behaviour in a `size_allocate` vfunc override, and D006 records that layout
vfunc overrides on a `Gtk4::Widget` subclass are silently ignored through this
binding. A future `FB` port must therefore compose a layout manager, as D030 did
for `AB`. An earlier handoff listed `FB` as a small increment because
"`Gtk4::Fixed` works"; `Gtk4::Fixed` is only the static half.

**A mid-line `#` is deliberately not treated as a comment.** `contrib.layout:78`
carries `#VolumeIcon #_VolumeSlider(horizontal=1)`, which the catalog reports as
two widget instances. That looked like a second defect of the same class, but
legacy strips only whole-line comments (`ReadLayoutFile`: `next if m/^#/`), and
`InitLayout` then turns each unresolvable name into a `Layout::PlaceHolder`. The
parser reproduces legacy exactly, so it was left alone. Two of the remaining
non-alphabetic catalog entries are this, not corruption.

Evidence or removal condition:

`t/02_LayoutParser.t` covers the fractional bundled shape, the integer shape,
and the negative/fractional four-value shape, plus that the child is still
recognised as a `container_ref` and keeps its base element. Expected values were
taken by running the legacy `::ExtractNameAndOptions` with the legacy `FB`
regex, not from the new implementation.

Against a pristine `git archive HEAD` tree with only the test and fixture
overlaid, `t/02_LayoutParser.t` fails **11 of 56** — exactly the new
assertions, with the remaining 45 passing on both trees as controls. The
pristine failure values are the phantom-widget symptom itself: `got '2' /
expected '1'` for the child count, `got '.1,0,.8,0' / expected 'HBinner'` for
the name, `got 'widget' / expected 'container_ref'` for the kind, and `got '' /
expected '.1,0,.8,0'` for the packing.

## D036 — Follow the GTK4 standard for design changes; keep every layout working

Status: **Accepted**

Context:

A standing instruction from the user, given after the input-controller probe
closed and the four remaining design-shaped choices were put to them:

> for all design changes needed, I would say to respect GTK4 as much as
> possible, and the standard here. What I really like in Gmusicbrowser is the
> shimmer desktop layout, but we shall keep all the layouts working. Maybe the
> theme shall be simplified overall.

This extends D029, which settled *mechanism* ("find the GTK4-native equivalent;
if none exists, build it"). D036 settles the **presentation and platform
convention** question that D029 explicitly did not: where GTK4 or the freedesktop
standard has an opinion about how a thing should look or behave, follow it.

Decision:

1. **The GTK4 and freedesktop convention is the default** for anything the port
   has to redesign — menu models, dialogs, icon naming, header/window
   structure, dark-mode handling, focus and keyboard conventions.
2. **Every bundled layout must keep working.** This is not softened by clause 1.
   Layout compatibility is D002 and remains the harder constraint: where the
   native convention and a bundled layout conflict, the layout wins and the
   conflict becomes a decision entry, not a silent drop.
3. **`Shimmer Desktop` is the reference layout** for judging whether the port
   still feels like gmusicbrowser. It is named by the user as the layout they
   actually use. It is not privileged in *support* terms — all layouts must
   work — but when a judgement call needs a concrete subject, use this one.
4. **Simplifying the theme is approved in principle**, scope still open. See the
   open question below; this clause records the direction, not a mandate.

Bounds, carried forward unchanged:

- **D013 still holds.** "Follow the GTK4 standard" is not licence for a UI
  redesign in the parity release. It governs choices the port is *forced* to
  make, not ones it could avoid. A GTK4 mechanism that would change established
  navigation or information density still needs its own entry.
- **D002 still holds**, and clause 2 restates it deliberately, because clause 1
  is the kind of instruction that erodes it by degrees.

Consequences:

`Shimmer Desktop` is currently the **least** covered bundled layout — 5 of its
45 own widget instances render, 11%, against a 20% average — precisely because
it uses close to one of everything: 4 `FilterPane`, 4 `ToggleButton`, 5
`MenuItem`, a `SongTree`, a `SongList`, a `QueueList`, `Stars`, plugin widgets,
and the `NB`/`BM`/`SM` containers. It also opens with widgets hidden
(`Window= hidden=VPSongPlaylist|FilterPane2`) and declares `DefaultFocus` and
`KeyBindings`, none of which is ported.

**So "the layout I like" is a late milestone, not a near one**, and saying so is
more useful than optimising toward it. It becomes a good acceptance target
around the end of M5 rather than a next increment.

For menus this settles the mechanism question: `GMenu`/`PopoverMenu` is the GTK4
standard and clause 1 selects it, leaving only the scope to agree.

Open question this entry does **not** settle:

"Simplified theme" has at least two readings with very different costs, and the
user has approved the direction without choosing between them. Do not assume
one. They are set out where the choice has to be made, and the user asked to be
given the trade-off explicitly rather than a recommendation alone.

Evidence or removal condition:

Accepted 2026-09-07 as a standing instruction. Revisit if following a GTK4
convention is found to break a bundled layout, which would put clause 1 and
clause 2 in direct conflict and require a specific entry rather than this
general one.

## D037 — Icons come from the desktop theme; dark/light is an in-app toggle defaulting to system

Status: **Accepted** (direction), with the toggle's mechanism **measured** and
its integration unscoped

Gate: the preference change needs a D002 exception before it lands

Context:

Asked to choose between retiring gmusicbrowser's own icon-theme preference in
favour of the desktop theme, keeping both, or deferring, the user answered:

> I would say desktop theme only now, but we should have possibility to toggle
> dark and light also in app but default to system

That is the first option **plus** a requirement the option did not include, and
the addition is the substantive part: "desktop theme only" and "an in-app
dark/light toggle" pull in opposite directions unless the toggle is built as an
override of the desktop theme rather than as a theme of gmusicbrowser's own.

Decision:

1. **Icons resolve through the desktop icon theme by themed name**, which D023
   and D024 already implement. The bundled `pix/` packs stay on disk and remain
   the fallback for the 28 `gmb-*` names the desktop has no equivalent for.
2. **gmusicbrowser's own "Icon theme :" preference is retired** for the GTK4
   frontend. It is a user-visible settings change and a saved-configuration key,
   so it needs a D002 exception entry of its own before it lands. **No file is
   removed from `pix/`** — that is separately forbidden and is not required by
   this decision.
3. **Dark/light is a three-state application preference — system, light, dark —
   defaulting to system.** System means: install nothing and let the desktop
   theme through, which is what D031/D032 already established.

Measured mechanism, because the obvious routes do not work:

- **libadwaita is absent on this host**, so `AdwStyleManager` — the standard
  GTK4 answer for exactly this toggle — is not available and cannot be assumed.
- **`gtk-application-prefer-dark-theme` has no GTK4 effect**, already in D006.
- **Switching `gtk-theme-name` is not a usable toggle.** Setting it to
  `Adwaita`, a light theme, left the label colour at `0.93,0.93,0.93` — barely
  moved from the dark baseline. The name changes and the colour does not follow,
  so a toggle built on theme names would appear to work while doing nothing.
- **A display-level `GtkCssProvider` does work, exactly and reversibly.** With
  an unambiguous test colour, a label read `0.976,0.980,0.984`, then
  `1.000,0.000,0.000` once the class was added, then the original value again
  once removed. That is the mechanism the toggle should use, and it is the same
  `_StyleProvider` machinery D031/D032 already built.

**Method note, because the first reading was nearly recorded as a finding.** The
first probe used `#eeeeee` and read `0.93,0.93,0.93` — close enough to the
baseline to look like "CSS is partly ignored". This host is already in a dark
context, so every honest dark value sits near every other one. Re-probing with
`rgb(255,0,0)` gave an unmistakable answer. **Probe a colour mechanism with a
colour the theme could never produce**, or the theme's own palette masks whether
the rule applied at all — the same family as the `font-size` trap in D006, where
a 10pt rule measures identically to the 10pt theme font.

Alternatives:

1. Keep the four bundled icon packs and add the desktop theme as one more entry
   in the existing combo. Rejected by the user in favour of "desktop theme only".
   It would also not be a simplification: 196 icon files, the preference, the
   loader, and a new code path, maintained permanently.
2. Ship a gmusicbrowser dark theme. Rejected — this is what the user described
   as "not the modern way to do things" when D031 was decided.
3. Depend on libadwaita for the toggle. Rejected for now: it is absent here, and
   adding it is a packaging decision that belongs with D011, not a side effect of
   a styling preference.

Consequences:

`Shimmer Desktop`, the reference layout under D036, is unaffected by this: its
appearance comes from the layout and the desktop theme, not from the icon packs.

The toggle is **not yet built**. What is settled is the direction and the
mechanism; what is unscoped is where the preference lives, since the GTK4 proof
application still has no configuration writer at all.

Evidence or removal condition:

Colour measurements above, taken on real Wayland under `LC_ALL=C`. Revisit
clause 3's mechanism if libadwaita becomes a dependency, in which case
`AdwStyleManager` supersedes the CSS route and should be preferred as the
standard answer under D036 clause 1.

## D038 — Port the menu *interpreter* to `GMenu`/`PopoverMenu`, not the menu instances

Status: **Accepted**, interpreter implemented

Gate: the 23 `gmusicbrowser_list.pm` call sites cannot be exercised until
`SongList`/`SongTree` exists

Context:

Menus are the largest remaining group — **206** widget instances, of which
`MenuItem` is 99 and `SeparatorMenuItem` 30. GTK4 removed `GtkMenu` outright, so
this is a forced rewrite rather than an API swap, and D036 clause 1 selects
`GMenu`/`PopoverMenu` as the GTK4-standard replacement. Only the scope was open.

The user first chose to port the whole subsystem in one increment. **Reading
`BuildMenu` after that choice changed the risk, and the revised finding was put
back to the user rather than acted on silently.**

**`BuildMenu` (`gmusicbrowser.pl:4670`) is an interpreter, not a definition.**
Every popup is constructed at popup time from live application state:

- **14 conditional filters** per item — `type`, `mode`, `notmode`, `isdefined`,
  `istrue`, `isfalse`, `empty`, `notempty`, `onlyone`, `onlymany`, `test`, and
  `ignore`.
- **four structural operators** that recurse — `foreach` (one item per value),
  `include` (splice in a computed array), `repeat` (splice in several), and
  `change_input` (rewrite the arguments for subsequent items).
- **labels and icons may themselves be coderefs** evaluated against the same
  arguments.

`GMenu` is the opposite shape: a declarative model described up front and then
bound to a `PopoverMenu`. Hand-porting 206 instances would mean re-encoding that
interpreter 206 times, and much of it would need reworking once `SongList`
lands, since **23 of the 50 `BuildMenu`/`PopupContextMenu` call sites are in
`gmusicbrowser_list.pm`**, which is unported.

Decision:

Port the **interpreter**. The GTK4 side gains a `BuildMenu` equivalent that
consumes the *same legacy menu-definition arrays* and emits a `GMenu` model
driven by a `PopoverMenu`. The menu definitions themselves — `@SongCMenu`,
`@cMenuAA`, `@TrayMenu` and the rest — are data and stay as they are.

This keeps the user's "whole subsystem at once" intent while working with the
dynamic shape rather than against it: one interpreter covers all 206 instances,
and every call site that already builds a definition array keeps working.

Consequences and honest bounds:

- **The dynamic operators must be evaluated at popup time, not at model-build
  time.** A `GMenu` may be rebuilt before each popup; that is the supported
  pattern and is what preserves `foreach`/`include`/`repeat`/`change_input`.
- **The 23 `gmusicbrowser_list.pm` call sites cannot be exercised** until
  `SongList`/`SongTree` exists. They will be reported, not claimed as covered.
  Any coverage figure for this decision must state that exclusion.
- `plugins/appindicator.pm` remains explicitly out of scope: it is marked "do
  not port its GTK3 menu".
- Actions must reach the frontend contract's command dispatch rather than
  calling widget code, per the architecture constraints. A menu item whose
  command is not registered would build and then fail on activation, which is
  the same trap already recorded for `%Buttons`.

Alternatives:

1. Hand-port the 206 layout instances. Rejected once the interpreter was read:
   it re-encodes the conditional and structural logic per instance, and the
   list-dependent half would be done twice.
2. Prove the route on a single context menu first. Offered as the smaller step
   after the risk was found; the user kept the subsystem scope with the
   interpreter framing instead.

Implementation notes, all measured:

- **A separator is a section boundary, not an item.** Appending an empty section
  where the separator sits does **not** group anything: measured, the empty
  section counts as an item of its own and the entries after it stay at the top
  level (`get_n_items` read 6 where 2 was expected). `_Append` therefore splits
  the definition into runs first and makes each run a section, leaving a single
  run flat so the common menu keeps no needless wrapper.
- **An entry carrying `code` takes the choice-menu path whatever its submenu's
  type.** That is legacy's order at `gmusicbrowser.pl:4742`, and the reason is
  that an `ordered_hash` submenu is an array of alternating labels and values
  rather than a definition. Dispatching on the submenu's type instead — which is
  the natural-looking reading — dies with `Can't use string ("Main") as a HASH
  ref`. **Found only by building the real `@TrayMenu` shape**; every synthetic
  fixture had missed it.
- **`include` receives the menu as its second argument and both bundled
  callbacks use it** (`gmusicbrowser_layout.pm:25` and `:40`), calling
  `BuildChoiceMenu(menu=>$menu)` to append in place and returning nothing to
  splice. Since splitting happens before any model exists, such a callback is
  collected during the split and run during the fill.
- **Sensitivity is an action property in GTK4**, not an item property, so an
  insensitive entry is disabled rather than dropped, matching legacy.
- Code reaches an item through `Gio::SimpleAction`, because a model item cannot
  hold a closure. A **string** code is a command name and goes through the
  frontend contract, never to a widget.

Evidence or removal condition:

`t/07_Gtk4Menu.t` (64 assertions, offline) and `t/gtk4/60_Menu.t` (25
assertions, real Wayland).

**The strongest evidence is not a pristine comparison.** A new module cannot
fail meaningfully against a tree that lacks it — the pristine run dies at
`require` with **0 assertions executed**, which proves only that the file is
new. What validates the port instead is that **29 of the offline assertions
compare the interpreter's answer against the legacy conditions transcribed
verbatim from `gmusicbrowser.pl:4675-4687` and executing in the same process**,
so the expected values are produced by legacy code rather than written by hand.
Two guard assertions confirm the comparison discriminates, by requiring that
some cases are skipped and some kept.

The Wayland file additionally checks the real model: section counts and their
contents, one action per code-bearing entry, exactly one disabled action,
firing through `activate_action`, a string code arriving at the frontend, a
stateful action starting from its own `check` callback, a real `PopoverMenu`
built from the model, and that a rebuild replaces the previous actions rather
than accumulating them.

Still true, and excluded from any coverage claim: the **23**
`gmusicbrowser_list.pm` call sites cannot be exercised until `SongList` exists,
and no layout `MenuItem` instance is rendered yet — this entry ports the
mechanism, not the `MB`/`SM`/`BM` containers that would place a menu in a
layout.

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
