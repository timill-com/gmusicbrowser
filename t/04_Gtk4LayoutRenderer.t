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

{	package Gtk4::Box;
	sub new { bless {orientation=>$_[1],children=>[]},$_[0] }
	sub append { push @{$_[0]{children}},$_[1] }
	sub set_hexpand { $_[0]{hexpand}=$_[1] }
	sub set_vexpand { $_[0]{vexpand}=$_[1] }
}
{	package Gtk4::Label;
	sub new { bless {label=>$_[1]},$_[0] }
}
{	package Gtk4::Button;
	sub new_with_label { bless {label=>$_[1],signals=>{}},$_[0] }
	sub set_label { $_[0]{label}=$_[1] }
	sub signal_connect { $_[0]{signals}{$_[1]}=$_[2] }
	sub activate { $_[0]{signals}{clicked}->($_[0]) }
	sub set_hexpand { $_[0]{hexpand}=$_[1] }
	sub set_vexpand { $_[0]{vexpand}=$_[1] }
}

require 'gmusicbrowser_frontend.pm';
require 'gmusicbrowser_layout_parser.pm';
require 'gmusicbrowser_gtk4_layout.pm';

my $fixture=File::Spec->catfile('t','layouts','proof.layout');
my $catalog=Layout::Parser::ParseFiles(files=>[$fixture]);
my ($frontend,$playing,$quit);
$frontend=GMB::Frontend->new
(	commands =>
	{	PlayPause => sub
		{ $playing=!$playing;
			$frontend->Emit(Playing=>{playing=>$playing ? 1 : 0});
			return $playing;
		},
		Quit => sub {$quit++; return 1},
	},
	state => {Playing=>sub {$playing ? 1 : 0}},
);
my $renderer=Layout::Renderer::Gtk4->new
(	catalog=>$catalog,
	frontend=>$frontend,
	labels=>{play=>'Play',pause=>'Pause',quit=>'Quit'},
	context=>{window_id=>'MainWindow',group=>'Play',selected_ids=>[]},
);
my $root=$renderer->Render('gtk4 proof');

isa_ok($root,'Gtk4::Box');
is($root->{orientation},'vertical','VB uses vertical orientation');
is(scalar @{$root->{children}},2,'root children rendered');
isa_ok($root->{children}[0],'Gtk4::Label');
is($root->{children}[0]{label},'GTK4 proof of life','Label text option preserved');
isa_ok($root->{children}[1],'Gtk4::Box');
is($root->{children}[1]{orientation},'horizontal','HB uses horizontal orientation');

my $play=$renderer->Widget('Play');
my $quitbutton=$renderer->Widget('Quit');
is($play->{label},'Play','Play reflects initial state');
$play->activate;
is($playing,1,'Play dispatches PlayPause');
is($play->{label},'Pause','Playing event updates Play label');
$quitbutton->activate;
is($quit,1,'Quit dispatches exact legacy command');

$renderer->Destroy;
$frontend->Emit(Playing=>{playing=>0});
is($play->{label},'Pause','renderer removes state subscriptions on teardown');
ok(!exists $INC{'Gtk3.pm'},'GTK4 renderer path does not load Gtk3');

done_testing;
