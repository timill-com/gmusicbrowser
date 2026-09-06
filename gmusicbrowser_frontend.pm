# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

package GMB::Frontend;

use Scalar::Util qw/blessed refaddr/;

sub new
{	my ($class,%args)=@_;
	my $commands= delete $args{commands};
	my $state= delete $args{state};
	my $lifecycle= delete $args{lifecycle};
	die "Unknown frontend option '$_'\n" for sort keys %args;
	$commands||={}; $state||={}; $lifecycle||={};
	die "commands must be a hash reference\n" unless ref $commands eq 'HASH';
	die "state must be a hash reference\n" unless ref $state eq 'HASH';
	die "lifecycle must be a hash reference\n" unless ref $lifecycle eq 'HASH';
	for my $name (sort keys %$lifecycle)
	{	die "Invalid lifecycle hook '$name'\n" unless $name=~m/^(?:startup|activate|open|shutdown)$/ && ref $lifecycle->{$name} eq 'CODE'; }
	my $self= bless
	{ commands	=> {},
	  state		=> $state,
	  lifecycle	=> $lifecycle,
	  lifecycle_phase	=> 'new',
	  lifecycle_value	=> {},
	  subscriptions	=> {},
	  watchers	=> {},
	  nexttoken	=> 1,
	},$class;
	for my $name (sort keys %$commands)
	{	my $def=$commands->{$name};
		if (ref $def eq 'CODE') { $self->RegisterCommand(name=>$name,code=>$def); }
		elsif (ref $def eq 'HASH') { $self->RegisterCommand(%$def,name=>$name); }
		else { die "Invalid command definition '$name'\n"; }
	}
	return $self;
}

sub RegisterCommand
{	my ($self,%args)=@_;
	my ($name,$code)= delete @args{qw/name code/};
	die "Unknown command option '$_'\n" for sort keys %args;
	die "Invalid command name\n" unless defined $name && !ref $name && $name=~m/^\w+$/;
	die "Command '$name' has no callback\n" unless ref $code eq 'CODE';
	$self->{commands}{$name}=$code;
	return 1;
}

sub ParseCommand
{	my ($self,$command)=@_;
	return {ok=>0,error=>'Invalid command spelling'} if !defined $command || ref $command;
	$command="$1($2)" if $command=~m/^(\w+) (.*)$/;
	my ($name,$argument)= $command=~m/^(\w+)(?:\((.*)\))?$/;
	return {ok=>0,error=>'Invalid command spelling'} unless defined $name;
	return {ok=>1,name=>$name,argument=>$argument,command=>$command};
}

