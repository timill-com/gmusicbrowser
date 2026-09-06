# GTK3 compatibility baseline

Status: active inventory

GTK3 is a maintained compatibility frontend until the GTK4 parity gate. Its
current behaviour is not assumed correct merely because it starts. GTK2 port
workarounds and incomplete GTK3 adaptations are tracked here and must be fixed
or explicitly retained with evidence.

| Surface | Status | Initial evidence |
|---|---|---|
| Binding overrides and compatibility methods | Audit required | `gmusicbrowser.pl` startup compatibility block |
| Monitor geometry, work areas, positioning, and scaling | In progress | Default window sizing still uses a fixed panel allowance |
| Progress text and custom bar rendering | Gap confirmed | `gmusicbrowser_layout.pm` retains GTK2 rendering notes |
| Theme-derived fonts and colors | Gap confirmed | Album/artist information plugins use fixed fallbacks |
| Stock icons, labels, tool buttons, and icon factories | Gap confirmed | Compatibility shims and direct stock calls remain across core and plugins |
| Tray icon and hover layouts | Gap confirmed | Deprecated `Gtk3::StatusIcon` is still the only GTK3 tray path |
| Menus, file choosers, dialogs, and input widgets | Audit required | GTK2-era assumptions and wording remain in active paths |
| SongList/SongTree drawing and invalidation | Audit required | GTK3-specific redraw workarounds and color fallbacks remain |
| X11-specific visuals, screen APIs, and session handling | Audit required | Wayland-safe fallbacks and lifecycle coverage are incomplete |
| Plugin GTK3 surfaces | Audit required | Album info, artist info, web context, lyrics, and AppIndicator have recorded gaps |
| Installation and dependency documentation | Gap confirmed | `INSTALL` still documents GTK2 and GStreamer 0.10 packages |

Each unit must preserve GTK3 behaviour not implicated by the gap, add focused
tests where practical, and receive the same syntax, diff, and style checks as a
GTK4 porting unit. A GTK3 fix is not evidence of GTK4 parity; both frontends
still require identical-fixture comparison at the relevant parity gate.
