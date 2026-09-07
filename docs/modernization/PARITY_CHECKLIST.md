# GTK4 parity checklist

Status: active inventory

This checklist records GTK4 implementation and verification status. `Rendered`
is not parity: an item reaches `Parity review` only after its saved options,
commands, input, focus, accessibility, failure behaviour, and relevant GTK3
comparison have been exercised. Unsupported behaviour requires an accepted
entry in `DECISIONS.md`.

Statuses used here are **Not started**, **Boundary work**, **GTK4 in progress**,
**Parity review**, **Complete**, and **Exception proposed**.

## Mandatory proof-of-life gate

| Check | Status | Evidence required |
|---|---|---|
| Perl GTK4 binding loads from the pinned dependency set | Boundary work | Binding/version probe |
| `GtkApplication` activates without loading Gtk3 | GTK4 in progress | Local `%INC` assertion and smoke passed |
| Window uses a real Wayland `GdkDisplay` | GTK4 in progress | Local backend assertion passed; X11 fallback fails |
| Neutral layout parser reads the proof layout | GTK4 in progress | Offline parser test passed |
| GTK4 renderer builds `VB`, `HB`, `Label`, `Play`, and `Quit` | GTK4 in progress | Local widget and interaction proof passed |
| Command and state boundary drives the proof widgets | GTK4 in progress | Contract and GUI proof passed |
| 100,000-row modern list/model probe | Boundary work | Timing and memory record |
| Custom drawing/widget probe | Boundary work | Render and lifecycle test |
| Click, motion, scroll, keyboard, menu, and DnD controllers | Boundary work | Interaction results |
| GStreamer bus and GTK4 GLib-loop coexistence | Boundary work | Deterministic bus test |
| Reproducible package contains Perl binding and typelibs | Not started | Clean package build and run |
| GTK3 regression path remains operational | GTK4 in progress | `make test-gtk3` startup/shutdown passed on real Wayland; acceptance warnings remain |

The gate remains open until every row has evidence. A skipped probe does not
advance its status.

## Layout compatibility surface

The following entries are the current built-in `Layout::Widgets` and alias
surface. Numeric suffixes retain the base element's behaviour.

| Elements | GTK4 status |
|---|---|
| `Label`, `Text`, `Play`, `Quit`, `Stop`, `Next`, `Prev`, `Filler` | GTK4 in progress |
| `minwidth=`/`minheight=` on any widget or container | GTK4 in progress |
| Icon options (`icon=`, `stock=`) on the above | GTK4 in progress, see D023/D024 (accepted) |
| `size=`/`relief=` on any button | GTK4 in progress, see D027 (accepted) |
| `xalign=`/`yalign=`/`ellipsize=` on `Label`/`Text` | GTK4 in progress, see D028 (accepted) |
| `font=`/`color=` on `Label`/`Text` | GTK4 in progress, see D031 (accepted) |
| `tip=` tooltip option on the above | GTK4 in progress, literal tips only |
| `AABox`, `AASearch`, `AddLabelEntry`, `Album`, `AlbumBox`, `AlbumSearch`, `Artist`, `ArtistBox`, `ArtistPic`, `ArtistSearch`, `BContext`, `Button`, `Choose`, `ChooseRandAlbum`, `Comment`, `Connections`, `Context`, `Cover`, `Date`, `EditList`, `EditListButtons`, `EmptyList`, `Equalizer`, `EqualizerPresets`, `EqualizerPresetsSimple`, `EventBox`, `FBox`, `FLock`, `FPane`, `Filter`, `FilterBox`, `FilterLock`, `FilterPane`, `Fullscreen`, `HSeparator`, `HistItem`, `LSortItem`, `LabelTime`, `LabelToggleButtons`, `LabelVol`, `LabelsIcons`, `LayoutItem`, `Length`, `Lock`, `LockAlbum`, `LockArtist`, `LockSong`, `MainMenuItem`, `MenuItem`, `OpenBrowser`, `OpenContext`, `OpenQueue`, `PFilterItem`, `PSortItem`, `PictureBrowser`, `PlayFilter`, `PlayItem`, `PlayList`, `PlayOrderCombo`, `PlayingTime`, `Pos`, `Pref`, `Progress`, `ProgressV`, `Queue`, `QueueActions`, `QueueFilter`, `QueueItem`, `QueueList`, `Refresh`, `Repeat`, `ResetFilter`, `Scale`, `SeparatorMenuItem`, `ShuffleList`, `SimpleSearch`, `SongInfo`, `SongList`, `SongSearch`, `SongTree`, `Sort`, `Stars`, `TabbedLists`, `Time`, `TimeBar`, `TimeSlider`, `Title`, `Title_by`, `TogButton`, `ToggleButton`, `Total`, `VProgress`, `VSeparator`, `Visuals`, `Vol`, `VolBar`, `VolSlider`, `Volume`, `VolumeBar`, `VolumeIcon`, `VolumeSlider`, `Year` | Not started |

