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
require 't/RendererLabels.pm';

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
	labels=>GMB::Test::RendererLabels::labels(),
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

# Filler and the legacy ApplyCommonOptions size request, measured as real
# allocations. Construction alone cannot satisfy these: minwidth has to change
# what GTK gives the child.
{	my $sfixture=File::Spec->catfile('t','layouts','sizing.layout');
	my $scatalog=Layout::Parser::ParseFiles(files=>[$sfixture]);
	is(scalar @{$scatalog->{diagnostics}},0,'sizing fixture parses without diagnostics');
	my $srenderer=Layout::Renderer::Gtk4->new
	(	catalog=>$scatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);
	my $sroot=$srenderer->Render('gtk4 sizing');
	$sroot->set_direction('ltr');
	my $swindow=Gtk4::Window->new;
	$swindow->set_default_size(600,300);
	$swindow->set_child($sroot);
	$swindow->present;
	ok(_wait_for_window($swindow),'GTK4 window mapped before sizing assertions');
	_drain();

	# a Filler is an empty box: it draws nothing but occupies real space
	my $filler=$srenderer->Widget('Filler');
	isa_ok($filler,'Gtk4::Box');
	is($filler->get_orientation,'horizontal','Filler is a horizontal box like the legacy one');
	is($filler->get_first_child,undef,'Filler has no child widget');
	cmp_ok($filler->get_width,'>',100,'an expanding Filler absorbs the free space');
	my $plain=$srenderer->Widget('Filler2');
	cmp_ok($plain->get_width,'<=',1,'a Filler with no expand takes no width of its own');
	is($plain->get_margin_start,4,'a padded Filler pads the packing axis');
	is($plain->get_margin_top,0,'Filler padding leaves the cross axis alone');

	# minwidth becomes a real minimum, for a widget with no natural size of its
	# own and for one that has one
	my $sized=$srenderer->Widget('Filler3');
	cmp_ok($sized->get_width,'>=',120,'minwidth gives an empty Filler a real minimum width');
	my $wide=$srenderer->Widget('Label4');
	cmp_ok($wide->get_width,'>=',90,'minwidth widens a label past its natural size');
	cmp_ok($wide->get_height,'>=',30,'minheight raises the same label');
	my $tall=$srenderer->Widget('Label5');
	cmp_ok($tall->get_height,'>=',40,'minheight applies without minwidth');
	# the row must be at least as tall as its tallest declared minimum
	my $row=$srenderer->Widget('HBsized');
	cmp_ok($row->get_height,'>=',40,'a minheight child raises its whole row');
	# The container's own minwidth. Asserting the allocated width would be
	# vacuous, because the 600px window satisfies >=320 with no request at all,
	# and a mapped Wayland window cannot be shrunk under it: set_size_request
	# raises a minimum but never lowers a size the compositor already gave.
	# measure() reports the minimum itself, which is the actual property.
	is_deeply([$sroot->get_size_request],[320,-1],'a container carries its minwidth as a size request');
	my ($rootmin)=$sroot->measure('horizontal',-1);
	cmp_ok($rootmin,'>=',320,'the container measures a minimum width of at least its minwidth');
	my ($fillmin)=$srenderer->Widget('HBfillers')->measure('horizontal',-1);
	cmp_ok($fillmin,'<',320,'a sibling row with no minwidth measures a smaller minimum');
	my ($sizedmin)=$sized->measure('horizontal',-1);
	is($sizedmin,120,'an empty Filler measures exactly the minwidth it was given');

	$srenderer->Destroy;
	$swindow->destroy;
	_drain();
}

