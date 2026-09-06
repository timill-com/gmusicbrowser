# GTK4 migration inventory

Status: initial inventory

Last measured: September 2026

This is the tracking index for converting the roadmap into implementation
issues. Counts are occurrences of the literal `Gtk3::`; they measure toolkit
coupling, not effort. A module with few references can still be high-risk when
those references depend on X11 or a removed desktop protocol.

Allowed statuses:

- **Not started**
- **Boundary work**
- **GTK3 prepared**
- **GTK4 in progress**
- **Parity review**
- **Complete**
- **Retirement proposed**
- **Retired**

## Primary application modules

| Module | GTK refs | Risk | Intended treatment | Roadmap | Status |
|---|---:|---|---|---|---|
| `gmusicbrowser.pl` | 533 | Critical | Extract lifecycle, actions, state, configuration, dialogs, URI intake, and scanning; retain a small frontend entry point | M2–M6 | Boundary work |
| `gmusicbrowser_list.pm` | 243 | Critical | Split view models from GTK; rebuild SongList, SongTree, filter, mosaic, and cloud views | M2, M5 | Not started |
| `gmusicbrowser_layout.pm` | 225 | Critical | Separate parser/model/registry; implement GTK3 and GTK4 renderers without changing layout syntax | M2–M5 | Not started |
| `gmusicbrowser_tags.pm` | 156 | High | Separate tag operations from editors and filenames; add stream/staging inputs; port editors after common controls | M2, M5, M6 | Not started |
| `gmusicbrowser_songs.pm` | 39 | Critical | Keep song/filter/random logic in core; introduce source/URI identity and availability; move GTK stores/combos into frontends | M2, M5, M6 | Not started |

## Frontend foundation

| Module | Toolkit coupling | Intended treatment | Roadmap | Status |
|---|---|---|---|---|
| `gmusicbrowser_frontend.pm` | None | Frozen first-slice command, state-event, and lifecycle contract | M2 | Boundary work |
| `gmusicbrowser_frontend_legacy.pm` | None | Bridge allowlisted widget-independent legacy commands and state events | M2 | Boundary work |
| `gmusicbrowser_layout_parser.pm` | None | Neutral versioned layout catalog; GTK3 adoption and golden comparison remain | M2 | Boundary work |
| `gmusicbrowser_gtk4_binding.pm` | GTK4 GI | Binding probes and evidence-driven overrides | M1 | GTK4 in progress |
| `gmusicbrowser_gtk4.pl` | GTK4 | Separate application entry point; proof slice only | M1, M4 | GTK4 in progress |
| `gmusicbrowser_gtk4_layout.pm` | GTK4 | Registry/renderer; currently only the proof subset | M1, M4, M5 | GTK4 in progress |

## Playback and metadata modules

| Module | GTK refs | Risk | Intended treatment | Roadmap | Status |
|---|---:|---|---|---|---|
| `gmusicbrowser_gstreamer-1.x.pm` | 2 | Medium | Keep engine; accept URI/staging leases; move preference widgets out; modernize sink policy and test contracts | M2, M6, M7 | Not started |
| `gmusicbrowser_mpv.pm` | 2 | Low | Keep backend during transition; define URI/staging behaviour; move preference widgets out | M2, M6, M7 | Not started |
| `gmusicbrowser_mplayer.pm` | 2 | Low | Isolate preference UI; propose backend retirement after usage review | M2, M7 | Not started |
| `gmusicbrowser_123.pm` | 6 | Low | Isolate preference UI; propose backend retirement after usage review | M2, M7 | Not started |
| `mp3header.pm` | 2 | Low | Move incidental dialog/UI use behind frontend service | M2, M5 | Not started |

## Plugins

| Module | GTK refs | Risk | Intended treatment | Roadmap | Status |
|---|---:|---|---|---|---|
| `plugins/artistinfo.pm` | 44 | High | Port text/list views and toolbar; reassess external information sources separately | M5 | Not started |
| `plugins/desktopwidget.pm` | 40 | High | Define Wayland-compatible scope; remove Wnck/root-window assumptions or propose retirement | M3, M5 | Not started |
| `plugins/webcontext.pm` | 35 | High | Decide WebKitGTK 6 strategy; port controls and embedded browser only after source review | M5 | Not started |
| `plugins/albuminfo.pm` | 34 | Medium | Port text/list views and input controllers | M5 | Not started |
| `plugins/lyrics.pm` | 22 | Medium | Port text interactions and toolbar; keep provider work separate | M5 | Not started |
| `plugins/fetch_cover.pm` | 17 | Medium | Port window, results, actions, and artwork lifecycle | M5 | Not started |
| `plugins/audioscrobbler.pm` | 8 | Low | Port log/preferences UI after shared controls | M5 | Not started |
| `plugins/titlebar.pm` | 6 | High | X11/Wnck behaviour needs a Wayland design or explicit retirement decision | M3, M5 | Not started |
| `plugins/karaoke.pm` | 4 | Low | Port label and preferences through normal widget registry | M4, M5 | Not started |
| `plugins/lullaby.pm` | 4 | Low | Port preferences using shared controls | M4 | Not started |
| `plugins/notify.pm` | 4 | Low | Preserve notification service; move preference UI and artwork conversion to adapters | M5, M7 | Not started |
| `plugins/nowplaying.pm` | 4 | Low | Port preferences; keep output behaviour in core/service layer | M5 | Not started |
| `plugins/export.pm` | 3 | Low | Port preferences and file dialog through shared services | M4, M5 | Not started |
| `plugins/rip.pm` | 3 | Medium | Port preferences/dialogs; review external command assumptions | M5 | Not started |
| `plugins/autosave.pm` | 2 | Low | Port its small preference panel after shared form controls exist | M4 | Not started |
| `plugins/appindicator.pm` | 2 | High | Replace with StatusNotifierItem service; do not port AppIndicator3 GTK menu code | M7 | Not started |
| `plugins/mpris2.pm` | 2 | Medium | Move preference UI out; modernize D-Bus implementation and enable by default | M2, M7 | Not started |