| Container prefix | Legacy meaning | GTK4 status |
|---|---|---|
| `HB`, `VB` | Horizontal/vertical packing | GTK4 in progress |
| `HP`, `VP` | Horizontal/vertical pane | GTK4 in progress |
| `TB`, `NB` | Legacy/current tabbed container | Not started |
| `MB`, `SM`, `BM` | Menu bar, submenu, button menu | Not started |
| `EB` | Expander | GTK4 in progress |
| `FB` | Fixed-position container | Not started |
| `FR` | Frame | GTK4 in progress |
| `SB` | Scroller | GTK4 in progress |
| `AB` | Alignment wrapper | GTK4 in progress, see D025/D030 (accepted) |
| `WB` | Event wrapper | GTK4 in progress, see D026 (accepted) |
| `@layout` | Embedded layout | Not started |

The containers marked in progress are built by the GTK4 renderer and covered by
`t/04_Gtk4LayoutRenderer.t` against in-process doubles. That proves construction,
option handling, and packing translation only. Pane allocation and saved-size
checks additionally run in `t/gtk4/20_Paned.t`, and box packing geometry in
`t/gtk4/30_Box.t`, both on real Wayland. This does not advance any container to
parity review. `HB`/`VB` translate the legacy packing prefix set (padding
digits, `_` expand, `-` end packing, `.` fill off). Expand, fill, and padding
now act on the packing axis, and `-` reproduces `pack_end` far-edge placement,
with allocated offsets measured against the unchanged GTK3 `BoxPack` on the
same fixture. Homogeneous boxes, `spacing` beyond the legacy 1, size groups,
and `expand_max`-style widget options are not covered.
`HP`/`VP` implement `_` resize, `+` shrink-off, and the `size` option.
Panes expose the legacy `SaveOptions` callback, recording both sides as `N-M`
and restoring `N`, `N-M`, or `N_M`. Coalesced position/bounds notifications
replace `size_allocate`; GTK4 resize properties replace `child_get`. The legacy
resize policy and constrained-restore retry are retained. The GTK4 proof
application still has no configuration writer, so this is a renderer-level
round trip, not persistence across application restarts. Pointer dragging,
physical keyboard input, focus, and accessibility still need comparison.
Icon-bearing options are resolved by name through `GtkIconTheme` per D023, with
the bundled `pix/` directory on the search path. Resolution also falls back to
the `<name>-symbolic` spelling per D024, without which standard names fail on
Adwaita and so do not follow the host theme on stock GNOME.
`t/gtk4/40_Icons.t` covers the
legacy `gtk-*` mapping, bundled icons, alias fallback, the text fallback for
an unresolvable name, and the symbolic fallback against a theme pinned to
Adwaita. `Play`, `Quit`, and the `%Buttons` widgets accept icons. The bundled
layouts contain 103 `icon=` and 17 `stock=` uses; exactly one of those 120
lands on an implemented widget (`Quit1(icon=gmb-turnoff)`), so the rest still
belong to widgets that are not implemented yet. An earlier revision recorded 99
`icon=`; the count on this tree is 103. Icon artwork is unchanged, so this
stays inside D013.

