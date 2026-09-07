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
| `Label`, `Play`, `Quit`, `Stop`, `Next`, `Prev` | GTK4 in progress |
| Icon options (`icon=`, `stock=`) on the above | GTK4 in progress, see D023 |
| `tip=` tooltip option on the above | GTK4 in progress, literal tips only |
| `AABox`, `AASearch`, `AddLabelEntry`, `Album`, `AlbumBox`, `AlbumSearch`, `Artist`, `ArtistBox`, `ArtistPic`, `ArtistSearch`, `BContext`, `Button`, `Choose`, `ChooseRandAlbum`, `Comment`, `Connections`, `Context`, `Cover`, `Date`, `EditList`, `EditListButtons`, `EmptyList`, `Equalizer`, `EqualizerPresets`, `EqualizerPresetsSimple`, `EventBox`, `FBox`, `FLock`, `FPane`, `Filler`, `Filter`, `FilterBox`, `FilterLock`, `FilterPane`, `Fullscreen`, `HSeparator`, `HistItem`, `LSortItem`, `LabelTime`, `LabelToggleButtons`, `LabelVol`, `LabelsIcons`, `LayoutItem`, `Length`, `Lock`, `LockAlbum`, `LockArtist`, `LockSong`, `MainMenuItem`, `MenuItem`, `OpenBrowser`, `OpenContext`, `OpenQueue`, `PFilterItem`, `PSortItem`, `PictureBrowser`, `PlayFilter`, `PlayItem`, `PlayList`, `PlayOrderCombo`, `PlayingTime`, `Pos`, `Pref`, `Progress`, `ProgressV`, `Queue`, `QueueActions`, `QueueFilter`, `QueueItem`, `QueueList`, `Refresh`, `Repeat`, `ResetFilter`, `Scale`, `SeparatorMenuItem`, `ShuffleList`, `SimpleSearch`, `SongInfo`, `SongList`, `SongSearch`, `SongTree`, `Sort`, `Stars`, `TabbedLists`, `Text`, `Time`, `TimeBar`, `TimeSlider`, `Title`, `Title_by`, `TogButton`, `ToggleButton`, `Total`, `VProgress`, `VSeparator`, `Visuals`, `Vol`, `VolBar`, `VolSlider`, `Volume`, `VolumeBar`, `VolumeIcon`, `VolumeSlider`, `Year` | Not started |

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
| `AB` | Alignment wrapper | GTK4 in progress |
| `WB` | Event wrapper | GTK4 in progress |
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

The renderer acts on `icon`, `stock`, `text`, and `tip` only. Every other
option a layout supplies to one of these buttons is reported by the new
`Unhandled` accessor and left untouched in the parsed catalog, so an ignored
option is recorded rather than silently accepted. What that currently covers:
`nbsongs` and `group`, which in GTK3 only feed the `Prev`/`Next` `click3` song
chooser; `size` and `relief`, which need the legacy `Layout::Button` defaults;
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

Icon sizes and states are still unhandled: `size=button`, `size=large-toolbar`,
`size=menu`, `relief=none`, and the two-state `stock="on:... off:..."` form used
by `LockAlbum`/`LockArtist`. Note that legacy `Layout::Button` defaults are
`relief=>'none'` and `size=>SIZE_BUTTONS` (`large-toolbar`), so these are the
default for every button widget rather than rare options. The 28 bundled `gmb-*` names remain app-supplied
artwork and do not follow the host theme; mapping them to freedesktop names is
deferred by D023 alternative 2 and has not been proposed for acceptance.

`AB` and `WB` have no direct GTK4 equivalent: `AB` becomes alignment properties
on its child and `WB` becomes a
plain box, both pending an accepted decision entry.

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