## Cross-cutting API inventory

The initial scan found the following migration groups:

| Group | Measured sites | Principal modules | Planned replacement |
|---|---:|---|---|
| All `Gtk3::` references | 1,444 | All tables above | GTK-free core plus frontend adapters |
| GTK subclasses | 84 classes | Main, list, layout, tags, information plugins | Prefer composition; subclass only with explicit lifecycle tests |
| Input/drawing/drag signals | 126 sites | Main, list, layout, tags | Event controllers, gestures, drag source/drop target, draw/snapshot APIs |
| Legacy data-view family | 168 refs | Main, list, layout, tags, songs | `GListModel`, selection models, ListView, ColumnView, TreeListModel, DropDown |
| Menu/status/eventbox/GDK-window family | 148 refs | Main, layout, list, plugins | Actions/menu models/popovers, controllers, StatusNotifierItem, GdkSurface |
| X11/XID/Wnck/GdkWindow-sensitive lines | 18 lines | Main, layout, titlebar, desktop widget, visuals | Wayland-safe surfaces and desktop services; isolate optional X11 code |
| Custom drawing definitions/connections | 25 sites | Layout and list views | DrawingArea draw functions or snapshot-based widgets |

Counts should be regenerated when M3 begins. Do not use a falling reference
count as the only progress metric; behaviour and acceptance gates remain the
definition of progress.

## Layout and view inventory

### Required compatibility set

- Main/default player layouts.
- Browser and search layouts.
- Queue and saved-list views.
- SongList and SongTree layouts, columns, groups, and skins.
- Fullscreen layout.
- Camel tray icon, wheel-controlled volume, and compact tray player with seek
  and rating. Use an activated GTK4 window as the standard fallback and assess
  a Plasma companion widget for true interactive hover behaviour.
- Preferences and tag editors.

### Compatibility-review set

- Desktop widget layouts.
- Titlebar overlays and root-window-aware behaviour.
- Embedded WebKit context pages.
- GStreamer visualizations requiring native window handles.
- Obsolete tray/XEmbed behaviour.

Items in the second set are not silently dropped. Each needs a Wayland-capable
design or an accepted decision recording the limitation.

## Shared components to build before leaf ports

These components prevent every plugin from inventing a different GTK4
translation:

- Application/window lifecycle service.
- Command/action registry and keyboard shortcut manager.
- Box, grid, pane, tab, scroller, and frame layout adapters.
- Standard labelled entry, spin, check, choice, and file-selection controls.
- Action menu/context menu builder.
- Async alert, file, font, color, and URI services.
- URI-native resource/source registry backed by GIO, with async enumeration,
  capability/access queries, local staging leases, and bounded caches.
- Source availability and committed scan-generation service with mount/source
  identity verification, suspicious-disappearance quarantine, missing-state
  retention, and explicit purge.
- Artwork widget and cache interface.
- Event controller helpers for click, middle-click, context menu, scroll, motion,
  and keyboard activation.
- Drag source/drop target payload adapters for song IDs, filters, and URIs.
- List item factory lifecycle helpers.
- Test helpers for isolated configuration, D-Bus, display, and fake playback.

## Per-module completion checklist

Before changing a row to **Complete**, verify:

- [ ] Non-UI behaviour has core tests.
- [ ] No unintended GTK import remains in core code.
- [ ] Existing configuration and layout options are covered.
- [ ] Commands and state events use shared interfaces.
- [ ] Pointer, keyboard, focus, menu, tooltip, and DnD behaviour is covered.
- [ ] Accessibility roles, names, states, and actions are present.
- [ ] Wayland and X11 smoke tests pass where applicable.
- [ ] Large-library performance has been measured where applicable.
- [ ] GTK3 rollback does not lose settings.
- [ ] Storage operations accept resources instead of assuming POSIX paths; any
  local-only limitation is declared and tested.
- [ ] Offline, access-denied, partial-scan, cancellation, and URI-redaction
  behaviour is covered where the module touches media files.
- [ ] No scan, playback error, or startup check can hard-delete a song record;
  unavailable-source and empty-mountpoint regressions preserve user metadata.
- [ ] Manual differences are documented and linked to an accepted decision.
- [ ] Superseded GTK3 code is removed or has an explicit removal issue.

## Updating this inventory

When work starts on a module:

1. Link the implementation issue in its intended-treatment cell or an adjacent
   note.
2. Change status only when the corresponding milestone gate is met.
3. Add newly discovered compatibility behaviour before changing code.
4. Put architectural exceptions in `DECISIONS.md`.
5. Update counts at milestone boundaries, not after every mechanical edit.
