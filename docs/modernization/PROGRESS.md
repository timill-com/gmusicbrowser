# GTK4 port progress

Status: active. Measured on 2026-09-07 at the tip of `gtk4-alpha`.

This is the "where are we overall" view. It is deliberately short and holds
only numbers that were **measured**, with the command or method beside each so
the next session can re-derive rather than trust them. `PARITY_CHECKLIST.md`
holds the per-row detail and `SESSION_HANDOFF.md` the working notes.

**Read this first, then the checklist.** The headline is that the port is an
early spike with a solid layout-container and label-option base, and the
widget surface is the bottleneck.

## The one-paragraph summary

GTK3 remains the complete, working application; nothing has been ported away
from it. The GTK4 side renders 8 of 110 layout element names and 8 of 15
container types, but because the implemented elements are common ones, it
covers **20% of the widget instances** the bundled layouts actually declare.
Most recent increments have gone into *option* coverage on the widgets that do
exist, which is where the silent correctness bugs were. The next structural
step is the song-field state path, which gates almost everything left.

## Coverage, measured

All figures from walking the parser's own catalog over `layouts/*.layout`
(13 files, 0 diagnostics), not from grep. See "Counting" below.

| | done | total | |
|---|---:|---:|---|
| Container types | 8 | 15 | `HB VB HP VP SB FR EB AB WB` |
| Layout element names | 8 | 110 | 95 definitions + 15 aliases |
| Element *definitions* | 7 | 95 | `Label` is an alias of `Text` |
| **Widget instances in bundled layouts** | **235** | **1161** | **20.2%** |
| Layout definitions parsed | 76 | 76 | in 13 files, 0 diagnostics |

The instance figure is the honest measure of usefulness: 7% of element types,
but a fifth of what the shipped layouts actually ask for.

The total was **1163** until D035. `FB` had no packing-prefix branch in the
parser, so each of the two bundled `FB` declarations contributed a phantom
widget named after its coordinates. Two non-widget entries remain in the walk
and are **correct**: `contrib.layout:78` carries two commented-out widgets after
a mid-line `#`, which legacy also parses as unresolvable widget names. See D035.

Implemented elements, by instances declared in the bundled layouts:

| element | instances |
|---|---:|
| `Filler` | 94 |
| `Play` | 36 |
| `Next` | 34 |
| `Prev` | 29 |
| `Stop` | 20 |
| `Quit` | 11 |
| `Text` | 10 |
| `Label` | 1 |

## What is implemented

**Containers** — `HB`/`VB` with the full legacy packing prefix set, `HP`/`VP`
with resize/shrink and saved sizes, and the five single-child forms `SB`, `FR`,
`EB`, `AB`, `WB`. `AB` reproduces `GtkAlignment` exactly, including fractional
values, through a `Gtk4::ConstraintLayout` (D030).

**Widgets** — `Label`, `Text`, `Play`, `Quit`, `Stop`, `Next`, `Prev`,
`Filler`.

**Options**, which is where most recent work went:

| option | mechanism | decision |
|---|---|---|
| `minwidth=` `minheight=` | `set_size_request`, both legacy call sites | — |
| `icon=` `stock=` | themed icon names, `-symbolic` fallback | D023, D024 |
| `size=` `relief=` | `set_pixel_size`, `set_has_frame` | D027 |
| `xalign=` `yalign=` `ellipsize=` | float properties, Pango enum | D028 |
| `font=` `color=` | one `GtkCssProvider`, theme-relative | D031 |
| `DefaultFont` `DefaultFontColor` | inherited through the same provider | D032 |
| static `markup=` | `set_markup`, validated | D033 |
| `HSize` `VSize` | `Gtk4::SizeGroup` | D034 |
| `tip=` | `set_tooltip_text`, literal tips only | — |

Two of those closed whole-class correctness bugs rather than adding features:
`%ButtonDefaults` (`relief=none`, `size=large-toolbar`) and `%LabelDefaults`
(`xalign=0`) are legacy `@default_options`, so **every** button and label the
renderer had already built was wrong until they landed. That pattern — a legacy
`@default_options` value whose GTK4 counterpart differs — has found four of the
last eight increments and is still the highest-value thing to look for.

## The route to a full port, in dependency order

Measured 2026-09-07. The remaining **926** instances cluster into four groups,
and the order below is set by what blocks what, not by size.

| group | instances | blocked on |
|---|---:|---|
| menus (`MenuItem` 99, `SeparatorMenuItem` 30, the `*Item` families) | 206 | interpreter **built** (D038); needs `MB`/`SM`/`BM` to place one in a layout |
| list/model (`FilterPane` 63, `SimpleSearch` 30, `SongList` 22, `SongTree` 19, `QueueList` 17, …) | 173 | the 100k-row `GListModel` probe, and D010 |
| song-field labels (`Title` 27, `Album` 26, `Artist` 25, `Total` 26, `Time` 13, …) | 157 | a `FRONTEND_CONTRACT.md` extension, and a fixture song source |
| everything else (`ToggleButton` 35, `Cover` 26, `Sort` 21, `TimeBar` 20, …) | 390 | mostly pointer input and the show/hide subsystem |

