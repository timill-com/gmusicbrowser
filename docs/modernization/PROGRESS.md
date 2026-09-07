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
| menus (`MenuItem` 99, `SeparatorMenuItem` 30, the `*Item` families) | 206 | interpreter **built** (D038); needs `MB`/`SM`/`BM` to place one in a layout, and command registration (D039) |
| list/model (`FilterPane` 63, `SimpleSearch` 30, `SongList` 22, `SongTree` 19, `QueueList` 17, …) | 173 | model probe **closed**; now D010's remaining half (custom drawing) and the song-field state path |
| song-field labels (`Title` 27, `Album` 26, `Artist` 25, `Total` 26, `Time` 13, …) | 157 | a `FRONTEND_CONTRACT.md` extension, and a fixture song source |
| everything else (`ToggleButton` 35, `Cover` 26, `Sort` 21, `TimeBar` 20, …) | 390 | mostly pointer input and the show/hide subsystem |

**The sequencing lesson so far: M1's exit gate is unmet while M4/M5 widget work
has been proceeding.** That is why input came first, the list model second, and
drawing third. Three probes are still BLOCKED, and **none of them gates a group
in the table above** — they are playback, transfer and packaging concerns
rather than layout ones, which is a change from every previous session:

1. ~~input controllers~~ — **closed**, `t/gtk4/50_Input.t`. It was the correct
   first move because it is the only probe every other group depends on: menus
   open by pointer, lists select by pointer, `ToggleButton` and
   `LockAlbum`/`LockArtist` need click plus hover. It also unblocks the *parity
   ratchet* — `PARITY_CHECKLIST.md` says no row reaches `Parity review` without
   pointer and keyboard evidence, so before this **no widget could ever be
   marked done**, however many rendered.
2. ~~**100k-row `GListModel`/`ListView`**~~ — **closed**,
   `t/gtk4/70_ListModel.t`. The stack carries a library-sized model: 100,000
   rows build in 0.12–0.27s and the factory allocates **205 row widgets for
   100,000 rows**, recycling them on scroll. D010's option 1 is no longer
   speculative. Three binding limits shape any port: `GtkExpression` is
   unmarshallable so the GTK sorters cannot be configured, `CustomSorter`
   receives `undef` items so **sorting happens in Perl** (1.1s at 100k, matching
   how legacy already sorts), and `Gio::ListStore::splice` corrupts the store
   with custom objects so rows must be appended. `CustomFilter` does work.
   **This does not unblock the 173-instance list group on its own** — those
   widgets also need the song-field state path and the per-widget subsystems;
   what it removes is the architectural unknown.
3. ~~**custom drawing**~~ — **closed**, `t/gtk4/80_Drawing.t`. "Compose, do not
   subclass" was the right guess, and the reason is stronger than expected:
   **neither GTK4 drawing path is reachable from Perl.** `GtkDrawingArea`'s
   callback dies on the unregistered `CairoContext` and `GtkSnapshot`'s
   positioning calls die on the graphene types, so a custom-drawn widget cannot
   be written at all. What works is offscreen `Cairo` — the standalone module
   still renders — uploaded as a `Gdk::MemoryTexture` and shown through a
   `Gtk4::Picture`, pixel-exact. That fits `Skin::draw`, which already caches a
   pixbuf per state and paints it rather than drawing live vectors.
4. **drag and drop**, **async finish/error**, **GStreamer loop coexistence** —
   independent of the layout surface; needed for the gate, not for widgets.
   `DragSource` and `DropTarget` both already construct (D006), so drag and drop
   is a behaviour probe rather than a feasibility one.