Stateless command buttons are built from a `%Buttons` table in the renderer
that keeps the field names `%Layout::Widgets` uses, so the two can be compared
directly. It holds `Prev`, `Stop`, and `Next`. Only commands the audited bridge
already exposes may be added: a widget whose command is unregistered would
build and then fail on click. The table deliberately omits `click2`/`click3`
secondary mouse actions, because pointer input is not ported and half-wiring
them would be worse than dropping them. `tip=` becomes `set_tooltip_text` with
`\n` unescaped, matching `gmusicbrowser_layout.pm:1207`; song-field tips and
coderef state tips are not handled.

`Next` and `Prev` dispatch `NextSong` and `PrevSong`. Those exist in the core
`%Command` table (`gmusicbrowser.pl:1624-1625`) but were not in the legacy
bridge's audited list, so this increment widened `@Commands` in
`gmusicbrowser_frontend_legacy.pm` — the first shared-boundary change in the
port. Both take no widget argument, which is what makes them safe to expose
through the widget-free bridge; `t/05_FrontendLegacy.t` asserts that the bridge
now refuses to construct when either definition is missing, so a widget can
never be wired to an unregistered command.

The renderer acts on `icon`, `stock`, `text`, `tip`, `size`, and `relief` only.
Every other option a layout supplies to one of these buttons is reported by the
`Unhandled` accessor and left untouched in the parsed catalog, so an ignored
option is recorded rather than silently accepted. What that currently covers:
`nbsongs` and `group`, which in GTK3 only feed the `Prev`/`Next` `click3` song
chooser; a `size=` value outside the mapping in D027;
and `button=0`, which asks for the `EventBox` form rather than a real button
and is used by three `layouts/titlebar.layout` layouts. For scale: the bundled
layouts instantiate `Next` 34 times, `Prev` 29, and `Stop` 20.

Not covered for these three: `click2` and `click3` — `Stop` has
`EnqueueAction(stop)`/`SetNextAction(stop)`, and `Next`/`Prev` open a song
chooser over `GetNextSongs`/`GetPrevSongs($nbsongs)` — plus pointer and
keyboard activation, focus order, and accessibility. Activation is proven by
emitting `clicked`, which is the signal a real click raises, not by
synthesising pointer input. The `group` values also differ from what a reader
might assume: `Next` is `group => 'Next'` but `Prev` is `group => 'Recent'`.

Icon sizes and relief are now implemented, as **D027** (status **Accepted**).
Legacy `Layout::Button` defaults are `relief=>'none'` and `size=>SIZE_BUTTONS`
(`large-toolbar`), which are the default for *every* button widget rather than
rare options, so until this increment every button the renderer built was framed
and theme-sized instead of flat and 24px. GTK4 removed `set_relief` and cut
`GtkIconSize` to `inherit`/`normal`/`large`, so `size=` becomes
`set_pixel_size` on the button's image and `relief=` becomes `set_has_frame`.
The pixel sizes come from `Gtk3::IconSize::lookup` on GTK 3.24.41, so the
translation is lossless: `menu` 16, `button` 16, `small-toolbar` 16,
`large-toolbar` 24, `dnd` 32, `dialog` 48. Those are the whole GTK3 set, and
the five that appear in `layouts/` are `menu` (54), `button` (46),
`large-toolbar` (16), `dialog` (9), and `small-toolbar` (4). `Total(size=small)`
in `layouts/contrib.layout` is a font size on a different widget, not an icon
size, and is outside this mapping.

Still unhandled for buttons: the two-state `stock="on:... off:..."` form. That
form is used only by `LockAlbum`/`LockArtist` (six sites in
`layouts/contrib.layout` and `layouts/shimmer.layout`), and those are
`Layout::Button` with `button => 0` — `GtkEventBox` forms, not buttons — whose
widget-table `stock` is already a hashref keyed by a `state` getter
(`gmusicbrowser_layout.pm:144-155`). Each state's value carries two icons, the
second of which GTK3 shows on `enter_notify_event`. So that form needs state,
the `EventBox` shape, and pointer hover, not just a string parse.
The 28 bundled `gmb-*` names remain app-supplied
artwork and do not follow the host theme; mapping them to freedesktop names is
deferred by D023 alternative 2 and has not been proposed for acceptance.

