# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# M1 gate probe: custom drawing. The remaining half of D010, and D006's
# "custom GObject/widget subclass" evidence line as it applies to drawing.
#
# The question this answers is not "can a widget be subclassed" -- D006 already
# records that layout vfunc overrides are silently ignored -- but "can the
# legacy skin layer's drawing reach the screen at all through this binding".
# GTK3 draws it in a `draw` handler holding a live Cairo context
# (Skin::draw, gmusicbrowser_layout.pm:5737). GTK4 removed that signal, so this
# file measures which replacement paths exist and which are unreachable.
#
# A feasibility probe, not a renderer test: no layout widget draws anything yet.

use strict;
use warnings;

use Test::More;
use lib '.';

plan skip_all => 'Wayland drawing probe must run through tools/run-gtk4-smoke'
	unless $ENV{GMB_GTK4_SMOKE};

require 'gmusicbrowser_gtk4_binding.pm';
my ($initialized,$reason)=GMB::Gtk4::Binding::try_init();
plan skip_all => $reason unless $initialized;
my $backend=GMB::Gtk4::Binding::backend_probe();
die (($backend->{error} || 'GTK4 display is not Wayland')."\n") unless $backend->{wayland};

ok(!exists $INC{'Gtk3.pm'},'GTK4 drawing probe does not load Gtk3');

# ---- what does not work, and why it looks like it should ----------------

# GtkDrawingArea exists and accepts a draw function, so a port would reasonably
# assume the legacy route survives. It does not: the callback is handed a
# CairoContext, whose GType is not registered with gperl, so it dies before the
# first drawing call. Nothing about the construction hints at this.
my $area=Gtk4::DrawingArea->new;
ok($area,'Gtk4::DrawingArea constructs');
ok(eval { $area->set_draw_func(sub {1}); 1 },'set_draw_func is accepted without complaint');

# Checked outside a signal handler on purpose: inside one Glib catches the
# error and prints 'unhandled exception in callback' to stderr, so an eval
# there would pass without ever seeing the failure (D006).
my $drawn=0;
$area->set_draw_func(sub { $drawn++ });
$area->set_content_width(32);
$area->set_content_height(32);
my $Failure;
{	my $app=Gtk4::Application->new('org.gmusicbrowser.Gtk4DrawProbe',['non-unique']);
	$app->signal_connect(activate => sub
	{	my $application=shift;
		my $window=Gtk4::ApplicationWindow->new($application);
		$window->set_default_size(200,200);
		$window->set_child($area);
		$window->present;
		Glib::Idle->add(sub
		{	Glib::MainContext->default->iteration(0) for 1..200;
			$application->quit;
			return 0;
		});
	});
	$Failure=!eval { $app->run([]); 1 };
}
ok($Failure,'mapping a DrawingArea dies rather than calling the draw function');
like($@,qr/CairoContext/,'the failure names the unregistered CairoContext type');
is($drawn,0,'the draw function never runs, so no legacy draw handler can be ported as-is');

# The GTK4-native replacement, GtkSnapshot, is closed off separately: every
# call that positions anything takes a graphene type, and those are not
# registered either (already recorded in D006 for compute_bounds).
my $snapshot=Gtk4::Snapshot->new;
ok($snapshot,'Gtk4::Snapshot constructs');
ok(eval { $snapshot->save; $snapshot->restore; 1 },'Snapshot save/restore work, so the object itself is usable');

my $rgba=Gtk4::Gdk::RGBA->new;
ok(eval { $rgba->parse('red'); 1 },'Gdk::RGBA parses a colour');
is($rgba->to_string,'rgb(255,0,0)','Gdk::RGBA is fully usable, so colour is not the obstacle');

ok(!eval { $snapshot->append_color($rgba,{x=>0,y=>0,width=>10,height=>10}); 1 },
	'Snapshot::append_color cannot be called');
like($@,qr/GrapheneRect/,'append_color fails on the unregistered GrapheneRect, not on the colour');
ok(!eval { $snapshot->translate({x=>1,y=>1}); 1 },'Snapshot::translate cannot be called either');
ok(!eval { $snapshot->to_node; 1 },'a snapshot cannot be turned into a render node');
like($@,qr/GskRenderNode/,'the render node type is unmarshallable in its own right');

# ---- what does work: render offscreen, upload as a texture --------------

# The standalone Cairo module is independent of the GTK4 introspection binding
# and still works. That matters because it means the legacy drawing *code* is
# portable even though the legacy drawing *callback* is not.
my $have_cairo=eval { require Cairo; 1 };
ok($have_cairo,'the standalone Cairo module loads') or BAIL_OUT('Cairo is required for the drawing route');

