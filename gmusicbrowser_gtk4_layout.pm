# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

package Layout::Renderer::Gtk4;

sub new
{	my ($class,%args)=@_;
	my $catalog=delete $args{catalog};
	my $frontend=delete $args{frontend};
	my $labels=delete $args{labels};
	my $context=delete $args{context} || {window_id=>'MainWindow',group=>'Play',selected_ids=>[]};
	die "Unknown GTK4 layout renderer option '$_'\n" for sort keys %args;
	die "GTK4 layout renderer needs a version 1 catalog\n"
		unless ref $catalog eq 'HASH' && $catalog->{version} && $catalog->{version}==1;
	die "GTK4 layout renderer needs a frontend\n"
		unless ref $frontend && $frontend->can('Dispatch') && $frontend->can('Subscribe');
	die "GTK4 layout renderer needs labels\n"
		unless ref $labels eq 'HASH' && defined $labels->{play} &&
		defined $labels->{pause} && defined $labels->{quit};
	return bless
	{ catalog	=> $catalog,
	  frontend	=> $frontend,
	  labels	=> $labels,
	  context	=> $context,
	  widgets	=> {},
	  subscriptions=> [],
	},$class;
}

sub Render
{	my ($self,$id)=@_;
	my $layout=$self->{catalog}{layouts}{$id}
		or die "Unknown layout '$id'\n";
	die _source($layout).": GTK4 renderer needs exactly one root container\n"
		unless @{$layout->{roots}}==1;
	$self->{layout}=$layout;
	$self->{nodes}={map {$_->{name}=>$_} @{$layout->{nodes}}};
	$self->{stack}={};
	return $self->_CreateContainer($layout->{roots}[0]);
}

sub Widget
{	return $_[0]{widgets}{$_[1]};
}

sub Destroy
{	my $self=shift;
	$self->{frontend}->Unsubscribe($_) for @{$self->{subscriptions}};
	$self->{subscriptions}=[];
	$self->{widgets}={};
}

sub _CreateContainer
{	my ($self,$name)=@_;
	my $node=$self->{nodes}{$name}
		or die _source($self->{layout}).": unknown container '$name'\n";
	die _source($node).": recursive container '$name'\n" if $self->{stack}{$name};
	local $self->{stack}{$name}=1;
	my $orientation= $node->{element} eq 'HB' ? 'horizontal'
		: $node->{element} eq 'VB' ? 'vertical'
		: die _source($node).": GTK4 container '$node->{element}' is not implemented\n";
	my $box=Gtk4::Box->new($orientation,0);
	$self->{widgets}{$name}=$box;
	for my $child (@{$node->{children}})
	{	die _source($child).": GTK4 packing '$child->{packing}{raw}' is not implemented\n"
			if $child->{packing}{raw}=~m/[-.]/;
		my $widget= $child->{kind} eq 'container_ref'
			? $self->_CreateContainer($child->{target})
			: $self->_CreateWidget($child);
		if ($child->{packing}{raw}=~m/_/)
		{	if ($orientation eq 'horizontal') { $widget->set_hexpand(1); }
			else { $widget->set_vexpand(1); }
		}
		$box->append($widget);
	}
	return $box;
}

sub _CreateWidget
{	my ($self,$node)=@_;
	my $element=$node->{element};
	my $widget;
	if ($element eq 'Label' || $element eq 'Text')
	{	my $text=$node->{options}{values}{text};
		$text='' unless defined $text;
		$widget=Gtk4::Label->new($text);
	}
	elsif ($element eq 'Play')
	{	$widget=Gtk4::Button->new_with_label('');
		$self->_SetPlayLabel($widget,$self->{frontend}->State('Playing'));
		$widget->signal_connect(clicked => sub
		{	my $result=$self->{frontend}->Dispatch('PlayPause',undef,$self->{context});
			warn "$result->{error}\n" unless $result->{ok};
		});
		my $token=$self->{frontend}->Subscribe(Playing => sub
		{	my (undef,$payload)=@_;
			$self->_SetPlayLabel($widget,$payload->{playing});
		});
		push @{$self->{subscriptions}},$token;
	}
	elsif ($element eq 'Quit')
	{	$widget=Gtk4::Button->new_with_label($self->{labels}{quit});
		$widget->signal_connect(clicked => sub
		{	my $result=$self->{frontend}->Dispatch('Quit',undef,$self->{context});
			warn "$result->{error}\n" unless $result->{ok};
		});
	}
	else
	{	die _source($node).": GTK4 widget '$element' is not implemented\n"; }
	$self->{widgets}{$node->{name}}=$widget;
	return $widget;
}

sub _SetPlayLabel
{	my ($self,$widget,$playing)=@_;
	$widget->set_label($self->{labels}{$playing ? 'pause' : 'play'});
}

sub _source
{	my $item=shift;
	my $source=$item->{source} || {};
	return ($source->{file} || '<layout>').':'.($source->{line} || 0);
}

1