**The sequencing lesson so far: M1's exit gate is unmet while M4/M5 widget work
has been proceeding.** That is why input came first. Four probes are still
BLOCKED, and each gates a group above:

1. ~~input controllers~~ — **closed**, `t/gtk4/50_Input.t`. It was the correct
   first move because it is the only probe every other group depends on: menus
   open by pointer, lists select by pointer, `ToggleButton` and
   `LockAlbum`/`LockArtist` need click plus hover. It also unblocks the *parity
   ratchet* — `PARITY_CHECKLIST.md` says no row reaches `Parity review` without
   pointer and keyboard evidence, so before this **no widget could ever be
   marked done**, however many rendered.
2. **100k-row `GListModel`/`ListView`** — gates the entire 173-instance list
   group and is the largest single unknown left. D010 (SongTree architecture)
   cannot be resolved without it.
3. **custom drawing** — gates the SongTree skin layer. Partly answered already:
   D006 records that layout vfunc overrides are silently ignored, so the answer
   is likely "compose, do not subclass", as `AB` did under D030.
4. **drag and drop**, **async finish/error**, **GStreamer loop coexistence** —
   independent of the layout surface; needed for the gate, not for widgets.

Still needing a **decision from the user**, not just code:

- extending `FRONTEND_CONTRACT.md`, which is frozen for the first slice. It can
  say *which* song is current but cannot resolve an ID to field values. Until
  that is settled the 157-instance label group cannot start.

Settled on 2026-09-07 (**D036**, **D037**, **D038**):

- **Follow the GTK4 and freedesktop standard** for anything the port must
  redesign, but **every bundled layout keeps working** — layout compatibility is
  the harder constraint. `Shimmer Desktop` is the named reference layout.
- **Icons come from the desktop theme**; dark/light becomes a three-state
  in-app preference defaulting to system, implemented through the existing
  display-level CSS provider because libadwaita is absent and theme-name
  switching does not actually change the colours.
- **Menus port the interpreter, not the instances** — a GTK4 `BuildMenu`
  equivalent consuming the same legacy definition arrays.

**`Shimmer Desktop` is the least-covered bundled layout, at 5 of 45 own
instances (11%) against a 20% average** — it uses close to one of everything, so
it is a good final acceptance target and a poor near-term one. It also opens
with widgets hidden (`Window= hidden=...`) and declares `DefaultFocus` and
`KeyBindings`, none of which is ported.

## The bottleneck, and what unblocks it

**The song-field state path is the single gate on most of what remains.** It is
`::UsedFields`, `Songs::Depends`, `::WatchSelID`, `::ReplaceFieldsAndEsc`, and
`markup_empty` for the no-song case (`gmusicbrowser_layout.pm:3178-3183`). What
it unlocks:

- the **54** field-bearing `markup=` uses, the remainder of D033;
- the whole rest of the `Layout::Label` family — 12 definitions, of which only
  `Text` is done. **Every other member carries a `markup` in its own
  widget-table defaults** (`:246-333`): `Title` is `'<b><big>%S</big></b>%V'`,
  `Artist` is `'<b>%a</b>'`. The markup *is* the widget, so none can be built
  without this path.
- once those land, D031's `font=` becomes reachable from a shipped layout for
  the first time, and five of D032's six bundled global uses become reachable.

It crosses the frontend boundary: `%::ReplaceFields` is built at
`gmusicbrowser_songs.pm:1935` from the shared song field definitions. So it
needs a GTK3 pass and is a subsystem port, not one widget.

The next unimplemented elements by instance count, for scale:

| element | instances | note |
|---|---:|---|
| `MenuItem` | 99 | `GMenu`/`PopoverMenu` design change — ask first |
| `FilterPane` | 63 | list/model widget, gated on the M1 `GListModel` probe |
| `ToggleButton` | 35 | needs the layout show/hide subsystem, not a button port |
| `SeparatorMenuItem` | 30 | with `MenuItem` |
| `SimpleSearch` | 30 | list/model widget |
| `Title` `Album` `Artist` | 27 26 25 | the `Layout::Label` family, gated as above |
| `Cover` `Total` | 26 26 | |
| `SongList` | 22 | the big one; D010 covers the architecture |

## Test position

| suite | result | notes |
|---|---|---|
| `make test-modernization` | 548 assertions, 0 skips | offline, in-process doubles |
| `make test-gtk4` | 398 TAP = 393 executed + 5 skips | real Wayland; 4 M1 probes still BLOCKED |
| `make test-gtk3` | 1 assertion | startup/shutdown on real Wayland |

Per file for `make test-gtk4`: 18 binding (holding all 5 skips), 4
proof-of-life, 84 pane, 166 box, 74 icon, 27 input, 25 menu. Count skips from `prove -v`, never
by subtraction. Two GTK `Failed to set text ... from markup` warnings are
expected, one per refused value in `t/layouts/markup.layout`.

