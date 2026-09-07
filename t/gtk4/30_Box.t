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
use lib '.';

plan skip_all => 'Wayland box test must run through tools/run-gtk4-smoke'
	unless $ENV{GMB_GTK4_SMOKE};

require 'gmusicbrowser_gtk4_binding.pm';
my ($initialized,$reason)=GMB::Gtk4::Binding::try_init();
plan skip_all => $reason unless $initialized;
my $backend=GMB::Gtk4::Binding::backend_probe();
die (($backend->{error} || 'GTK4 display is not Wayland')."\n") unless $backend->{wayland};

require 'gmusicbrowser_frontend.pm';
require 'gmusicbrowser_layout_parser.pm';
require 'gmusicbrowser_gtk4_layout.pm';

ok(!exists $INC{'Gtk3.pm'},'GTK4 box test does not load Gtk3');

my $fixture=File::Spec->catfile('t','layouts','packing.layout');
my $catalog=Layout::Parser::ParseFiles(files=>[$fixture]);
is(scalar @{$catalog->{diagnostics}},0,'packing fixture parses without diagnostics');

my $frontend=GMB::Frontend->new
( commands=>{PlayPause=>sub { return 1 },Quit=>sub { return 1 }},
  state=>{Playing=>sub { return 0 }},
);

sub _drain
{	my $context=Glib::MainContext->default;
	while ($context->pending) { $context->iteration(0); }
}

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

my @children=('Label','Text','Text2',map {"Label$_"} 2..11);

my $renderer=Layout::Renderer::Gtk4->new
(	catalog=>$catalog,
	frontend=>$frontend,
	labels=>{play=>'Play',pause=>'Pause',quit=>'Quit'},
);
my $root=$renderer->Render('gtk4 packing');
$root->set_direction('ltr');
# a fixed child size keeps the offsets independent of the theme's font metrics
$renderer->Widget($_)->set_size_request(50,24) for @children;
my $window=Gtk4::Window->new;
$window->set_default_size(600,300);
$window->set_child($root);
$window->present;
ok(_wait_for_window($window),'GTK4 window mapped before box assertions');
_drain();

# Allocated offsets, not just child order: a renderer that merely constructs
# the children cannot satisfy these. compute_bounds and compute_point are
# unusable here because this binding cannot marshal the graphene types they
# return, so offsets come from translate_coordinates.
sub _offset
{	my ($container,$name)=@_;
	my ($ok,$x)=$renderer->Widget($name)->translate_coordinates($container,0,0);
	return $ok ? $x : undef;
}

sub _row
{	my ($box,@names)=@_;
	my $container=$renderer->Widget($box);
	my %offset=map {$_=>_offset($container,$_)} @names;
	return ($container,\%offset,[sort {$offset{$a} <=> $offset{$b}} grep {defined $offset{$_}} @names]);
}

# Reference geometry captured from the unchanged GTK3 BoxPack with the same
# fixture rows, spacing 1, 600px width and a 50x24 request per child:
#   HBmixed        Label 0/50  Text 51/384  Label4 442/50  Label3 499/50  Label2 550/50
#   HBinterleaved  Label6 0/50 Text2 51/396 Label8 448/50  Label7 499/50  Label5 550/50
#   HBfill         Label9 0/271  Label10 382/53  Label11 547/53

# HBmixed= Label _Text -Label2 -Label3 6Label4
{	my @names=qw/Label Text Label2 Label3 Label4/;
	my ($box,$offset,$order)=_row('HBmixed',@names);
	ok(defined $offset->{$_},"HBmixed $_ received a real allocation") for @names;
	is_deeply($order,[qw/Label Text Label4 Label3 Label2/],
		'HBmixed matches the GTK3 order: start children, then end children inwards from the far edge');
	is($offset->{Label},0,'the start-packed child keeps the near edge');
	cmp_ok($renderer->Widget('Text')->get_width,'>',300,'"_" absorbs the free space along the packing axis');
	my $width=$box->get_width;
	is($offset->{Label2}+$renderer->Widget('Label2')->get_width,$width,
		'the first "-" child reaches the far edge, as GTK3 pack_end does');
	is($offset->{Label3}+$renderer->Widget('Label3')->get_width+1,$offset->{Label2},
		'the second "-" child sits directly inside the first, separated by the box spacing');
	cmp_ok($offset->{Label4},'<',$offset->{Label3},'padded start child stays left of the end group');
}