`ToggleButton` is **not** a `Layout::Button` variant, contrary to what earlier
handoffs recorded. It is `Layout::TogButton`
(`gmusicbrowser_layout.pm:602`, class at `:3805`), a `Gtk3::ToggleButton`
subclass whose entire purpose is showing and hiding *another* layout widget. It
has no `activate` and dispatches no command. It reads `widget`, `togglegroup`,
and `resize`, and drives `::get_layout_widget`, `GetShowHideState`, `ShowHide`,
and `Hide`, plus a `::Watch($self,'HiddenWidgets',...)` subscription.

All **39** `ToggleButton`/`TogButton` option groups in `layouts/` carry
`widget=`. There is not one plain toggle among them. So porting `ToggleButton`
means porting the layout show/hide subsystem first, which is a much larger unit
than a `%Buttons` entry and is not a button increment at all. It reuses
`%Buttons` and `_CreateButton` only for its icon, size, and relief — the parts
D027 now covers.

`Label` and `Text` now apply the legacy `Layout::Label` presentation options,
as **D028** (status **Accepted**). `@default_options` is
`xalign => 0, yalign => .5` (`gmusicbrowser_layout.pm:3105`) while GTK4's own
`Gtk4::Label` default is `.5`, so until this increment every `Label` and `Text`
the renderer built was centred where GTK3 left-aligns it. GTK4 split the
deprecated `set_alignment` into `set_xalign`/`set_yalign`, which take the same
fractional value, so this translation is **lossless** — the contrast with D025,
where `AB` loses a fractional alignment to a three-valued enum. `ellipsize` is
the same Pango enum in both toolkits and passes through unchanged.

One accepted parity exception rides with D028: a label written `ellipsize=1`
now ellipsizes at the end, where GTK3 leaves it un-ellipsized. `Layout::Button`
maps `'1'` to `'end'` (`gmusicbrowser_layout.pm:3051`) and `Layout::Label`
does not (`:3128`); D028 alternative 2 resolves the asymmetry in favour of the
button reading. No bundled layout is affected — all 37 `ellipsize=` uses in
`layouts/` name `end` — so the exception is reachable only from a hand-written
layout.

Two values are filtered because an out-of-range enum is fatal through this
binding: an `ellipsize` outside `none`/`start`/`middle`/`end` once the `'1'`
shorthand is normalised, and a
non-numeric `xalign`/`yalign`, which falls back to the legacy default as GTK3's
own coercion does. Both stay reported through `Unhandled`.

Still unhandled for labels: `markup` (**76** uses), which needs `::UsedFields`
and per-song substitution; `font` and `color`, which GTK4 moved from widget
overrides to CSS; and `minsize`/`expand_max`, which drive the legacy
scrolling-label machinery. Each belongs with a real `Layout::Label` port.
Counting `markup` needs the same care as the widget counts: the bundled layouts
also carry 24 `lmarkup=`, 11 `mmarkup=`, 2 `markup_empty=`, and 2
`init_markup=`, and a bare `grep -o 'markup='` reports 113 by matching inside
the first three. A `[(,]markup=` filter undercounts at 74 because two uses
start a continuation line.
The `Layout::Label` family is `Text`, `Pos`, `Title`, `Title_by`, `Artist`,
`Album`, `Year`, `Comment`, `Length`, `PlayingTime`, `Volume`, `Visuals`, and
`LabelToggleButtons`, with `Label` an alias for `Text`; only `Text`/`Label` is
implemented.

`Filler` is the legacy `Gtk3::HBox->new`, so GTK4 builds it as an empty
`Gtk4::Box`. It carries no options in any bundled layout: all 102 instances are
driven purely by their packing prefix, which `_CreateBox` already translates.
Measured on real Wayland, an expanding `Filler` absorbs 564 of 600px while a
plain one is allocated 0px with its declared padding intact.

The legacy `ApplyCommonOptions` size request is now applied at both of the
call sites GTK3 uses — `gmusicbrowser_layout.pm:1013` for containers and
`:1178` for widgets — so `minwidth=` (52 uses) and `minheight=` (7) reach every
widget and container the renderer builds, not just buttons. The legacy
read-then-merge order is preserved, so a widget that already requested a size
of its own keeps whichever dimension the layout did not name; both toolkits
spell an unset dimension `-1`, which was verified against GTK3 rather than
assumed. `hover_layout`, the other half of `ApplyCommonOptions`, is **not**
ported: it needs a popup window and its own `GdkWindow`.