**`t/01_ModFileMetadata.t` needs care when reporting.** Earlier documents
recorded it as failing because "the repository ships no samples". The
repository still ships none — `t/samples/` is in `.gitignore` and untracked —
but this working copy has them downloaded, so the file now **passes with 10
real assertions and no skips**. Both statements are true and they are about
different things: the repository state and this checkout's state. It would
still fail on a fresh clone, which is why it stays outside the offline target.
Check `git ls-files t/samples/` before reporting either way.
| `t/01_ModFileMetadata.t` | passes **here only** | 10 assertions; see below |

**No row in `PARITY_CHECKLIST.md` has reached `Parity review`,** and that is
not pedantry. Every increment so far proves construction, options, and
allocation; none has exercised pointer input, keyboard focus, accessibility, or
saved-profile round trips against GTK3 under the same fixture. Those are the
gate, and they are unstarted.

## How to re-derive these figures

Every number above comes from one of these. Re-run them rather than trusting
the table; each has been wrong at least once when taken on trust.

	# element definitions, aliases, and container types
	grep -n 'our %Widgets=' gmusicbrowser_layout.pm        # registry, to :742
	sed -n '/# aliases for previous widget names/,/^  );/p' gmusicbrowser_layout.pm
	grep -n 'our %Boxes=' gmusicbrowser_layout.pm          # 15 container types

	# widget instances, options, and coverage: walk the parser catalog
	perl -I. -e 'require "gmusicbrowser_layout_parser.pm";
	  my $c=Layout::Parser::ParseFiles(files=>[glob "layouts/*.layout"]);
	  for my $id (@{$c->{order}}) { my $l=$c->{layouts}{$id};
	    my %own=map {$_->{name}=>1} @{$l->{declarations}};
	    for my $n (@{$l->{nodes}}) { next unless $own{$n->{name}};
	      for my $ch (@{$n->{children}}) {
	        next if $ch->{kind} eq "container_ref";
	        print "$ch->{element}\n"; } } }' | sort | uniq -c | sort -rn

	# test position
	make test-modernization                                 # offline
	make test-gtk4      # real Wayland, outside the sandbox
	make test-gtk3
	git rev-list --count master..HEAD

## The GTK3 reference count, and its basis

`MODERNIZATION.md` records **1444 `Gtk3::` references across 27 files**. That
reproduces exactly, but only on one basis, and the basis was never written down:

	# 1444 across 27 files - production only
	for f in $(git ls-files '*.pm' '*.pl' | grep -v '^t/' | grep -v gmusicbrowser_gtk4); do
	  grep -o 'Gtk3::' "$f"; done | wc -l

A plain `grep -roh 'Gtk3::' --include=*.pm --include=*.pl . | wc -l` gives
**1448**, because it also counts four references in `t/gtk4/` fixtures and the
GTK4 renderer's comments naming the GTK3 source of truth. Neither figure is
wrong; they answer different questions. State which one you mean.

## Counting

Instance counts have been recorded wrong repeatedly, so state the basis:

- **"own" basis** — widgets declared in that layout's own block. This is the
  figure this document uses.
- **"all" basis** — instances across every layout, so a widget a derived layout
  inherits through `based on` is counted again. Six bundled layouts use
  `based on`, which is why `Next` is 34 own and 36 all.

A raw `grep -o` gives neither. It also matches `HSize`/`VSize` size-group
declarations, which name existing widgets and instantiate nothing, plus
comments, `Name=` prose, and option values. That inflated five recorded
figures; see D034. The reliable method is to walk the parser's catalog.

## Decisions

D001–D038 exist; **30 are Accepted** and **8 are unresolved**. All eight are
pre-existing and none blocks a layout increment, but four of them are gates on
the milestones, so do not read the layout work's cleared backlog as the whole
picture:

| | status | what it holds up |
|---|---|---|
| D006 | Open | which GTK4 Perl binding to support — the **M1 gate**. Its evidence section is the accumulated binding-behaviour record every increment reads. |
| D007 | Open | canonical application ID |
| D008 | Open | minimum supported platform versions |
| D010 | Open | SongTree GTK4 rendering architecture — gates the largest widget |
| D009 | Proposed | transitional use of deprecated GTK4 TreeView APIs |
| D011 | Proposed | initial packaging format |
| D012 | Proposed | legacy playback backends |
| D019 | Proposed | remote cache policy |

D006 and D010 are the two that matter for the port's shape: D006 because the
binding's limits have already made one design impossible (layout vfunc
overrides are silently ignored, which is why `AB` uses a constraint layout),
and D010 because `SongList`/`SongTree` is the biggest remaining widget.

## Not started at all

Menus (`SM`/`MB`/`BM`, `MenuItem`), tabbed containers (`TB`/`NB`), the fixed
container `FB` (whose prefix now parses, but whose `SFixed` dynamic placement
needs a layout manager — D035), embedded layouts (`@layout`), every list/model widget, SongTree,
drag and drop, the drawing layer used by the SongTree skins, `hover_layout`,
right-to-left packing, configuration persistence for the GTK4 proof
application, and the remaining M1 gate probes (100k-row model, custom drawing,
input controllers, GStreamer loop coexistence, reproducible packaging).