my ($Width,$Height)=(4,2);
my $surface=Cairo::ImageSurface->create('argb32',$Width,$Height);
my $cr=Cairo::Context->create($surface);
$cr->set_source_rgb(1,0,0);
$cr->rectangle(0,0,$Width,1);
$cr->fill;
$cr->set_source_rgb(0,0,1);
$cr->rectangle(0,1,$Width,1);
$cr->fill;
$surface->flush;
my $stride=$surface->get_stride;
cmp_ok(length $surface->get_data,'>',0,'an offscreen Cairo surface yields pixel data');

# Glib::Bytes is the hand-off point between the two libraries.
my $bytes=Glib::Bytes->new($surface->get_data);
ok($bytes,'Cairo pixel data wraps into a Glib::Bytes');

my $texture=Gtk4::Gdk::MemoryTexture->new($Width,$Height,'b8g8r8a8-premultiplied',$bytes,$stride);
ok($texture,'a MemoryTexture is built from Cairo output');
is($texture->get_width,$Width,'the texture keeps its width');
is($texture->get_height,$Height,'the texture keeps its height');

# Read the pixels back to prove nothing was reinterpreted on the way through.
# Byte order is BGRA, so the red row reads 0,0,255,255.
my $download="\0" x ($stride*$Height);
ok(eval { $texture->download($download,$stride); 1 },'a texture downloads back into a buffer');
is_deeply([unpack 'C4',substr($download,0,4)],[0,0,255,255],'the red row survives as BGRA');
is_deeply([unpack 'C4',substr($download,$stride,4)],[255,0,0,255],'the blue row survives as BGRA');

# GdkTexture is abstract; only its concrete subclasses construct. Worth an
# assertion because the error is about instantiability, not about arguments.
ok(!eval { Gtk4::Gdk::Texture->new; 1 },'Gdk::Texture is abstract and does not construct directly');

# The other half of the legacy skin path is loading an image file, which is
# what _load_skinfile does. pix/ ships PNGs, so use one rather than a fixture.
my $from_file=eval { Gtk4::Gdk::Texture->new_from_filename('pix/gmb-album.png') };
ok($from_file,'a texture loads from a bundled PNG');
cmp_ok($from_file->get_width,'>',0,'the loaded texture has a real width');

# ---- the pixels reach the screen, and can be replaced --------------------

# GtkPicture takes any paintable, so a texture is displayable without any
# widget subclass at all -- the composition route D030 used for AB.
my $picture=Gtk4::Picture->new;
ok(eval { $picture->set_paintable($texture); 1 },'a Picture accepts a texture as its paintable');
isa_ok($picture->get_paintable,'Gtk4::Gdk::MemoryTexture','the paintable reads back as the texture');

my ($Mapped,$Swapped);
{	my $app=Gtk4::Application->new('org.gmusicbrowser.Gtk4DrawProbe2',['non-unique']);
	$app->signal_connect(activate => sub
	{	my $application=shift;
		my $window=Gtk4::ApplicationWindow->new($application);
		$window->set_default_size(200,200);
		$window->set_child($picture);
		$window->present;
		Glib::Idle->add(sub
		{	my $context=Glib::MainContext->default;
			$context->iteration(0) for 1..300;
			$Mapped=$picture->get_mapped ? 1 : 0;

			# Redrawing is a texture swap, which is how a skin would repaint on a
			# state change. Skin::draw already caches a pixbuf per state and size
			# (gmusicbrowser_layout.pm:5764), so this matches what it does.
			my $second=Cairo::ImageSurface->create('argb32',$Width,$Height);
			my $context2=Cairo::Context->create($second);
			$context2->set_source_rgb(0,1,0);
			$context2->rectangle(0,0,$Width,$Height);
			$context2->fill;
			$second->flush;
			$picture->set_paintable(Gtk4::Gdk::MemoryTexture->new($Width,$Height,
				'b8g8r8a8-premultiplied',Glib::Bytes->new($second->get_data),$second->get_stride));
			$context->iteration(0) for 1..200;
			$Swapped=ref $picture->get_paintable;

			$application->quit;
			return 0;
		});
	});
	$app->run([]);
}
is($Mapped,1,'the texture-backed Picture maps on screen');
is($Swapped,'Gtk4::Gdk::MemoryTexture','the paintable can be replaced to repaint');

# CSS is the other route already in use (D031, D032) and covers the flat
# backgrounds, borders and rounded corners a skin would otherwise draw.
my $provider=Gtk4::CssProvider->new;
my $css='.probe { background-color: rgb(255,0,0); border: 2px solid rgb(0,255,0); }';
ok(eval { $provider->load_from_data($css,length $css); 1 },
	'CSS covers backgrounds and borders without any drawing call');

done_testing();
