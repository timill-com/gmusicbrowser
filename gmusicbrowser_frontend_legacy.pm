# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

package GMB::Frontend::Legacy;

use gmusicbrowser_frontend;

my @Commands=qw/Play PlayPause Pause Stop IncVolume DecVolume TogMute/;
my @Events=qw/Playing CurSong Time Vol Quit/;
my %OpenCommands=
( playlist	=> 'OpenFiles',
  enqueue	=> 'EnqueueFiles',
  'add-playlist'	=> 'AddFilesToPlaylist',
  'insert-playlist' => 'InsertFilesInPlaylist',
  library	=> 'AddToLibrary',
);

sub new
{	my ($class,%args)=@_;
	my ($frontend,$commands,$watch,$unwatch,$state)=delete @args{qw/frontend commands watch unwatch state/};
	die "Unknown legacy frontend option '$_'\n" for sort keys %args;
	die "frontend is required\n" unless $frontend && $frontend->can('RegisterCommand') && $frontend->can('Emit');
	die "commands must be a hash reference\n" unless ref $commands eq 'HASH';
	die "watch must be a code reference\n" unless ref $watch eq 'CODE';
	die "unwatch must be a code reference\n" unless ref $unwatch eq 'CODE';
	die "state must be a hash reference\n" unless ref $state eq 'HASH';
	for my $name (qw/Playing CurSong Time Duration Vol Mute/)
	{	die "Missing state getter '$name'\n" unless ref $state->{$name} eq 'CODE'; }
	my $self=bless
	{ frontend	=> $frontend,
	  commands	=> $commands,
	  watch		=> $watch,
	  unwatch	=> $unwatch,
	  state		=> $state,
	  watches	=> [],
	},$class;
	$self->_RegisterCommands;
	$self->_Connect;
	return $self;
}

sub _RegisterCommands
{	my $self=shift;
	for my $name (@Commands)
	{	my $def=$self->{commands}{$name};
		die "Missing legacy command '$name'\n" unless ref $def eq 'ARRAY' && ref $def->[0] eq 'CODE';
		my $code=$def->[0];
		$self->{frontend}->RegisterCommand(name=>$name,code=>sub { $code->(undef,$_[0]); });
	}
}

sub _Connect
{	my $self=shift;
	for my $event (@Events)
	{	my $owner={};
		my $callback=sub { $self->_Changed($event); };
		$self->{watch}->($owner,$event,$callback);
		push @{$self->{watches}},[$event,$owner];
	}
}

sub _Changed
{	my ($self,$event)=@_;
	my $get=$self->{state};
	my $payload=
		$event eq 'Playing' ? {playing=>!!$get->{Playing}->()} :
		$event eq 'CurSong' ? {id=>$get->{CurSong}->()} :
		$event eq 'Time' ? {position=>$get->{Time}->(),duration=>$get->{Duration}->()} :
		$event eq 'Vol' ? {volume=>$get->{Vol}->(),mute=>!!$get->{Mute}->()} : {};
	return $self->{frontend}->Emit($event,$payload);
}

sub Open
{	my ($self,$data)=@_;
	die "Open data must be a hash reference\n" unless ref $data eq 'HASH';
	my $disposition=$data->{disposition};
	die "Missing Open disposition\n" unless defined $disposition && !ref $disposition;
	my $command=$OpenCommands{$disposition};
	die "Unknown Open disposition '$disposition'\n" unless $command;
	my $uris=$data->{uris};
	die "Open uris must be a non-empty array reference\n" unless ref $uris eq 'ARRAY' && @$uris;
	for my $uri (@$uris)
	{ die "Invalid Open uri\n" unless defined $uri && !ref $uri && length $uri; }
	my $def=$self->{commands}{$command};
	die "Missing legacy command '$command'\n" unless ref $def eq 'ARRAY' && ref $def->[0] eq 'CODE';
	return $def->[0]->(undef,join ' ',@$uris);
}

sub Disconnect
{	my $self=shift;
	my @watches=splice @{$self->{watches}};
	$self->{unwatch}->($_->[1],$_->[0]) for @watches;
	return scalar @watches;
}

1
