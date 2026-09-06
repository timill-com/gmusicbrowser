# Frontend contract

Status: command dispatch, state events, and lifecycle frozen for the first GTK4
vertical slice

`GMB::Frontend` is the GTK-free boundary shared by the concrete
`GMB::Frontend::Legacy` adapter, the GTK4 frontend, and desktop services. It
does not import Gtk3, Gtk4, GDK, or Wnck. This first contract is deliberately
small. Command spelling, dispatch arguments, event names, payloads, lifecycle
order, and synchronous callback order are frozen.

## Construction and commands

```perl
my $frontend=GMB::Frontend->new
(
	commands => {},
	state => {},
	lifecycle => {},
);
```

`commands` contains command definitions keyed by their exact, case-sensitive
legacy names. A code reference is accepted as a shorthand definition. `state`
contains direct data values or zero-argument provider callbacks. `lifecycle`
may contain `startup`, `activate`, `open`, and `shutdown` callbacks.

Commands may also be registered with:

```perl
$frontend->RegisterCommand
(
	name => 'Seek',
	code => sub { my ($argument,$context)=@_; ... },
);
```

`Dispatch($name,$argument,$context)` invokes the callback as
`($argument,$context)` and returns `{ok=>1,value=>$value}`. Unknown commands,
invalid arguments or contexts, and callback exceptions return
`{ok=>0,error=>$message}`. Context is a hash containing only unblessed scalars,
arrays, and hashes. Blessed objects, code or other references, and cycles are
rejected recursively, so a command never depends on a widget.

`ParseCommand($text)` returns
`{ok=>1,name=>$name,argument=>$argument,command=>$spelling}`. It preserves exact
case and argument text in legacy `Name(arg)` spelling. The historic `Name arg`
form is normalized to `Name(arg)`. Invalid input returns an error result.
`GMB::Frontend::Legacy` exposes the audited widget-independent commands
`Play`, `PlayPause`, `Pause`, `Stop`, `IncVolume`, `DecVolume`, and `TogMute`.
It invokes the existing `%::Command` handler as `(undef,$argument)`. Further
commands require an explicit audit and allowlist addition; the bridge does not
rename commands or reinterpret their arguments. `Quit` belongs to the frontend
lifecycle and is not registered as a core command.

The bridge is constructed by the legacy entry point after its initial state is
available:

```perl
my $legacy=GMB::Frontend::Legacy->new
(
	frontend => $frontend,
	commands => \%::Command,
	watch => \&::Watch,
	unwatch => \&::UnWatch,
	state =>
	{
		Playing => sub {$::TogPlay},
		CurSong => sub {$::SongID},
		Time => sub {$::PlayTime},
		Duration => sub
			{ defined $::SongID ? Songs::Get($::SongID,'length') : undef },
		Vol => \&::GetVol,
		Mute => \&::GetMute,
	},
);
```

`gmusicbrowser.pl` supplies the same getter table to `GMB::Frontend` and the
legacy bridge. This makes initial state and subsequent event payloads agree
without changing the existing GTK3 command or watcher paths.

## State and events

`State($name)` returns the named direct state value or calls its provider. An
unknown state name returns `undef`.

`Subscribe($event,$callback)` returns an opaque token. Event callbacks run
synchronously in subscription order as `($event,$payload_hash)`.
`Unsubscribe($token)` removes that exact subscription. `Emit` accepts a
data-only payload hash and returns the same success/error result shape as
`Dispatch`.

The first vertical slice freezes these events and payloads:

| Event | Payload |
|---|---|
| `Playing` | `{playing=>0|1}` |
| `CurSong` | `{id=>$song_id}`; `id` is `undef` when no song is current |
| `Time` | `{position=>$seconds,duration=>$seconds_or_undef}` |
| `Vol` | `{volume=>$percent,mute=>0|1}` |
| `Quit` | `{}` |

Payloads may gain documented optional keys, but the event name and the meaning
of existing keys are compatibility interfaces. Frontends read initial values
through `State` and then update views from these events.

`GMB::Frontend::Legacy` registers a separate plain hash owner with the existing
`Watch` function for each event. On notification it reads the current values
through injected state getters and calls `Emit` immediately. `Disconnect`
removes exactly those watches and is safe to call more than once. The bridge
does not load `gmusicbrowser.pl` or any GTK module.

## Lifecycle

`Startup`, `Activate`, `Open`, and `Shutdown` each take a data-only hash and
return `{ok=>1,value=>$value}` or `{ok=>0,error=>$message}`. Missing lifecycle
hooks are successful no-ops. The initial data shapes are:

| Method | Data |
|---|---|
| `Startup` | `{profile=>$name}`; `profile` is optional |
| `Activate` | `{reason=>$reason,layout=>$name,hidden=>0|1}`; keys are optional |
| `Open` | `{uris=>[...],disposition=>$name,source=>$source}`; keys are optional |
| `Shutdown` | `{reason=>$reason}`; `reason` is optional |

The normal phase order is `Startup`, one or more `Activate` calls, zero or more
`Open` calls, then `Shutdown`. `Activate` requires a successful `Startup`, and
`Open` and `Shutdown` require a successful `Activate`. Further `Activate` and
`Open` calls may be interleaved while the application is active. A successful
`Startup` or `Shutdown` is idempotent and returns its first value without
running its hook again. A failed hook does not advance the phase and may be
retried. After a successful `Shutdown`, every lifecycle call except an
idempotent `Shutdown` is rejected. Lifecycle data is validated before phase or
idempotence checks.

Unknown lifecycle keys are rejected. Present scalar fields must not contain
references, `hidden` is `0` or `1`, and `uris` is an array of non-empty scalar
URIs. The initial `disposition` and `source` values are validated against the
sets below. Adding a lifecycle field or value therefore requires an explicit
contract revision before downstream use.

A missing hook is a successful no-op and advances the phase. Lifecycle methods
do not synthesize state events. In particular, `Shutdown` does not emit `Quit`.
The shutdown callback owns teardown and emits exactly one `Quit` event at the
application model's compatibility point. This preserves the legacy order in
which playback and saved state are settled before `Quit`, while frontend-loop
cleanup follows it.

For the initial integration, `disposition` uses `playlist`, `enqueue`,
`add-playlist`, `insert-playlist`, or `library`. The legacy adapter maps those
values to the established `OpenFiles`, `EnqueueFiles`, `AddFilesToPlaylist`,
`InsertFilesInPlaylist`, and `AddToLibrary` commands without reinterpreting URI
order or command arguments. `source` records `command-line`, `application`, or
`fifo`. General legacy command strings are dispatched after initial activation;
they are not `Open` calls.

The optional legacy Gnome2 session-manager `die` callback still exits the GTK3
main loop directly. It is a recorded lifecycle exception pending a testable
session-manager fixture; the callback must not be treated as GTK4 lifecycle
parity.