# AB alignment as real positions, which D025 requires before an AB row can move
# past 'GTK4 in progress'. GTK4 has no GtkAlignment, so the legacy four numbers
# become halign/valign on the child; only an allocation shows they took effect.
{	my $afixture=File::Spec->catfile('t','layouts','align.layout');
	my $acatalog=Layout::Parser::ParseFiles(files=>[$afixture]);
	is(scalar @{$acatalog->{diagnostics}},0,'align fixture parses without diagnostics');
	my $arenderer=Layout::Renderer::Gtk4->new
	(	catalog=>$acatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);
	my $aroot=$arenderer->Render('gtk4 align');
	$aroot->set_direction('ltr');
	my $awindow=Gtk4::Window->new;
	$awindow->set_default_size(600,120);
	$awindow->set_child($aroot);
	$awindow->present;
	ok(_wait_for_window($awindow),'GTK4 window mapped before alignment assertions');
	_drain();

	# each AB is an expanding sibling, so each gets an equal slot; the child's
	# offset inside its own AB is what the alignment decides
	my %pos;
	for my $case (['ABstart','Label'],['ABcenter','Label2'],['ABend','Label3'],['ABfill','Label4'])
	{	my ($box,$child)=@$case;
		my $b=$arenderer->Widget($box);
		my $c=$arenderer->Widget($child);
		my ($ok,$x)=$c->translate_coordinates($b,0,0);
		$pos{$box}={ok=>$ok, x=>$x, slot=>$b->get_width, child=>$c->get_width};
		ok($ok,"$box child received a real allocation");
	}
	cmp_ok($pos{ABstart}{slot},'>',$pos{ABstart}{child}*2,
		'an expanding AB slot is wider than its child, so alignment is observable');
	is($pos{ABstart}{x},0,'xalign=0 with xscale=0 puts the child at the near edge');
	is($pos{ABend}{x}+$pos{ABend}{child},$pos{ABend}{slot},
		'xalign=1 with xscale=0 puts the child at the far edge');
	cmp_ok(abs($pos{ABcenter}{x}+$pos{ABcenter}{child}/2-$pos{ABcenter}{slot}/2),'<=',1,
		'xalign=.5 with xscale=0 centres the child in its slot');
	# the default xscale=1 fills instead of aligning, so the child spans the slot
	is($pos{ABfill}{child},$pos{ABfill}{slot},
		'an AB with the default xscale=1 fills its slot rather than aligning');
	is($pos{ABfill}{x},0,'a filling AB child starts at the near edge');
	# the three aligned children must actually differ, or the assertions above
	# could all be satisfied by one accidental position
	isnt($pos{ABstart}{x},$pos{ABend}{x},'start and end alignment differ');
	isnt($pos{ABcenter}{x},$pos{ABend}{x},'centre and end alignment differ');

	# A fractional xalign or xscale has no halign/valign enum to land on, so
	# these go through a Gtk4::ConstraintLayout instead (D025 alternative 4).
	# The legacy arithmetic is size = scale*slot + (1-scale)*minimum and
	# pos = align*(slot-size), and it was measured to agree with
	# Gtk3::Alignment on this same fixture shape.
	my %frac;
	for my $case (['ABfrac','Label5'],['ABscale','Label6'],['ABboth','Label7'],['ABbad','Label8'])
	{	my ($box,$child)=@$case;
		my $b=$arenderer->Widget($box);
		my $c=$arenderer->Widget($child);
		my ($ok,$x)=$c->translate_coordinates($b,0,0);
		my ($min)=$c->measure('horizontal',-1);
		$frac{$box}={ok=>$ok, x=>$x, slot=>$b->get_width, child=>$c->get_width, min=>$min};
		ok($ok,"$box child received a real allocation");
	}
	# every fractional label carries identical text, so only the option can
	# move the geometry; a differing string would measure the string
	for my $box (qw/ABfrac ABscale ABboth/)
	{	cmp_ok($frac{$box}{slot},'>',$frac{$box}{min}*2,
			"$box has slack for the fraction to act on");
	}
	# xscale=0 keeps the natural size, so the child sits 30% across the slack
	is($frac{ABfrac}{child},$frac{ABfrac}{min},
		'a fractional xalign with xscale=0 leaves the child at its natural size');
	cmp_ok(abs($frac{ABfrac}{x}-0.3*($frac{ABfrac}{slot}-$frac{ABfrac}{min})),'<=',1,
		'xalign=0.3 places the child 30% across the slack, not bucketed to start');
	# pristine buckets 0.3 to 'center' (its threshold is <=.25 for start), so
	# "not at the near edge" would pass there; being off-centre is the fact
	# that discriminates
	cmp_ok(abs($frac{ABfrac}{x}+$frac{ABfrac}{child}/2-$frac{ABfrac}{slot}/2),'>',2,
		'xalign=0.3 is neither bucketed to start nor to center');
	# xscale=0.5 takes half the slack as extra size, at the near edge
	cmp_ok(abs($frac{ABscale}{child}
		-($frac{ABscale}{min}+0.5*($frac{ABscale}{slot}-$frac{ABscale}{min}))),'<=',1,
		'xscale=0.5 gives the child half the slack, not a full fill');
	cmp_ok($frac{ABscale}{child},'<',$frac{ABscale}{slot},
		'a fractional xscale does not fill the whole slot');
	is($frac{ABscale}{x},0,'xscale=0.5 with xalign=0 starts at the near edge');
	# both fractional at once
	cmp_ok(abs($frac{ABboth}{child}
		-($frac{ABboth}{min}+0.5*($frac{ABboth}{slot}-$frac{ABboth}{min}))),'<=',1,
		'a fractional xscale still sizes correctly beside a fractional xalign');
	# a renderer that fills the slot leaves no slack, making the 70% target 0
	# and any x=0 pass; require the slack first so this turns on the option
	cmp_ok($frac{ABboth}{slot}-$frac{ABboth}{child},'>',4,
		'a fractional xscale leaves slack for the alignment to act on');
	cmp_ok(abs($frac{ABboth}{x}-0.7*($frac{ABboth}{slot}-$frac{ABboth}{child})),'<=',1,
		'xalign=0.7 places the child 70% across the remaining slack');
	cmp_ok($frac{ABboth}{x},'>',4,
		'a fractional xalign beside a fractional xscale is not left at the edge');
	# control: a non-numeric alignment falls back to the legacy default, which
	# is the integral xalign=.5 path, so this must pass on both trees
	cmp_ok(abs($frac{ABbad}{x}+$frac{ABbad}{child}/2-$frac{ABbad}{slot}/2),'<=',1,
		'a non-numeric xalign falls back to the centred legacy default');
	# the constraint path is used only where an enum cannot express the value,
	# so the integral cases keep the plain box layout they had before
	for my $box (qw/ABfrac ABscale ABboth/)
	{	isa_ok($arenderer->Widget($box)->get_layout_manager,'Gtk4::ConstraintLayout',
			"$box uses a constraint layout");
	}
	for my $box (qw/ABstart ABcenter ABend ABfill ABbad/)
	{	my $lm=$arenderer->Widget($box)->get_layout_manager;
		isnt(ref $lm,'Gtk4::ConstraintLayout',
			"$box keeps the plain box layout, so the common path does not regress");
	}

	$arenderer->Destroy;
	$awindow->destroy;
	_drain();
}