# HBinterleaved= -Label5 Label6 _Text2 -Label7 Label8
{	my @names=qw/Label5 Label6 Text2 Label7 Label8/;
	my ($box,$offset,$order)=_row('HBinterleaved',@names);
	is_deeply($order,[qw/Label6 Text2 Label8 Label7 Label5/],
		'interleaved packing keeps the GTK3 order for both groups');
	is($offset->{Label6},0,'the first start child of an interleaved box keeps the near edge');
	is($offset->{Label5}+$renderer->Widget('Label5')->get_width,$box->get_width,
		'the first "-" child of an interleaved box still reaches the far edge');
	cmp_ok($offset->{Label8},'<',$offset->{Label7},
		'a start child packed after an end child stays inside the end group');
}

# HBfill= _Label9 _.Label10 .Label11
{	my @names=qw/Label9 Label10 Label11/;
	my ($box,$offset,$order)=_row('HBfill',@names);
	is_deeply($order,[qw/Label9 Label10 Label11/],'HBfill keeps its declared order');
	my $filled=$renderer->Widget('Label9');
	my $centred=$renderer->Widget('Label10');
	my $plain=$renderer->Widget('Label11');
	my $natural=$centred->get_width;
	cmp_ok($filled->get_width,'>',$natural*2,'"_" without "." fills the extra space it received');
	is($offset->{Label9},0,'the filling child starts at the near edge');
	# fill off keeps the natural size centred in the space expand handed over
	my $slot_start=$offset->{Label9}+$filled->get_width+1;
	my $slot_end=$offset->{Label11}-1;
	cmp_ok(abs($offset->{Label10}+$natural/2-($slot_start+$slot_end)/2),'<=',3,
		'"_." centres the child in its extra space instead of filling it');
	# "." without "_" receives no extra space, so the child keeps its request
	is($plain->get_width,50,'"." keeps the requested size along the packing axis');
	# fill is a packing-axis property: the cross axis still fills
	is($filled->get_height,$box->get_height,'"_" child fills the cross axis');
	is($centred->get_height,$box->get_height,'"_." child still fills the cross axis');
	is($plain->get_height,$box->get_height,'"." child still fills the cross axis');
}

# numeric packing pads along the packing axis on both sides, never the cross axis
{	my ($box,$offset)=_row('HBmixed',qw/Label3 Label4/);
	my $padded=$renderer->Widget('Label4');
	is($padded->get_height,$box->get_height,'numeric packing does not pad the cross axis');
	is($padded->get_margin_start,6,'numeric packing pads the near packing-axis side');
	is($padded->get_margin_end,6,'numeric packing pads the far packing-axis side');
	is($padded->get_margin_top,0,'numeric packing leaves the cross axis unpadded');
	cmp_ok($offset->{Label4}+$padded->get_width+6,'<=',$offset->{Label3},
		'the padding stays between the padded child and the next one');
}

# a vertical box applies the same rules to the other axis
{	my $vertical=$renderer->Widget('VBroot');
	is($vertical->get_orientation,'vertical','VB uses its GTK4 orientation');
	my $mixed=$renderer->Widget('HBmixed');
	is($mixed->get_width,$vertical->get_width,'a VB child fills the cross axis by default');
	my ($ok,undef,$y)=$mixed->translate_coordinates($vertical,0,0);
	ok($ok && $y==0,'the first VB child keeps the top edge');
}

$renderer->Destroy;
$window->destroy;
_drain();

done_testing;
