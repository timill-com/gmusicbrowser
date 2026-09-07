# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

use Test::More;
use File::Spec;
use Storable qw/dclone/;
use lib '.';

plan skip_all => 'Wayland paned test must run through tools/run-gtk4-smoke'
	unless $ENV{GMB_GTK4_SMOKE};

require 'gmusicbrowser_gtk4_binding.pm';
my ($initialized,$reason)=GMB::Gtk4::Binding::try_init();
plan skip_all => $reason unless $initialized;
my $backend=GMB::Gtk4::Binding::backend_probe();
die (($backend->{error} || 'GTK4 display is not Wayland')."\n") unless $backend->{wayland};

require 'gmusicbrowser_frontend.pm';
require 'gmusicbrowser_layout_parser.pm';
require 'gmusicbrowser_gtk4_layout.pm';

ok(!exists $INC{'Gtk3.pm'},'GTK4 pane test does not load Gtk3');

my $fixture=File::Spec->catfile('t','layouts','containers.layout');
my $catalog=Layout::Parser::ParseFiles(files=>[$fixture]);
is(scalar @{$catalog->{diagnostics}},0,'paned fixture parses without diagnostics');

my $frontend=GMB::Frontend->new
( commands=>{PlayPause=>sub { return 1 },Quit=>sub { return 1 }},
  state=>{Playing=>sub { return 0 }},
);

sub _wait_for_window
{	my $window=shift;
	my $until=time+3;
	my $context=Glib::MainContext->default;
	while (time<$until)
	{	while ($context->pending) { $context->iteration(0); }
		return 1 if $window->get_mapped && $window->get_width && $window->get_height;
		select undef,undef,undef,.01;
	}
	return;
}

sub _drain
{	my $context=Glib::MainContext->default;
	while ($context->pending) { $context->iteration(0); }
}

sub _wait_for_max
{	my ($paned,$oldmax)=@_;
	my $until=time+3;
	my $context=Glib::MainContext->default;
	while (time<$until)
	{	while ($context->pending) { $context->iteration(0); }
		return 1 if $paned->get('max-position')>$oldmax;
		select undef,undef,undef,.01;
	}
	return;
}

sub _catalog
{	my ($orientation,$size,$packing)=@_;
	my $copy=dclone($catalog);
	my $layout=$copy->{layouts}{'gtk4 containers'};
	my $node=(grep {$_->{name} eq 'HPmain'} @{$layout->{nodes}})[0];
	$node->{element}=$orientation eq 'vertical' ? 'VP' : 'HP';
	$node->{options}{values}{size}=$size if defined $size;
	if ($packing)
	{	$node->{children}[0]{packing}{raw}=$packing->[0];
		$node->{children}[1]{packing}{raw}=$packing->[1];
	}
	return $copy;
}

sub _render
{	my ($orientation,$size,$packing)=@_;
	my $renderer=Layout::Renderer::Gtk4->new
	( catalog=>_catalog($orientation,$size,$packing),
	  frontend=>$frontend,
	  labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop',next=>'Next Song',prev=>'Recently played songs'},
	);
	my $paned=$renderer->Render('gtk4 containers');
	$paned->set_direction('ltr');
	$renderer->Widget('VBleft')->set_size_request(60,60);
	$renderer->Widget('VBright')->set_size_request(60,60);
	my $window=Gtk4::Window->new;
	$window->set_default_size(480,420);
	$window->set_child($paned);
	$window->present;
	ok(_wait_for_window($window),'GTK4 window mapped before pane assertions');
	return ($renderer,$window,$paned);
}

sub _save
{	my $paned=shift;
	return {$paned->{SaveOptions}->($paned)};
}

sub _destroy
{	my ($renderer,$window)=@_;
	$renderer->Destroy;
	$window->destroy;
	_drain();
}

sub _position_is_saved
{	my ($paned,$name,$fractional)=@_;
	if ($fractional)
	{	cmp_ok(abs($paned->{size1}-$paned->get_position),'<=',1,
			"$name stores the handle position after notification");
		cmp_ok(abs($paned->{size1}+$paned->{size2}-$paned->get('max-position')),'<=',1,
			"$name stores the complete handle range after notification");
	}
	else
	{	is($paned->{size1},$paned->get_position,"$name stores the handle position after notification");
		is($paned->{size2},$paned->get('max-position')-$paned->get_position,
			"$name stores the remaining handle range after notification");
	}
}

