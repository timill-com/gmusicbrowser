#!/usr/bin/env perl

# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;
use utf8;
binmode STDERR,':utf8';
binmode STDOUT,':utf8';

use FindBin;
use lib $FindBin::RealBin;

sub _ ($) {$_[0]}

require 'gmusicbrowser_gtk4_binding.pm';
require 'gmusicbrowser_frontend.pm';
require 'gmusicbrowser_layout_parser.pm';
require 'gmusicbrowser_gtk4_layout.pm';

GMB::Gtk4::Binding::init();

my $layoutfile=$ENV{GMB_GTK4_LAYOUT_FILE} || $FindBin::RealBin.'/t/layouts/proof.layout';
my $catalog=Layout::Parser::ParseFiles(files=>[$layoutfile]);
my @errors=grep $_->{severity} eq 'error',@{$catalog->{diagnostics}};
die join("\n",map {($_->{source}{file} || $layoutfile).':'.($_->{source}{line} || 0).": $_->{message}"} @errors)."\n" if @errors;

my ($app,$frontend,$renderer,$window);
my $playing=0;
my $smokefailed;

$frontend=GMB::Frontend->new
(	commands =>
	{	PlayPause =>
		{ code => sub
			{ $playing=!$playing;
				my $result=$frontend->Emit(Playing=>{playing=>$playing ? 1 : 0});
				die "$result->{error}\n" unless $result->{ok};
				return $playing;
			},
		},
		Quit =>
		{ code => sub
			{ $app->quit;
				return 1;
			},
		},
	},
	state => {Playing=>sub {$playing ? 1 : 0}},
	lifecycle =>
	{	shutdown => sub
		{	my $result=$frontend->Emit(Quit=>{});
			die "$result->{error}\n" unless $result->{ok};
			return 1;
		},
	},
);
my $lifecycle=$frontend->Startup({profile=>''});
die "$lifecycle->{error}\n" unless $lifecycle->{ok};

$app=Gtk4::Application->new('org.gmusicbrowser.Gtk4Proof',['non-unique']);
$app->signal_connect(activate => sub
{	my $application=shift;
	my $result=$frontend->Activate({reason=>'application'});
	die "$result->{error}\n" unless $result->{ok};
	return $window->present if $window;
	$renderer=Layout::Renderer::Gtk4->new
	(	catalog=>$catalog,
		frontend=>$frontend,
		labels=>{play=>_"Play",pause=>_"Pause",quit=>_"Quit",stop=>_"Stop"},
		context=>{window_id=>'MainWindow',group=>'Play',selected_ids=>[]},
	);
	my $content=$renderer->Render('gtk4 proof');
	$window=Gtk4::ApplicationWindow->new($application);
	$window->set_title('gmusicbrowser');
	$window->set_default_size(360,120);
	$window->set_child($content);
	$window->present;
	return unless $ENV{GMB_GTK4_SMOKE};
	Glib::Idle->add(sub
	{	my $ok=eval
		{	my $backend=GMB::Gtk4::Binding::backend_probe();
			die(($backend->{error} || 'GTK4 display is not Wayland')."\n") unless $backend->{wayland};
			die "GTK3 loaded by GTK4 entry point\n" if exists $INC{'Gtk3.pm'};
			my $play=$renderer->Widget('Play');
			die "GTK4 proof Play widget is missing\n" unless $play;
			$play->signal_emit('clicked');
			die "GTK4 proof action did not update state\n" unless $frontend->State('Playing');
			$play->grab_focus;
			print "GTK4_PROOF backend=wayland layout=gtk4 proof action=PlayPause gtk3=absent\n";
			1;
		};
		unless ($ok)
		{	$smokefailed=$@ || 'GTK4 proof failed';
			warn $smokefailed;
		}
		$frontend->Dispatch('Quit',undef,{window_id=>'MainWindow',group=>'Play',selected_ids=>[]});
		return 0;
	});
});
$app->signal_connect(shutdown => sub
{	my $result=$frontend->Shutdown({reason=>'application'});
	warn "$result->{error}\n" unless $result->{ok};
	$renderer->Destroy if $renderer;
	$renderer=undef;
	$window=undef;
});

my $status=$app->run(\@ARGV);
exit($smokefailed ? 2 : $status);