sub Dispatch
{	my ($self,$name,$arg,$context)=@_;
	if (defined $name && !ref $name && $name=~m/\(/ && !defined $arg)
	{	my $parsed=$self->ParseCommand($name);
		return $parsed unless $parsed->{ok};
		($name,$arg)=@$parsed{qw/name argument/};
	}
	return {ok=>0,error=>'Invalid command name'} if !defined $name || ref $name || $name!~m/^\w+$/;
	my $code=$self->{commands}{$name};
	return {ok=>0,error=>"Unknown command '$name'"} unless $code;
	return {ok=>0,error=>'Invalid context: must be a hash'} unless ref $context eq 'HASH';
	my $error=_data_error($context,'context',{});
	return {ok=>0,error=>"Invalid context: $error"} if $error;
	my ($value,$callback_error);
	{	local $@; $value=eval { $code->($arg,$context) }; $callback_error=$@; }
	if ($callback_error)
	{	$callback_error=~s/\s+$//;
		return {ok=>0,error=>"Command '$name' failed: $callback_error"};
	}
	return {ok=>1,value=>$value};
}

sub Subscribe
{	my ($self,$event,$callback)=@_;
	die "Invalid event name\n" unless defined $event && !ref $event && length $event;
	die "Invalid event callback\n" unless ref $callback eq 'CODE';
	my $token='subscription:'.$self->{nexttoken}++;
	$self->{subscriptions}{$token}=[$event,$callback];
	push @{$self->{watchers}{$event}},$token;
	return $token;
}

sub Unsubscribe
{	my ($self,$token)=@_;
	return 0 unless defined $token && exists $self->{subscriptions}{$token};
	my $event=$self->{subscriptions}{$token}[0];
	delete $self->{subscriptions}{$token};
	@{$self->{watchers}{$event}}=grep $_ ne $token, @{$self->{watchers}{$event}};
	delete $self->{watchers}{$event} unless @{$self->{watchers}{$event}};
	return 1;
}

sub Emit
{	my ($self,$event,$payload)=@_;
	return {ok=>0,error=>'Invalid event name'} unless defined $event && !ref $event && length $event;
	return {ok=>0,error=>'Invalid event payload: must be a hash'} unless ref $payload eq 'HASH';
	my $error=_data_error($payload,'payload',{});
	return {ok=>0,error=>"Invalid event payload: $error"} if $error;
	my @tokens=@{$self->{watchers}{$event} || []};
	for my $token (@tokens)
	{	my $subscription=$self->{subscriptions}{$token} or next;
		my $callback_error;
		{	local $@; eval { $subscription->[1]->($event,$payload); 1 }; $callback_error=$@; }
		if ($callback_error)
		{	$callback_error=~s/\s+$//;
			return {ok=>0,error=>"Event '$event' failed: $callback_error"};
		}
	}
	return {ok=>1,value=>undef};
}

sub State
{	my ($self,$name)=@_;
	return undef unless defined $name && exists $self->{state}{$name};
	my $value=$self->{state}{$name};
	return ref $value eq 'CODE' ? $value->() : $value;
}

sub Startup
{	return $_[0]->_Lifecycle('startup',$_[1]);
}
sub Activate
{	return $_[0]->_Lifecycle('activate',$_[1]);
}
sub Open
{	return $_[0]->_Lifecycle('open',$_[1]);
}
sub Shutdown
{	return $_[0]->_Lifecycle('shutdown',$_[1]);
}

sub _Lifecycle
{	my ($self,$name,$args)=@_;
	$args={} unless defined $args;
	return {ok=>0,error=>"Invalid $name data: must be a hash"} unless ref $args eq 'HASH';
	my $error=_data_error($args,$name,{});
	return {ok=>0,error=>"Invalid $name data: $error"} if $error;
	$error=_lifecycle_data_error($name,$args);
	return {ok=>0,error=>"Invalid $name data: $error"} if $error;
	my $phase=$self->{lifecycle_phase};
	if ($name eq 'shutdown' && $phase eq 'shutdown')
	{ return {ok=>1,value=>$self->{lifecycle_value}{shutdown}}; }
	return {ok=>0,error=>"Lifecycle '$name' called after Shutdown"} if $phase eq 'shutdown';
	if ($name eq 'startup')
	{ return {ok=>1,value=>$self->{lifecycle_value}{startup}} if $phase ne 'new'; }
	elsif ($name eq 'activate')
	{ return {ok=>0,error=>"Lifecycle 'activate' requires Startup"} if $phase eq 'new'; }
	elsif ($name eq 'open')
	{ return {ok=>0,error=>"Lifecycle 'open' requires Activate"} unless $phase eq 'activate'; }
	elsif ($name eq 'shutdown')
	{ return {ok=>0,error=>"Lifecycle 'shutdown' requires Activate"} unless $phase eq 'activate'; }
	my $code=$self->{lifecycle}{$name};
	my ($value,$callback_error);
	if ($code)
	{	local $@; $value=eval { $code->($args) }; $callback_error=$@; }
	if ($callback_error)
	{	$callback_error=~s/\s+$//;
		return {ok=>0,error=>"Lifecycle '$name' failed: $callback_error"};
	}
	if ($name eq 'startup')
	{	$self->{lifecycle_phase}='startup';
		$self->{lifecycle_value}{startup}=$value;
	}
	elsif ($name eq 'activate') { $self->{lifecycle_phase}='activate'; }
	elsif ($name eq 'shutdown')
	{	$self->{lifecycle_phase}='shutdown';
		$self->{lifecycle_value}{shutdown}=$value;
	}
	return {ok=>1,value=>$value};
}

sub _lifecycle_data_error
{	my ($name,$args)=@_;
	my %allowed=
	( startup	=> {map {$_=>1} qw/profile/},
	  activate	=> {map {$_=>1} qw/reason layout hidden/},
	  open		=> {map {$_=>1} qw/uris disposition source/},
	  shutdown	=> {map {$_=>1} qw/reason/},
	);
	return "unknown key '$_'" for grep !$allowed{$name}{$_}, sort keys %$args;
	for my $key (grep exists $args->{$_}, qw/profile reason layout disposition source/)
	{ return "$key must be a scalar" if defined $args->{$key} && ref $args->{$key}; }
	if (exists $args->{hidden})
	{ return 'hidden must be 0 or 1' if !defined $args->{hidden} || ref $args->{hidden} || $args->{hidden}!~m/^[01]$/; }
	if (exists $args->{uris})
	{	return 'uris must be an array' unless ref $args->{uris} eq 'ARRAY';
		for my $uri (@{$args->{uris}})
		{ return 'uris must contain non-empty scalars' unless defined $uri && !ref $uri && length $uri; }
	}
	if (defined $args->{disposition} && $args->{disposition}!~m/^(?:playlist|enqueue|add-playlist|insert-playlist|library)$/)
	{ return "unknown disposition '$args->{disposition}'"; }
	if (defined $args->{source} && $args->{source}!~m/^(?:command-line|application|fifo)$/)
	{ return "unknown source '$args->{source}'"; }
	return undef;
}

sub _data_error
{	my ($value,$path,$seen)=@_;
	return "blessed value at $path" if blessed($value);
	my $ref=ref $value;
	return undef unless $ref;
	return "unsupported reference at $path" unless $ref eq 'HASH' || $ref eq 'ARRAY';
	my $address=refaddr($value);
	return "cyclic value at $path" if $seen->{$address};
	$seen->{$address}=1;
	my $error;
	if ($ref eq 'HASH')
	{	for my $key (sort keys %$value)
		{	$error=_data_error($value->{$key},$path.'.'.$key,$seen);
			last if $error;
		}
	}
	else
	{	for my $i (0..$#$value)
		{	$error=_data_error($value->[$i],$path.'['.$i.']',$seen);
			last if $error;
		}
	}
	delete $seen->{$address};
	return $error;
}

1
