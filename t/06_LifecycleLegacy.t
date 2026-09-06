# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

use Test::More;
use lib '.';

BEGIN
{	use_ok('gmusicbrowser_frontend');
	use_ok('gmusicbrowser_frontend_legacy');
}

my %watchers;
sub Watch
{	my ($owner,$event,$callback)=@_;
	push @{$watchers{$event}},$owner;
	$owner->{'WatchUpdate_'.$event}=$callback;
}
sub UnWatch
{	my ($owner,$event)=@_;
	@{$watchers{$event}}=grep $_ ne $owner,@{$watchers{$event}};
	delete $owner->{'WatchUpdate_'.$event};
}
sub HasChanged
{	my ($event,@args)=@_;
	for my $owner (@{$watchers{$event} || []})
	{	my $callback=$owner->{'WatchUpdate_'.$event};
		$callback->($owner,@args) if $callback;
	}
}

my @order;
my @allowed=qw/Play PlayPause Pause Stop IncVolume DecVolume TogMute/;
my %commands=
(	(map {my $name=$_; $name=>[sub {return $name},$name]} @allowed),
	OpenFiles => [sub {push @order,'command:OpenFiles:'.($_[1] || ''); return 'opened'},'Open files'],
	EnqueueFiles => [sub {},'Enqueue files'],
	AddFilesToPlaylist => [sub {},'Add files to playlist'],
	InsertFilesInPlaylist => [sub {},'Insert files in playlist'],
	AddToLibrary => [sub {},'Add to library'],
);
my %state=(Playing=>0,CurSong=>undef,Time=>0,Duration=>undef,Vol=>50,Mute=>0);
my ($frontend,$legacy,$activated);
$frontend=GMB::Frontend->new
(	lifecycle =>
	{	startup => sub
		{	push @order,qw/permanent-watches load-plugins read-options plugin-init read-songs post-read demo volume-mute/;
			$legacy=GMB::Frontend::Legacy->new
			(	frontend => $frontend,
				commands => \%commands,
				watch => \&Watch,
				unwatch => \&UnWatch,
				state => {map {my $name=$_; $name=>sub {$state{$name}}} keys %state},
			);
			push @order,qw/legacy-adapter playpack-init keybindings version icons playback check scan icecast playlist initial-play layouts plugin-start queue-list queue-changed/;
			return 'started';
		},
		activate => sub
		{	if ($activated++) {push @order,'present'; return 'presented';}
			push @order,qw/main-window hide delayed-seek tray/;
			return 'activated';
		},
		open => sub {return $legacy->Open($_[0]);},
		shutdown => sub
		{	push @order,qw/save-play-time stop clear-pending close-tray-tip save-tags/;
			HasChanged('Quit');
			push @order,qw/unlink-fifo main-quit/;
			return 'stopped';
		},
	},
);
my @quit;
$frontend->Subscribe(Quit=>sub {push @quit,$_[0]});

is_deeply($frontend->Startup({profile=>'-test'}),{ok=>1,value=>'started'},'legacy startup runs');
is_deeply($frontend->Startup({profile=>'-ignored'}),{ok=>1,value=>'started'},'legacy startup is idempotent');
is_deeply($frontend->Activate({reason=>'startup'}),{ok=>1,value=>'activated'},'first activation runs');
is_deeply($frontend->Activate({reason=>'application'}),{ok=>1,value=>'presented'},'later activation presents');
is_deeply($frontend->Open({disposition=>'playlist',uris=>['file:///one','file:///two'],source=>'application'}),{ok=>1,value=>'opened'},'Open uses the legacy mapper');
is_deeply($frontend->Shutdown({reason=>'command'}),{ok=>1,value=>'stopped'},'legacy shutdown runs');
is_deeply($frontend->Shutdown({reason=>'again'}),{ok=>1,value=>'stopped'},'legacy shutdown is idempotent');

is_deeply(\@order,
	[ qw/permanent-watches load-plugins read-options plugin-init read-songs post-read demo volume-mute
		legacy-adapter playpack-init keybindings version icons playback check scan icecast playlist initial-play layouts plugin-start queue-list queue-changed
		main-window hide delayed-seek tray present/,
	  'command:OpenFiles:file:///one file:///two',
	  qw/save-play-time stop clear-pending close-tray-tip save-tags unlink-fifo main-quit/,
	],
	'legacy lifecycle preserves startup, activation, Open, and shutdown order');
is_deeply(\@quit,['Quit'],'shutdown emits one legacy Quit event at the saved-state boundary');
is($frontend->Open({disposition=>'playlist',uris=>['file:///late']})->{error},"Lifecycle 'open' called after Shutdown",'Open is rejected after shutdown');

$legacy->Disconnect;
my @gtk=grep m#^(?:Gtk3|Gtk4|Gdk|Wnck)(?:/|\.pm)#,keys %INC;
is_deeply(\@gtk,[],'lifecycle integration test does not load GTK, GDK, or Wnck');

done_testing;