Still unhandled sizing: `maxwidth=` (44 uses) and `maxheight=` (7). Those are
not general options — in GTK3 they feed `Layout::Label`'s `expand_max`
ellipsize and scrolling behaviour (`gmusicbrowser_layout.pm:3126`, `:3209`),
so they belong with a real `Layout::Label` port rather than with a size
request.

`AB` and `WB` have no direct GTK4 equivalent, because `GtkAlignment` and
`GtkEventBox` were both removed. `AB` becomes alignment properties on its child
(**D025**) and `WB` becomes a plain box (**D026**). Both entries are now
**Accepted**, and both rows stay at `GTK4 in progress`. `AB`'s fractional
bucketing has since been closed by **D030** (see below); what holds its row is
now only the input, focus, accessibility, and saved-profile comparison every
row needs. `WB` still has none of the behaviour it existed to provide.
Acceptance removed the decision gate on each row without advancing it.

`AB` alignment is now covered by real allocations in `t/gtk4/30_Box.t`, which
D025 requires before that row can move: four equally sized expanding `AB` slots
of 150px place their child at x=0, 71, and 142 for `xalign` 0, .5, and 1, while
the default `xscale=1` case fills its slot outright. That is coverage of an
implementation that already existed, not a proof of new behaviour — the same
file passes against the preceding commit.

Legacy `font=` and `color=` on a label are now applied, through a
`GtkCssProvider`, because GTK4 removed the per-widget `modify_font` and
`override_color` those options used (**D031**). Two things about that row are
worth reading before citing it as parity:

- **`font=` is theme-relative, not absolute.** A legacy `font=20` becomes
  `200%` of the desktop font rather than 20 points, so the rendering matches
  GTK3 exactly on a 10pt desktop and deliberately diverges on any other. That
  is an accepted parity exception, taken so the OS font preference reaches the
  widget; measured, `font=20` renders 32px at a 10pt desktop and 51px at 16pt,
  where absolute points stay at 20pt.
- **`color=grey` becomes GTK4's `dim-label` class**, which follows the theme
  and its dark variant instead of pinning a shade. It has no observable
  through this binding, so the grey path is covered as a style class rather
  than as a rendered colour.

`DefaultFont`/`DefaultFontColor`, the layout-wide globals that
`desktop.layout` and `fullscreen.layout` set, are **not** ported. So a `Text`
in `desktop.layout` gets its explicit `color=grey` but not the inherited
`white`. That is D031 alternative 5, deferred as layout-level option
inheritance rather than a widget option.

`AB`'s fractional gap is **closed** as of 2026-09-07. A fractional alignment
or scale now goes through a `Gtk4::ConstraintLayout` reproducing the legacy
arithmetic exactly, measured against `Gtk3::Alignment` on the same fixture:
14 of 15 fractional combinations agree exactly, one differs by 1px from solver
rounding. The integral values every bundled layout uses keep the plain
`halign`/`valign` path, so the common path is untouched. See **D030**, which
supersedes the fractional half of D025. The row still does not advance,
because input, focus, accessibility, and saved-profile comparison against GTK3
are unfinished — the same reasons that apply to every other row.

The paragraph below records what D025 originally blocked the row on, and is
kept because it explains why the row was held; the two losses it names are no
longer outstanding.

What still blocks `AB` from parity is narrower than "approximation": the
translation is **exact for every bundled layout**, because the only alignment
values anywhere in `layouts/` are 0, 0.0, .5, 0.5, and 1 and the only scale
values are 0 and 0.0. It is inexact only for a hand-written layout using a
fractional `xalign`/`yalign`, which bucketizes to start/center/end, or a
fractional `xscale`/`yscale`, which is treated as fill. See D025.

What blocks `WB` is different: no bundled layout uses `WB` at all, and its sole
purpose in GTK3 was to give a widget its own `GdkWindow` so `hover_layout`
would work (`gmusicbrowser_layout.pm:1247`). GTK4 removes that need — a child
can carry its own event controllers — and `hover_layout` is not ported, so `WB`
is currently a shape with none of its behaviour. See D026.