**The gate on menus is command registration, not the `MenuItem` widget.**
Measured 2026-09-07 by walking the parser catalog for `command=` values. There
are **20 distinct commands** across all bundled widgets and only **six** are
registered in `@Commands` (`gmusicbrowser_frontend_legacy.pm:18`): `PlayPause`,
`Stop`, `NextSong`, `PrevSong`, `IncVolume`, `DecVolume`. Of the 99 `MenuItem`
instances, 69 carry a command and **only 14 of those use a registered one**, so
a naive "port `MenuItem`" delivers 14 working items out of 99. The rest split
into `RunPerlCode` (23, see **D039**), `OpenPref` (9), `Quit` (8, deliberately
outside `%Command` as a lifecycle action), `OpenCustom` (6), `OpenSongProp` (4),
and five more at 1–2 each. Widening `@Commands` is shared code and needs a GTK3
pass. The other 30 `MenuItem` instances are 28 `togglewidget` (needing the
show/hide subsystem) and 2 with neither option.

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
| `make test-gtk4` | 484 TAP = 481 executed + 3 skips | real Wayland; 3 M1 probes still BLOCKED |
| `make test-gtk3` | 1 assertion | startup/shutdown on real Wayland |

Per file for `make test-gtk4`: 18 binding (holding all 3 skips), 4
proof-of-life, 84 pane, 166 box, 74 icon, 27 input, 25 menu, 54 list model,
32 drawing.
Count skips from `prove -v`, never by subtraction, and run the files through
`tools/run-gtk4-smoke`: a bare `prove` without `GMB_GTK4_SMOKE=1` reports
different counts (19 TAP and 6 skips for `00_Binding.t`) because the
Wayland-only assertions skip themselves. Two GTK `Failed to set text ... from markup` warnings are
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

	# command registration: the 20 distinct command= values, and which are
	# registered in @Commands (gmusicbrowser_frontend_legacy.pm:18)
	perl -I. -e 'require "gmusicbrowser_layout_parser.pm";
	  my $c=Layout::Parser::ParseFiles(files=>[glob "layouts/*.layout"]); my %cmd;
	  for my $id (@{$c->{order}}) { my $l=$c->{layouts}{$id};
	    my %own=map {$_->{name}=>1} @{$l->{declarations}};
	    for my $n (@{$l->{nodes}}) { next unless $own{$n->{name}};
	      for my $ch (@{$n->{children}}) {
	        next if $ch->{kind} eq "container_ref";
	        my $v=$ch->{options}{values}||{};
	        $cmd{$v->{command}}++ if defined $v->{command}; } } }
	  printf "%-28s %3d\n",$_,$cmd{$_} for sort {$cmd{$b}<=>$cmd{$a}} keys %cmd;'

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

D001–D039 exist; **30 are Accepted** and **9 are unresolved**. Eight are
pre-existing and none blocks a layout increment, but four of them are gates on
the milestones, so do not read the layout work's cleared backlog as the whole
picture. The ninth, **D039**, is new and is the one to settle before menus:

| | status | what it holds up |
|---|---|---|
| D006 | Open | which GTK4 Perl binding to support — the **M1 gate**. Its evidence section is the accumulated binding-behaviour record every increment reads. |
| D007 | Open | canonical application ID |
| D008 | Open | minimum supported platform versions |
| D010 | Open | SongTree GTK4 rendering architecture — gates the largest widget. **Both halves are now measured**: option 1 performs, and option 2 is *unavailable* because no render node can be emitted. Ready to settle. |
| D009 | Proposed | transitional use of deprecated GTK4 TreeView APIs |
| D011 | Proposed | initial packaging format |
| D012 | Proposed | legacy playback backends |
| D019 | Proposed | remote cache policy |
| D039 | Proposed | how `RunPerlCode` is modernized — gates 23 of the 99 `MenuItem` instances |

D006 and D010 are the two that matter for the port's shape: D006 because the
binding's limits have already made one design impossible (layout vfunc
overrides are silently ignored, which is why `AB` uses a constraint layout),
and D010 because `SongList`/`SongTree` is the biggest remaining widget — though
both its questions are now measured, so it is ready to be settled rather than
probed further.

## Not started at all

Menus (`SM`/`MB`/`BM`, `MenuItem`), tabbed containers (`TB`/`NB`), the fixed
container `FB` (whose prefix now parses, but whose `SFixed` dynamic placement
needs a layout manager — D035), embedded layouts (`@layout`), every list/model widget, SongTree,
drag and drop, the drawing layer used by the SongTree skins, `hover_layout`,
right-to-left packing, configuration persistence for the GTK4 proof
application, and the remaining M1 gate probes (drag and drop, async
finish/error, GStreamer loop coexistence, reproducible packaging).