# Layout::Label xalign/yalign and ellipsize as real rendering, not property
# read-back. @default_options is (xalign=>0, yalign=>.5), while GTK4's own Label
# default is centred, so a Label built without this is misaligned.
{	my $lfixture=File::Spec->catfile('t','layouts','labels.layout');
	my $lcatalog=Layout::Parser::ParseFiles(files=>[$lfixture]);
	is(scalar @{$lcatalog->{diagnostics}},0,'labels fixture parses without diagnostics');
	my $lrenderer=Layout::Renderer::Gtk4->new
	(	catalog=>$lcatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);
	my $lroot=$lrenderer->Render('gtk4 labels');
	$lroot->set_direction('ltr');
	my $lwindow=Gtk4::Window->new;
	$lwindow->set_default_size(400,300);
	$lwindow->set_child($lroot);
	$lwindow->present;
	ok(_wait_for_window($lwindow),'GTK4 window mapped before label assertions');

	# get_layout_offsets is where the text actually lands, so it shows the
	# alignment took effect rather than merely being stored on the widget
	# the labels must be wider than their text before alignment moves anything
	$lrenderer->Widget($_)->set_size_request(200,-1) for qw/Label Label2 Label3 Label4/;
	_drain();
	my %off;
	for my $name (qw/Label Label2 Label3 Label4/)
	{	my $w=$lrenderer->Widget($name);
		my ($x,$y)=$w->get_layout_offsets;
		$off{$name}={x=>$x, width=>$w->get_width};
	}
	# All four carry identical text, so a difference in offset can only come
	# from the alignment. With differing text the centred offsets differ by a
	# few pixels on their own and every comparison here passes vacuously.
	cmp_ok($off{Label2}{width},'>',40,'the label slot is wide enough for alignment to be observable');
	is($off{Label2}{x},0,'xalign=0 renders its text at the near edge');
	cmp_ok($off{Label4}{x},'>',$off{Label3}{x},'xalign=1 renders further right than xalign=.5');
	cmp_ok($off{Label3}{x},'>',$off{Label2}{x},'xalign=.5 renders further right than xalign=0');
	cmp_ok(abs($off{Label3}{x}*2-$off{Label4}{x}),'<=',1,
		'xalign=.5 renders at half the xalign=1 offset');
	# the legacy default must match xalign=0, not GTK4's centred default
	is($off{Label}{x},$off{Label2}{x},
		'a Label with no xalign renders where xalign=0 does, not centred');
	cmp_ok($off{Label3}{x}-$off{Label}{x},'>',10,
		'the legacy default is far from centred, not merely unequal to it');

	# ellipsize=end lets the label shrink below its own text width; that reduced
	# minimum is the real effect. Both labels carry identical text so the
	# comparison isolates the option rather than measuring two different strings.
	my ($cmin)=$lrenderer->Widget('Text')->measure('horizontal',-1);
	my ($kmin)=$lrenderer->Widget('Text2')->measure('horizontal',-1);
	cmp_ok($cmin,'<',$kmin,'ellipsize=end lowers the minimum width below the un-ellipsized one');
	# D028 normalises ellipsize=1 to 'end'. Text3 carries the same text as both
	# labels above, so matching Text's lowered minimum is the physical effect
	# rather than a property read-back; against an un-normalised renderer it
	# measures the full text width like Text2.
	my ($nmin)=$lrenderer->Widget('Text3')->measure('horizontal',-1);
	is($nmin,$cmin,'ellipsize=1 lowers the minimum width exactly as ellipsize=end does');
	cmp_ok($nmin,'<',$kmin,'ellipsize=1 is normalised rather than left un-ellipsized');
	is($lrenderer->Widget('Text3')->get_ellipsize,'end','ellipsize=1 is normalised to end');
	# an out-of-range ellipsize would be a fatal enum error through this binding,
	# so reaching this line at all proves it was filtered rather than passed on
	is($lrenderer->Widget('Text5')->get_ellipsize,'none','an out-of-range ellipsize is left at the default');
	is_deeply($lrenderer->Unhandled('Text5'),['ellipsize'],'an out-of-range ellipsize is reported');

	$lrenderer->Destroy;
	$lwindow->destroy;
	_drain();
}