Parser compatibility items are inheritance, empty overrides, continuation
lines, translations, ordered packing prefixes, quoted and nested options,
unknown options, aliases, numeric widget suffixes, source locations, SongTree
columns/groups, default options, size groups, key bindings, `VolumeScroll`, and
saved per-widget options. These are in **Boundary work** until golden comparison
against the GTK3 parser is available.

## Commands

`PlayPause`, `Stop`, `NextSong`, and `PrevSong` are **GTK4 in progress** in the
proof slice. `Play`, `Pause`, `IncVolume`, `DecVolume`, and `TogMute` are
exposed by the audited production bridge but have no GTK4 widget yet. `Quit` is
a frontend lifecycle operation rather than a core command, and is not in
`%Command` at all — which is why `-cmd Quit` cannot script a GTK3 shutdown.
Every other legacy command below is **Not started** for GTK4 routing and
behavioural comparison:

`AddFilesToPlaylist`, `AddToLibrary`, `Browser`, `ChangeDisplay`,
`ChooseSongFromAlbum`, `ClearPlayFilter`, `ClearPlaylist`, `ClearQueue`,
`CloseWindow`, `DeleteSelected`,
`EditSelectedSongsProperties`, `EnqueueAction`, `EnqueueAlbum`,
`EnqueueArtist`, `EnqueueFiles`, `EnqueueSelected`, `Forward`,
`GoToCurrentSong`, `Hide`, `InsertFilesInPlaylist`,
`MenuPlayFilter`, `MenuPlayOrder`, `MenuQueue`, `NextAlbum`, `NextArtist`,
`NextSongInPlaylist`, `OpenContext`, `OpenCustom`, `OpenFiles`,
`OpenPref`, `OpenQueue`, `OpenSearch`, `OpenSongProp`,
`PlayListed`, `PopupCustom`, `PopupTrayTip`,
`PrevSongInPlaylist`, `QueueInsertSelected`, `ReloadLayouts`, `Rewind`,
`RunPerlCode`, `RunShellCmd`, `RunShellCmdOnSelected`, `RunSysCmd`,
`RunSysCmdOnSelected`, `Save`, `Seek`, `SetEqualizer`, `SetFocusOn`,
`SetNextAction`, `SetPlayerLayout`, `SetSongLabel`, `SetSongRating`, `Show`,
`ShowHide`, `ShowHideWidget`, `Shuffle`, `TogAlbumLock`,
`TogArtistLock`, `TogSongLock`, `ToggleFullscreen`,
`ToggleFullscreenLayout`, `ToggleRandom`, `ToggleSongLabel`, and
`UnsetSongLabel`.

Exact names, `Name(arg)` parsing, argument validation, FIFO/command-line use,
layout invocation, plugin invocation, and widget-dependent selection context
are compatibility requirements.

## Preferences

| Page or surface | GTK4 status |
|---|---|
| Library and scan/check controls | Not started |
| Audio, backend, sink, ReplayGain, gapless, and equalizer | Not started |
| Layout selection, reload, fullscreen button, tray layout, and icon theme | Not started |
| Miscellaneous behaviour | Not started |
| Field definitions and custom fields | Not started |
| Plugin discovery, activation, and plugin preference widgets | Not started |
| Keyboard and mouse bindings | Not started |
| Tag writing and tag-reader priority | Not started |
| Per-layout and per-widget saved settings | Boundary work |
| Unknown core and plugin option round trip | Boundary work |

## Interaction and view behaviour

