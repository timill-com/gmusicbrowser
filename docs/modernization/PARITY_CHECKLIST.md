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
| GTK3 regression path remains operational | GTK4 in progress | Isolated startup/shutdown passed; acceptance warnings remain |

The gate remains open until every row has evidence. A skipped probe does not
advance its status.

## Layout compatibility surface

The following entries are the current built-in `Layout::Widgets` and alias
surface. Numeric suffixes retain the base element's behaviour.

| Elements | GTK4 status |
|---|---|
| `Label`, `Play`, `Quit` | GTK4 in progress |
| `AABox`, `AASearch`, `AddLabelEntry`, `Album`, `AlbumBox`, `AlbumSearch`, `Artist`, `ArtistBox`, `ArtistPic`, `ArtistSearch`, `BContext`, `Button`, `Choose`, `ChooseRandAlbum`, `Comment`, `Connections`, `Context`, `Cover`, `Date`, `EditList`, `EditListButtons`, `EmptyList`, `Equalizer`, `EqualizerPresets`, `EqualizerPresetsSimple`, `EventBox`, `FBox`, `FLock`, `FPane`, `Filler`, `Filter`, `FilterBox`, `FilterLock`, `FilterPane`, `Fullscreen`, `HSeparator`, `HistItem`, `LSortItem`, `LabelTime`, `LabelToggleButtons`, `LabelVol`, `LabelsIcons`, `LayoutItem`, `Length`, `Lock`, `LockAlbum`, `LockArtist`, `LockSong`, `MainMenuItem`, `MenuItem`, `Next`, `OpenBrowser`, `OpenContext`, `OpenQueue`, `PFilterItem`, `PSortItem`, `PictureBrowser`, `PlayFilter`, `PlayItem`, `PlayList`, `PlayOrderCombo`, `PlayingTime`, `Pos`, `Pref`, `Progress`, `ProgressV`, `Queue`, `QueueActions`, `QueueFilter`, `QueueItem`, `QueueList`, `Refresh`, `Repeat`, `ResetFilter`, `Scale`, `SeparatorMenuItem`, `ShuffleList`, `SimpleSearch`, `SongInfo`, `SongList`, `SongSearch`, `SongTree`, `Sort`, `Stars`, `Stop`, `TabbedLists`, `Text`, `Time`, `TimeBar`, `TimeSlider`, `Title`, `Title_by`, `TogButton`, `ToggleButton`, `Total`, `VProgress`, `VSeparator`, `Visuals`, `Vol`, `VolBar`, `VolSlider`, `Volume`, `VolumeBar`, `VolumeIcon`, `VolumeSlider`, `Year` | Not started |

| Container prefix | Legacy meaning | GTK4 status |
|---|---|---|
| `HB`, `VB` | Horizontal/vertical packing | GTK4 in progress |
| `HP`, `VP` | Horizontal/vertical pane | Not started |
| `TB`, `NB` | Legacy/current tabbed container | Not started |
| `MB`, `SM`, `BM` | Menu bar, submenu, button menu | Not started |
| `EB` | Expander | Not started |
| `FB` | Fixed-position container | Not started |
| `FR` | Frame | Not started |
| `SB` | Scroller | Not started |
| `AB` | Alignment wrapper | Not started |
| `WB` | Event wrapper | Not started |
| `@layout` | Embedded layout | Not started |

Parser compatibility items are inheritance, empty overrides, continuation
lines, translations, ordered packing prefixes, quoted and nested options,
unknown options, aliases, numeric widget suffixes, source locations, SongTree
columns/groups, default options, size groups, key bindings, `VolumeScroll`, and
saved per-widget options. These are in **Boundary work** until golden comparison
against the GTK3 parser is available.

## Commands

`PlayPause` is **GTK4 in progress** in the proof slice. `Play`, `Pause`, `Stop`,
`IncVolume`, `DecVolume`, and `TogMute` are exposed by the audited production
bridge but do not yet have GTK4 interaction parity. `Quit` is a frontend
lifecycle operation rather than a core command. Every other legacy command
below is **Not started** for GTK4 routing and behavioural comparison:

`AddFilesToPlaylist`, `AddToLibrary`, `Browser`, `ChangeDisplay`,
`ChooseSongFromAlbum`, `ClearPlayFilter`, `ClearPlaylist`, `ClearQueue`,
`CloseWindow`, `DeleteSelected`,
`EditSelectedSongsProperties`, `EnqueueAction`, `EnqueueAlbum`,
`EnqueueArtist`, `EnqueueFiles`, `EnqueueSelected`, `Forward`,
`GoToCurrentSong`, `Hide`, `InsertFilesInPlaylist`,
`MenuPlayFilter`, `MenuPlayOrder`, `MenuQueue`, `NextAlbum`, `NextArtist`,
`NextSong`, `NextSongInPlaylist`, `OpenContext`, `OpenCustom`, `OpenFiles`,
`OpenPref`, `OpenQueue`, `OpenSearch`, `OpenSongProp`,
`PlayListed`, `PopupCustom`, `PopupTrayTip`, `PrevSong`,
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