# Legacy font=/color= as real rendering. GTK4 removed the per-widget font and
# colour overrides Layout::Label used, so both go through a CSS provider (D031).
# font= is a physical measurement; a colour is not, so it is read back from the
# style context instead.
{	my $sfixture=File::Spec->catfile('t','layouts','styling.layout');
	my $scatalog=Layout::Parser::ParseFiles(files=>[$sfixture]);
	is(scalar @{$scatalog->{diagnostics}},0,'styling fixture parses without diagnostics');
	my $srenderer2=Layout::Renderer::Gtk4->new
	(	catalog=>$scatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);
	my $sroot=$srenderer2->Render('gtk4 styling');
	$sroot->set_direction('ltr');
	my $swindow2=Gtk4::Window->new;
	$swindow2->set_default_size(700,300);
	$swindow2->set_child($sroot);
	$swindow2->present;
	ok(_wait_for_window($swindow2),'GTK4 window mapped before styling assertions');
	_drain();

	# every styling label carries the identical text 'Wg', so only the option
	# can change the measurement
	my %h=map {($_=>($srenderer2->Widget($_)->measure('vertical',-1))[0])}
		qw/Text Text2 Text3 Text4/;
	# the theme default is the baseline: font= is a ratio against 10pt, so a
	# font=20 is 200% and must measure well above the unstyled label
	cmp_ok($h{Text2},'>',$h{Text},'font=20 renders larger than the theme default');
	cmp_ok($h{Text3},'<',$h{Text},'font=8 renders smaller than the theme default');
	cmp_ok($h{Text2},'>',$h{Text3}*2,'font=20 is more than twice font=8');
	# the class is the mechanism, and it is a fixed ratio rather than an
	# absolute point size, which is what lets the desktop font through
	ok($srenderer2->Widget('Text2')->has_css_class('gmb-font-200'),
		'font=20 becomes a 200% ratio of the theme font, not an absolute size');
	ok($srenderer2->Widget('Text3')->has_css_class('gmb-font-80'),
		'font=8 becomes an 80% ratio');
	# control: an unstyled label gets no font class at all, and a value with no
	# size in it is refused rather than guessed
	ok(!grep(m/^gmb-font-/,@{$srenderer2->Widget('Text')->get_css_classes}),
		'a label with no font= gets no font class');
	is($h{Text4},$h{Text},'an unparseable font= leaves the theme font alone');
	is_deeply($srenderer2->Unhandled('Text4'),['font'],'an unparseable font= is reported');

	# colour does not change geometry, so a measurement would be vacuous here:
	# the style context is the observable
	my $plain=$srenderer2->Widget('Label')->get_style_context->get_color->to_string;
	my $white=$srenderer2->Widget('Label3')->get_style_context->get_color->to_string;
	is($white,'rgb(255,255,255)','an explicit colour reaches the rendered text colour');
	isnt($white,$plain,'an explicit colour differs from the theme colour');
	# a grey is the legacy spelling of de-emphasis, which GTK4 expresses with
	# the dim-label class so it follows the theme and its dark variant. That
	# class styles by opacity at draw time, so get_color cannot observe it and
	# the class itself is the only available check.
	ok($srenderer2->Widget('Label2')->has_css_class('dim-label'),
		'color=grey becomes the theme-following dim-label class');
	ok(!grep(m/^gmb-color-/,@{$srenderer2->Widget('Label2')->get_css_classes}),
		'color=grey does not also pin a literal grey');
	is($srenderer2->Widget('Label4')->get_style_context->get_color->to_string,$plain,
		'an invalid colour leaves the theme colour alone');
	is_deeply($srenderer2->Unhandled('Label4'),['color'],'an invalid colour is reported');
	# control: an unstyled label carries neither styling class
	ok(!grep(m/^gmb-color-|^dim-label$/,@{$srenderer2->Widget('Label')->get_css_classes}),
		'a label with no color= gets no colour class');

	$srenderer2->Destroy;
	$swindow2->destroy;
	_drain();
}