| Behaviour | GTK4 status |
|---|---|
| Programmatic activation and focus in proof controls | GTK4 in progress |
| Pointer and keyboard activation in proof controls | Not started |
| Focus order, default focus, mnemonics, and custom key bindings | Not started |
| Primary, middle, secondary, double click, and configurable mouse actions | Not started |
| Motion, hover layouts, tooltips, and cursor feedback | Not started |
| Discrete and smooth scrolling, including volume and seek | Not started |
| Context, main, queue, filter, sort, and choice menus | Not started |
| Internal song/filter DnD and external file/URI DnD | Not started |
| Selection, multi-selection, restoration, and current-playing indication | Not started |
| Search, filter, sort, edit, reorder, and saved column/group state | Not started |
| Dialog continuation, cancellation, transient parenting, and errors | Not started |
| Accessibility roles, names, states, actions, and keyboard-only use | Not started |
| Fullscreen, popup, tray-tip, desktop, and multi-window lifecycle | Not started |
| Legacy Gnome2 session-manager `die` lifecycle | Exception proposed |
| HiDPI, fractional scaling, dark theme, CSS, fonts, colors, and icons | Not started |

## Bundled layouts

| File/family | GTK4 status |
|---|---|
| `t/layouts/proof.layout` | GTK4 in progress; test-only checkpoint |
| `layouts/main.layout` | Not started |
| `layouts/browser.layout` | Not started |
| `layouts/search.layout` | Not started |
| `layouts/fullscreen.layout` | Not started |
| `layouts/popups.layout` | Not started |
| `layouts/pages.layout` | Not started |
| `layouts/tray.layout` | Not started |
| `layouts/desktop.layout` | Not started |
| `layouts/shimmer.layout` | Not started |
| `layouts/makeitlooklike.layout` | Not started |
| `layouts/contrib.layout` | Not started |
| `layouts/titlebar.layout` | Not started |

Each named layout in these files must eventually have parser output,
construction diagnostics, saved-option round trips, a screenshot comparison,
and an interaction result. File-level status does not imply all layouts in the
file have passed.

## Plugins

| Plugin | GTK4 status | Compatibility note |
|---|---|---|
| Album info | Not started | Text/list/input views |
| AppIndicator | Not started | Replace with StatusNotifierItem; do not port its GTK3 menu |
| Artist info | Not started | Text/list/toolbar views |
| AudioScrobbler | Not started | Service plus preferences/log UI |
| Autosave | Not started | Timer lifecycle and preferences |
| Desktop widgets | Not started | Wayland design required |
| Export | Not started | File service and preferences |
| Fetch cover | Not started | Results, artwork lifecycle, dialogs |
| GNOME media keys | Not started | MPRIS/portal compatibility review |
| Karaoke | Not started | Layout widget and preferences |
| Lullaby | Not started | Timer/actions and preferences |
| Lyrics | Not started | Text interaction and toolbar |
| MPRIS1 | Not started | Retirement requires an accepted decision |
| MPRIS2 | Not started | Maintained default service target |
| Notify | Not started | Notification actions and artwork |
| Now Playing | Not started | Output service and preferences |
| Rip | Not started | Dialogs, commands, resource assumptions |
| Titlebar | Not started | Wayland design or accepted exception required |
| Web context | Not started | WebKitGTK 6 decision and views |

## Playback, storage, and desktop services

| Surface | GTK4 status |
|---|---|
| Playback contract and fake backend | Not started |
| GStreamer URI playback, bus, seek, gapless, ReplayGain, EQ, and errors | Boundary work |
| mpv fallback | Not started |
| mplayer and 123 backend compatibility decision | Not started |
| Local source/URI identity compatibility | Not started |
| Remote source registry, async enumeration, staging, and cache | Not started |
| Offline/partial/source-mismatch scan safety and explicit purge | Not started |
| MPRIS2 | Not started |
| StatusNotifierItem and compact tray player | Not started |
| Plasma tray companion | Not started |
| Notifications | Not started |
| File chooser, URI opening, document, and global-shortcut portals | Not started |
| Application/desktop/D-Bus/Wayland identity | Not started; blocked by D007 |
| GNOME, Ubuntu GNOME, and Plasma acceptance matrices | Not started |

## Regression closure

GTK3/GTK4 comparisons use the same fixture library, isolated configuration,
layout, saved options, theme, size, and action sequence. Required closure areas
are startup/configuration, library and queues, filters/random modes, playback,
tagging, every compatibility layout, keyboard/pointer/focus/menu/DnD,
accessibility, remote-source failures, 100,000-song performance, screenshots,
Wayland, X11, packaging, upgrade, downgrade, and rollback. All are **Not
started** unless a narrower row above says otherwise.
