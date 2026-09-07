# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

use Test::More;
use Scalar::Util qw/refaddr/;
use lib '.';

BEGIN
{	use_ok('gmusicbrowser_frontend');
	use_ok('gmusicbrowser_frontend_legacy');
}

my (%watchers,@unwatched);
sub Watch
{	my ($owner,$event,$callback)=@_;
	push @{$watchers{$event}},$owner;
	$owner->{'WatchUpdate_'.$event}=$callback;
}
sub UnWatch
{	my ($owner,$event)=@_;
	push @unwatched,[$event,refaddr($owner)];
	@{$watchers{$event}}=grep refaddr($_)!=refaddr($owner),@{$watchers{$event}};
	delete $owner->{'WatchUpdate_'.$event};
}
sub HasChanged
{	my ($event,@args)=@_;
	my @owners=@{$watchers{$event} || []};
	for my $owner (@owners)
	{	my $callback=$owner->{'WatchUpdate_'.$event};
		$callback->($owner,@args) if $callback;
	}
}

my (@commands,@opens);
my @allowed=qw/Play PlayPause Pause Stop NextSong PrevSong IncVolume DecVolume TogMute/;
our %Command=
(	(map
	{	my $name=$_;
		$name => [sub { push @commands,[$name,@_]; return lc $name; },$name];
	} @allowed),
	(map
	{	my $name=$_;
		$name => [sub { push @opens,[$name,@_]; return $name; },$name];
	} qw/OpenFiles EnqueueFiles AddFilesToPlaylist InsertFilesInPlaylist AddToLibrary/),
	Quit => [sub { die "Quit command used\n" },'Quit'],
	CloseWindow => [sub { die "widget-dependent command used\n" },'Close Window'],
	NextSongInPlaylist => [sub { die "unlisted core command used\n" },'Next Song In Playlist'],
);
my %state=
(	Playing => 0,
	CurSong => undef,
	Time => 0,
	Duration => undef,
	Vol => 50,
	Mute => 0,
);
my $frontend=GMB::Frontend->new;
my $legacy=GMB::Frontend::Legacy->new
(	frontend => $frontend,
	commands => \%Command,
	watch => \&Watch,
	unwatch => \&UnWatch,
	state => {map {my $name=$_; $name=>sub {$state{$name}}} keys %state},
);

for my $name (@allowed)
{ is_deeply($frontend->Dispatch($name,'legacy argument',{}),{ok=>1,value=>lc $name},"$name is registered"); }
is_deeply(\@commands,[map {[$_,undef,'legacy argument']} @allowed],'allowlisted commands receive an undef widget and exact argument');
is($frontend->Dispatch('Quit',undef,{})->{error},"Unknown command 'Quit'",'Quit is not registered as a legacy core command');
is($frontend->Dispatch('playpause',undef,{})->{error},"Unknown command 'playpause'",'command spelling remains case-sensitive');
is($frontend->Dispatch('CloseWindow',undef,{})->{error},"Unknown command 'CloseWindow'",'widget-dependent command is not registered');

# NextSong and PrevSong are the transport commands the Next and Prev widgets
# dispatch. A missing definition must abort construction rather than leave a
# widget wired to a command that fails on click, so this is what proves the
# bridge requires them rather than merely tolerating them.
for my $missing (qw/NextSong PrevSong Stop/)
{	my %partial=map {$_=>$Command{$_}} grep $_ ne $missing,keys %Command;
	my $ok=eval
	{	GMB::Frontend::Legacy->new
		(	frontend => GMB::Frontend->new,
			commands => \%partial,
			watch => \&Watch,
			unwatch => \&UnWatch,
			state => {map {my $name=$_; $name=>sub {$state{$name}}} keys %state},
		);
		1;
	};
	is($@,"Missing legacy command '$missing'\n","the bridge requires $missing");
	ok(!$ok,"a bridge missing $missing does not construct");
}
# a core command outside the bridge's list stays unreachable, so widening the
# list is a deliberate act rather than a side effect of the core table
is($frontend->Dispatch('NextSongInPlaylist',undef,{})->{error},
	"Unknown command 'NextSongInPlaylist'",'an unlisted core command is not registered');

my @open_cases=
(	[playlist	=> 'OpenFiles'],
	[enqueue	=> 'EnqueueFiles'],
	['add-playlist'	=> 'AddFilesToPlaylist'],
	['insert-playlist' => 'InsertFilesInPlaylist'],
	[library	=> 'AddToLibrary'],
);
for my $case (@open_cases)
{	my ($disposition,$command)=@$case;
	is($legacy->Open({disposition=>$disposition,uris=>['file:///one%20song','sftp://host/two']}),$command,"$disposition maps to $command");
}
is_deeply(\@opens,
	[map {[$_->[1],undef,'file:///one%20song sftp://host/two']} @open_cases],
	'Open preserves URI order and joins established spellings once');
my $opencount=@opens;
for my $bad
(	{},
	{disposition=>'unknown',uris=>['file:///one']},
	{disposition=>'playlist'},
	{disposition=>'playlist',uris=>[]},
	{disposition=>'playlist',uris=>'file:///one'},
	{disposition=>'playlist',uris=>['file:///one',undef]},
	{disposition=>'playlist',uris=>['']},
	{disposition=>'playlist',uris=>[[]]},
)
{	my $ok=eval {$legacy->Open($bad); 1};
	ok(!$ok,'malformed Open data is rejected');
}
is(scalar @opens,$opencount,'rejected Open data does not invoke a handler');

my @events;
$frontend->Subscribe($_=>sub {push @events,[$_[0],{%{$_[1]}}]}) for qw/Playing CurSong Time Vol Quit/;
$state{Playing}=1;
HasChanged(Playing=>'stale positional value');
$state{CurSong}=42;
HasChanged(CurSong=>7);
$state{Time}=12;
$state{Duration}=180;
HasChanged(Time=>1,2);
$state{Vol}=75;
$state{Mute}=1;
HasChanged(Vol=>10,0);
HasChanged(Quit=>'ignored');
is_deeply(\@events,
	[	['Playing',{playing=>1}],
		['CurSong',{id=>42}],
		['Time',{position=>12,duration=>180}],
		['Vol',{volume=>75,mute=>1}],
		['Quit',{}],
	],
	'legacy notifications synchronously emit frozen getter payloads in order');
is(scalar(grep $_->[0] eq 'Quit',@events),1,'legacy Quit event is emitted exactly once');

my @watchevents=qw/Playing CurSong Time Vol Quit/;
my @watchowners=map {$watchers{$_}[0]} @watchevents;
is(scalar(grep ref $_ eq 'HASH',@watchowners),5,'legacy watches use hash owners');
is(scalar(keys %{ {map {refaddr($_)=>1} @watchowners} }),5,'each legacy watch has its own owner');
my $other={};
my $othercalls=0;
Watch($other,Playing=>sub {$othercalls++});
is($legacy->Disconnect,5,'Disconnect removes every registered watch');
is_deeply(\@unwatched,
	[map {[$watchevents[$_],refaddr($watchowners[$_])]} 0..$#watchevents],
	'Disconnect removes the exact registered owners and events');
is($legacy->Disconnect,0,'Disconnect is idempotent');
HasChanged(Playing=>0);
is(scalar @events,5,'disconnected notifications are ignored');
is($othercalls,1,'Disconnect preserves an unrelated legacy watch');

my @gtk=grep m#^(?:Gtk3|Gtk4|Gdk|Wnck)(?:/|\.pm)#,keys %INC;
is_deeply(\@gtk,[],'legacy frontend adapter does not load GTK, GDK, or Wnck');

done_testing;