# Layout-level inheritance of DefaultFont/DefaultFontColor as real rendering.
# Legacy InitLayout reads them into {global_options} (gmusicbrowser_layout.pm:971)
# and NewWidget merges them into every widget (:1162), but both fall back with
# || - at :1163 for the font and :3120 for the colour - so a widget's own
# font=/color= wins. They reuse the D031 provider, so DefaultFont is a ratio of
# the theme font just as font= is.
{	my $ifixture=File::Spec->catfile('t','layouts','inherit.layout');
	my $icatalog=Layout::Parser::ParseFiles(files=>[$ifixture]);
	is(scalar @{$icatalog->{diagnostics}},0,'inherit fixture parses without diagnostics');

	# The unstyled baseline comes from a SEPARATE layout with no globals, so
	# the comparison is against a genuinely untouched label rather than against
	# another inheriting one.
	my $plainrenderer=Layout::Renderer::Gtk4->new
	(	catalog=>$icatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);
	my $proot=$plainrenderer->Render('gtk4 inherit none');
	$proot->set_direction('ltr');
	my $pwindow=Gtk4::Window->new;
	$pwindow->set_default_size(700,300);
	$pwindow->set_child($proot);
	$pwindow->present;
	ok(_wait_for_window($pwindow),'GTK4 window mapped before the baseline measurement');
	_drain();
	my $baseline=($plainrenderer->Widget('Text')->measure('vertical',-1))[0];
	my $themecolor=$plainrenderer->Widget('Text')->get_style_context->get_color->to_string;
	ok(!grep(m/^gmb-font-|^gmb-color-|^dim-label$/,
		@{$plainrenderer->Widget('Text')->get_css_classes}),
		'a label in a layout with no globals carries no styling class');

	my $irenderer=Layout::Renderer::Gtk4->new
	(	catalog=>$icatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);
	my $iroot=$irenderer->Render('gtk4 inherit');
	$iroot->set_direction('ltr');
	my $iwindow=Gtk4::Window->new;
	$iwindow->set_default_size(700,300);
	$iwindow->set_child($iroot);
	$iwindow->present;
	ok(_wait_for_window($iwindow),'GTK4 window mapped before inheritance assertions');
	_drain();

	# every label in the fixture carries the identical text 'Wg', so only the
	# inherited or explicit option can change the measurement
	my %ih=map {($_=>($irenderer->Widget($_)->measure('vertical',-1))[0])}
		qw/Text Text2 Text3 Text4/;
	# DefaultFont=20 reaches a label that names no font= of its own
	cmp_ok($ih{Text},'>',$baseline,
		'a label with no font= renders larger under an inherited DefaultFont=20');
	ok($irenderer->Widget('Text')->has_css_class('gmb-font-200'),
		'an inherited DefaultFont=20 becomes the same 200% ratio as a font=20');
	# and the widget's own font= still wins, in the opposite direction, so this
	# turns on the precedence rather than merely on a class being present
	cmp_ok($ih{Text2},'<',$baseline,
		"a widget's own font=8 overrides the inherited DefaultFont=20");
	ok($irenderer->Widget('Text2')->has_css_class('gmb-font-80'),
		'the overriding font=8 keeps its own 80% ratio');
	ok(!$irenderer->Widget('Text2')->has_css_class('gmb-font-200'),
		'the overridden DefaultFont leaves no ratio class behind');
	# the two globals are inherited independently: overriding one must not
	# discard the other, which is what merging them per option rather than as
	# a pair gets right
	is($irenderer->Widget('Text2')->get_style_context->get_color->to_string,
		'rgb(255,255,255)',
		'overriding the font still leaves the inherited DefaultFontColor applied');
	ok($irenderer->Widget('Text3')->has_css_class('gmb-font-200'),
		'overriding the colour still leaves the inherited DefaultFont applied');

	# DefaultFontColor=white likewise reaches a label naming no color=
	is($irenderer->Widget('Text')->get_style_context->get_color->to_string,
		'rgb(255,255,255)',
		'an inherited DefaultFontColor reaches the rendered text colour');
	isnt($irenderer->Widget('Text')->get_style_context->get_color->to_string,$themecolor,
		'the inherited colour differs from the theme colour');
	# an explicit color=grey overrides the inherited white, as it does in GTK3
	ok($irenderer->Widget('Text3')->has_css_class('dim-label'),
		"a widget's own color=grey overrides the inherited DefaultFontColor");
	is($irenderer->Widget('Text3')->get_style_context->get_color->to_string,$themecolor,
		'the overridden white does not reach the explicitly greyed label');
	# a widget's own refused value is taken rather than falling through to the
	# global, which is what || does in the legacy code
	is($ih{Text4},$baseline,
		"a widget's own unparseable font= falls back to the theme, not to the global");
	is($irenderer->Widget('Text4')->get_style_context->get_color->to_string,$themecolor,
		"a widget's own invalid colour falls back to the theme, not to the global");
	is_deeply([sort @{$irenderer->Unhandled('Text4')}],['color','font'],
		"a widget's own refused values are reported under the widget");
	# with a provider available nothing is left over to report against the layout
	is($irenderer->UnhandledGlobals,undef,
		'globals that apply are not reported against the layout');

	$irenderer->Destroy;
	$iwindow->destroy;
	$plainrenderer->Destroy;
	$pwindow->destroy;
	_drain();
}

done_testing;
