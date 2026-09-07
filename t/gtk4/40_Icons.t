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

plan skip_all => 'Wayland icon test must run through tools/run-gtk4-smoke'
	unless $ENV{GMB_GTK4_SMOKE};

require 'gmusicbrowser_gtk4_binding.pm';
my ($initialized,$reason)=GMB::Gtk4::Binding::try_init();
plan skip_all => $reason unless $initialized;
my $backend=GMB::Gtk4::Binding::backend_probe();
die (($backend->{error} || 'GTK4 display is not Wayland')."\n") unless $backend->{wayland};

require 'gmusicbrowser_frontend.pm';
require 'gmusicbrowser_layout_parser.pm';
require 'gmusicbrowser_gtk4_layout.pm';

ok(!exists $INC{'Gtk3.pm'},'GTK4 icon test does not load Gtk3');

my $fixture=File::Spec->catfile('t','layouts','icons.layout');
my $catalog=Layout::Parser::ParseFiles(files=>[$fixture]);
is(scalar @{$catalog->{diagnostics}},0,'icon fixture parses without diagnostics');

my ($playing,$quit);
my $frontend;
$frontend=GMB::Frontend->new
( commands=>
  { PlayPause=>sub { $playing=!$playing; $frontend->Emit(Playing=>{playing=>$playing?1:0}); return $playing },
    Quit=>sub { $quit++; return 1 },
  },
  state=>{Playing=>sub { $playing ? 1 : 0 }},
);

my $renderer=Layout::Renderer::Gtk4->new
(	catalog=>$catalog,
	frontend=>$frontend,
	labels=>{play=>'Play',pause=>'Pause',quit=>'Quit'},
	icon_path=>'pix',
);
$renderer->Render('gtk4 icons');

# GTK4 dropped the stock-item system, so a legacy 'gtk-*' name has to be
# mapped before it can resolve at all
is($renderer->Widget('Play')->get_icon_name,'media-playback-start',
	'a legacy gtk-* icon name maps to its freedesktop replacement');
is($renderer->Widget('Quit')->get_icon_name,'application-exit',
	'the stock= option resolves through the same mapping');

# a bundled gmb-* icon resolves from the flat pix/ directory
is($renderer->Widget('Play2')->get_icon_name,'gmb-random',
	'a bundled icon resolves from the pix/ search path');
# gmb-queue0 ships no file of its own and must fall back, as in GTK3
is($renderer->Widget('Quit2')->get_icon_name,'gmb-queue',
	'a bundled alias falls back to the icon that has a file');

# an unresolvable name must not leave a broken image in place of the label
my $unresolved=$renderer->Widget('Play3');
is($unresolved->get_icon_name,undef,'an unknown icon name sets no icon');
is($unresolved->get_label,'Play','an unknown icon name keeps the text label');
is($renderer->Widget('Quit3')->get_label,'Quit','a widget with no icon option keeps its label');

# the Play button tracks state through its icon when it has one
my $play=$renderer->Widget('Play');
$frontend->Dispatch('PlayPause',undef,{});
is($play->get_icon_name,'media-playback-pause','an icon Play button shows pause while playing');
$frontend->Dispatch('PlayPause',undef,{});
is($play->get_icon_name,'media-playback-start','an icon Play button returns to play when stopped');

# a text Play button still tracks state through its label
my $textplay=$renderer->Widget('Play3');
$frontend->Dispatch('PlayPause',undef,{});
is($textplay->get_label,'Pause','a text Play button still follows state');
$frontend->Dispatch('PlayPause',undef,{});
is($textplay->get_label,'Play','a text Play button returns to its play label');

# Every resolved name must be loadable. lookup_icon always returns a paintable
# because GTK substitutes its own missing-image icon, so a correct freedesktop
# name that this host's theme happens to lack still renders: verified with
# 'application-exit', which Yaru does not carry.
my $theme=Gtk4::IconTheme::get_for_display(Gtk4::Gdk::Display::get_default());
for my $name (qw/Play Quit Play2 Quit2/)
{	my $icon=$renderer->Widget($name)->get_icon_name;
	ok($theme->lookup_icon($icon,undef,24,1,'ltr',[]),
		"$name resolved to a loadable icon ($icon)");
}
# the bundled and directly-mapped names are present on this host
for my $name (qw/Play Play2 Quit2/)
{	my $icon=$renderer->Widget($name)->get_icon_name;
	ok($theme->has_icon($icon),"$name resolved to an icon present in the theme ($icon)");
}

$renderer->Destroy;

done_testing;
