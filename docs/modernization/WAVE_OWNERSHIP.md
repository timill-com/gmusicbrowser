# Modernization wave ownership

Status: active

Each work unit has exclusive write ownership until it is released for
integration. Shared contracts are frozen before dependent work starts. Changes
to a frozen contract require an integration review before dependent units use
the revision.

## Wave 1

| Work unit | Exclusive files | Interface state | Integration state |
|---|---|---|---|
| GTK4 binding and smoke runner | `gmusicbrowser_gtk4_binding.pm`, `t/gtk4/00_Binding.t`, `tools/run-gtk4-smoke`, `docs/modernization/BINDING_SPIKE.md` | Binding probe is local to M1 | Integrated; isolated Wayland proof passed |
| Neutral layout parser | `gmusicbrowser_layout_parser.pm`, `t/02_LayoutParser.t`, `t/layouts/parser.layout`, `t/layouts/proof.layout` | Catalog version 1 frozen for Wave 1 | Integrated; bundled layouts parse without errors |
| Frontend contract | `gmusicbrowser_frontend.pm`, `t/03_FrontendContract.t` | Version 1 callback order frozen as `($event,$payload)` | Integrated |
| Legacy frontend adapter | `gmusicbrowser_frontend_legacy.pm`, `t/05_FrontendLegacy.t`, `docs/modernization/FRONTEND_CONTRACT.md` | Command/event bridge frozen for the first slice | Integrated |
| Legacy production wiring | `gmusicbrowser.pl` | Depends on the first-slice frontend and legacy adapter | Integrated; GTK3 smoke passed with recorded warnings |
| GTK4 proof slice | `gmusicbrowser_gtk4.pl`, `gmusicbrowser_gtk4_layout.pm`, `t/04_Gtk4LayoutRenderer.t`, `t/gtk4/10_ProofOfLife.t` | Proof-only renderer surface | Integrated; isolated Wayland proof passed |
| Integration tracking | `MODERNIZATION.md`, `Makefile`, `po/create_pot.pl`, `docs/modernization/INVENTORY.md`, `docs/modernization/PARITY_CHECKLIST.md`, `docs/modernization/TESTING.md`, this file | Records released interfaces and evidence | Active |

The Wave 1 style and integration review passed. The GTK4 binding and
proof-of-life tests passed on a real Wayland connection with privately
extracted packages. The GTK3 path completed an isolated Wayland startup and
shutdown smoke with recorded warnings. No milestone or parity gate advances
until every required row has evidence from the reproducible dependency set.

## Wave 2

| Work unit | Exclusive files | Dependency | State |
|---|---|---|---|
| Lifecycle contract freeze | `gmusicbrowser_frontend.pm`, `t/03_FrontendContract.t`, `docs/modernization/FRONTEND_CONTRACT.md` | Wave 1 frontend/event contract | Complete; lifecycle order frozen |
| Playback command audit | Read-only legacy command and consumer inventory | Wave 1 legacy bridge | Complete; seven-command core allowlist integrated |
| Lifecycle and playback integration | `gmusicbrowser.pl`, `gmusicbrowser_frontend_legacy.pm`, `gmusicbrowser_gtk4.pl`, `t/05_FrontendLegacy.t`, `t/06_LifecycleLegacy.t` | Frozen lifecycle and playback-command audit | Complete; local review complete, required independent review pending |
| Playback-control renderer audit | Read-only legacy and GTK4 widget inventory | Playback command freeze | Complete; renderer work remains unassigned |
| GTK3 monitor work area | `gmusicbrowser_layout.pm`, `t/07_Gtk3Geometry.t`, `docs/modernization/GTK3_BASELINE.md` | Existing layout size and position syntax | In progress |

Playback-control renderer files remain unassigned until the lifecycle and
playback integration review passes. This prevents downstream work from coding
against a moving interface.

## Later waves

File ownership for a later wave is assigned only after its upstream interfaces
are frozen. No work unit may claim a file already owned by another active unit.
Cross-unit changes are returned to the owning unit or made after that ownership
is explicitly released.
