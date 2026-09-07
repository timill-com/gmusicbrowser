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
	labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop'},
	icon_path=>'pix',
);
$renderer->Render('gtk4 icons');

# GTK4 dropped the stock-item system, so a legacy 'gtk-*' name has to be
# mapped before it can resolve at all
is($renderer->Widget('Play')->get_icon_name,'media-playback-start',
	'a legacy gtk-* icon name maps to its freedesktop replacement');
# The runner isolates the session bus, so the icon theme here is GTK's own
# default rather than the desktop's choice. Adwaita ships 'application-exit'
# only as a symbolic icon, so pin the mapping and let either variant satisfy it.
like($renderer->Widget('Quit')->get_icon_name,qr/^application-exit(?:-symbolic)?$/,
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
# name that the active theme happens to lack still renders.
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

# Icon resolution must follow the host theme, so it has to be checked against a
# theme other than whichever one this host happens to be using. A theme created
# with IconTheme->new can be retargeted; the display's own theme cannot, because
# set_theme_name refuses to touch the display singleton.
{	my $adwaita=Gtk4::IconTheme->new;
	$adwaita->set_theme_name('Adwaita');
	# add_search_path, not set_search_path: replacing the path would drop the
	# host theme directories and make every standard name unresolvable.
	$adwaita->add_search_path('pix');
	is($adwaita->get_theme_name,'Adwaita','a standalone icon theme can be retargeted');

	my $probe=Layout::Renderer::Gtk4->new
	(	catalog=>$catalog,
		frontend=>$frontend,
		labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop'},
		icon_path=>'pix',
	);
	$probe->{icon_theme}=$adwaita;

	# Adwaita carries the full-colour media names, so those must not be
	# rewritten: the suffixed pass is a fallback, not a preference.
	SKIP:
	{	skip 'installed Adwaita has no unsuffixed media-playback-start',1
			unless $adwaita->has_icon('media-playback-start');
		is($probe->_IconName('gtk-media-play'),'media-playback-start',
			'a name the theme carries is used unsuffixed');
	}

	# Adwaita ships only the symbolic variant of these, which is why the
	# unsuffixed name alone does not follow the host theme on stock GNOME. The
	# fallback is only observable while that stays true of the installed
	# Adwaita, so report a skip rather than a failure if a host ever ships the
	# unsuffixed name too.
	for my $pair (['gtk-quit','application-exit'],['gtk-refresh','view-refresh'])
	{	my ($legacy,$plain)=@$pair;
		if ($adwaita->has_icon($plain) || !$adwaita->has_icon($plain.'-symbolic'))
		{	SKIP: { skip "installed Adwaita does not isolate $plain from its symbolic variant",1 }
			next;
		}
		is($probe->_IconName($legacy),$plain.'-symbolic',
			"$legacy falls back to the symbolic variant the theme provides");
	}

	# the bundled names still come from pix/ and must not acquire a suffix
	is($probe->_IconName('gmb-random'),'gmb-random',
		'a bundled icon is unaffected by the symbolic fallback');
	is($probe->_IconName('gmb-queue0'),'gmb-queue',
		'a bundled alias still falls back to the icon that has a file');
	# an unmapped unknown name must still resolve to nothing rather than to a
	# fabricated '<name>-symbolic'
	is($probe->_IconName('no-such-icon-name'),undef,
		'an unknown name is not turned into a symbolic name');
	$probe->Destroy;
}

$renderer->Destroy;

# A %Buttons widget takes its icon from the table's default 'stock', so on a
# real theme it must show an icon rather than the text fallback the offline
# doubles see. media-playback-stop is in every theme measured.
{	my $bfixture=File::Spec->catfile('t','layouts','buttons.layout');
	my $bcatalog=Layout::Parser::ParseFiles(files=>[$bfixture]);
	is(scalar @{$bcatalog->{diagnostics}},0,'button fixture parses without diagnostics');
	my $stopped=0;
	my $bfrontend;
	$bfrontend=GMB::Frontend->new
	(	commands=>
		{ Stop=>sub {$stopped++; return 1}, PlayPause=>sub {1}, Quit=>sub {1} },
		state=>{Playing=>sub {0}},
	);
	my $brenderer=Layout::Renderer::Gtk4->new
	(	catalog=>$bcatalog,
		frontend=>$bfrontend,
		labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop'},
		icon_path=>'pix',
	);
	$brenderer->Render('gtk4 buttons');

	my $stop=$brenderer->Widget('Stop');
	is($stop->get_icon_name,'media-playback-stop',
		'Stop resolves its default stock through the icon theme');
	is($stop->get_label,undef,'an icon Stop button carries no text label');
	is($stop->get_tooltip_text,'Stop','Stop keeps its tooltip alongside the icon');

	# a layout stock= option overrides the widget default
	is($brenderer->Widget('Stop3')->get_icon_name,'gmb-random',
		'a layout stock option overrides the widget default icon');

	# 'activate' needs a mapped, focusable widget; emitting 'clicked' is the
	# same route a real click takes and is what 20_Paned.t uses for actions.
	$stop->signal_emit('clicked');
	is($stopped,1,'a real GTK4 button dispatches Stop when clicked');
	$brenderer->Destroy;
}

done_testing;