for my $case
(	{orientation=>'horizontal',axis=>'width'},
	{orientation=>'vertical',axis=>'height'},
)
{	my ($renderer,$window,$paned)=_render($case->{orientation});
	is($paned->get_orientation,$case->{orientation},"$case->{orientation} paned uses its GTK4 orientation");
	ok($case->{axis} eq 'width' ? $paned->get_width>0 : $paned->get_height>0,
		"$case->{orientation} paned received a real allocation");
	is($paned->get_resize_start_child,1,"$case->{orientation} start packing keeps resize enabled");
	ok(!$paned->get_resize_end_child,"$case->{orientation} end packing keeps resize disabled");

	my $restored=_save($paned);
	like($restored->{size},qr/^\d+-120$/,"$case->{orientation} restored the saved fixed end size");
	my ($saved_position,$saved_end)=split /-/,$restored->{size};
	is($saved_position+$saved_end,$paned->get('max-position'),"$case->{orientation} saved sizes match the allocated handle range");
	_destroy($renderer,$window);

	($renderer,$window,$paned)=_render($case->{orientation},$restored->{size});
	is(_save($paned)->{size},$restored->{size},"$case->{orientation} saved pane size round trips through a new renderer");

	my $maximum=$paned->get('max-position');
	my $position=int($maximum/2);
	$paned->set_position($position);
	_drain();
	_position_is_saved($paned,"$case->{orientation} set_position");
	is(_save($paned)->{size},$paned->get_position.'-'.($maximum-$paned->get_position),"$case->{orientation} set_position updates the saved size");

	$paned->set_position(int($maximum/3));
	_drain();
	my $before=$paned->get_position;
	ok($paned->signal_emit('cycle-handle-focus',0),"$case->{orientation} cycle-handle-focus action is handled");
	$paned->signal_emit('move-handle',$case->{orientation} eq 'horizontal' ? 'step-right' : 'step-down');
	_drain();
	ok($paned->get_position>$before,"$case->{orientation} move-handle keyboard action advances the handle");
	_position_is_saved($paned,"$case->{orientation} move-handle action");
	is(_save($paned)->{size},$paned->get_position.'-'.($maximum-$paned->get_position),
		"$case->{orientation} move-handle action updates the saved size");
	_destroy($renderer,$window);
}

for my $case
(	{name=>'start-only',packing=>['_','+']},
	{name=>'end-only',packing=>['+','_'],position=>200},
	{name=>'both',packing=>['_','_'],half=>1},
	{name=>'neither',packing=>['',''],half=>1},
)
{	my ($renderer,$window,$paned)=_render('horizontal','200-200',$case->{packing});
	is($paned->get_resize_start_child ? 1 : 0,$case->{packing}[0] eq '_' ? 1 : 0,
		"$case->{name} restore has the requested start resize flag");
	is($paned->get_resize_end_child ? 1 : 0,$case->{packing}[1] eq '_' ? 1 : 0,
		"$case->{name} restore has the requested end resize flag");
	my $maximum=$paned->get('max-position');
	my $expected= $case->{name} eq 'start-only' ? $maximum-200
		: $case->{half} ? int($maximum/2) : $case->{position};
	cmp_ok(abs($paned->get_position-$expected),'<=',1,
		"$case->{name} resize policy restores the expected handle position");
	_position_is_saved($paned,"$case->{name} restore");

	$paned->set_position(150);
	_drain();
	_position_is_saved($paned,"$case->{name} manual position before resize");
	my $oldmax=$paned->get('max-position');
	my $oldend=$paned->{size2};
	# set_default_size has no effect once a Wayland window is mapped; the size
	# request is what actually grows the surface
	$window->set_size_request($window->get_width+100,$window->get_height+100);
	ok(_wait_for_max($paned,$oldmax),"$case->{name} pane received a larger allocation");
	my $newmax=$paned->get('max-position');
	$expected= $case->{name} eq 'start-only' ? $newmax-$oldend
		: $case->{name} eq 'end-only' ? 150
		: $newmax*150/$oldmax;
	cmp_ok(abs($paned->get_position-$expected),'<=',1,
		"$case->{name} resize policy preserves the expected split after a window resize");
	_position_is_saved($paned,"$case->{name} window resize",$case->{half});
	_destroy($renderer,$window);
}

done_testing;
