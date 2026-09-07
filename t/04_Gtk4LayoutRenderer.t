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

{	package Glib::Idle;
	our (%callbacks,$next);
	sub add { $callbacks{++$next}=$_[1]; return $next; }
	sub drain
	{	while (%callbacks)
		{	my ($id)=sort {$a<=>$b} keys %callbacks;
			my $cb=delete $callbacks{$id};
			$cb->();
		}
	}
}
{	package Glib::Source;
	sub remove { delete $Glib::Idle::callbacks{$_[1]} }
}
{	package Gtk4::Widget::Double;
	sub set_hexpand { $_[0]{hexpand}=$_[1] }
	sub set_vexpand { $_[0]{vexpand}=$_[1] }
	sub set_halign { $_[0]{halign}=$_[1] }
	sub set_valign { $_[0]{valign}=$_[1] }
	sub set_margin_start { $_[0]{margin_start}=$_[1] }
	sub set_margin_end { $_[0]{margin_end}=$_[1] }
	sub set_margin_top { $_[0]{margin_top}=$_[1] }
	sub set_margin_bottom { $_[0]{margin_bottom}=$_[1] }
}
{	package Gtk4::Box;
	our @ISA=('Gtk4::Widget::Double');
	sub new { bless {orientation=>$_[1],spacing=>$_[2],children=>[]},$_[0] }
	sub append { push @{$_[0]{children}},$_[1] }
	sub prepend { unshift @{$_[0]{children}},$_[1] }
	sub insert_child_after
	{	my ($self,$widget,$sibling)=@_;
		my $at=0;
		if (defined $sibling)
		{	my $children=$self->{children};
			$at=1+(grep {$children->[$_]==$sibling} 0..$#$children)[0];
		}
		splice @{$self->{children}},$at,0,$widget;
	}
}
{	package Gtk4::Paned;
	our @ISA=('Gtk4::Widget::Double');
	sub new { bless {orientation=>$_[1]},$_[0] }
	sub set_start_child { $_[0]{start_child}=$_[1] }
	sub set_end_child { $_[0]{end_child}=$_[1] }
	sub set_resize_start_child { $_[0]{resize_start}=$_[1] }
	sub set_resize_end_child { $_[0]{resize_end}=$_[1] }
	sub set_shrink_start_child { $_[0]{shrink_start}=$_[1] }
	sub set_shrink_end_child { $_[0]{shrink_end}=$_[1] }
	sub set_position
	{	my ($self,$position)=@_;
		return if defined $self->{position} && $self->{position}==$position;
		$self->{position}=int $position;
		$self->notify('notify::position');
	}
	sub get_position { $_[0]{position} || 0 }
	sub get { $_[0]{$_[1]} }
	sub get_width { $_[0]{width} || 0 }
	sub get_height { $_[0]{height} || 0 }
	sub get_start_child { $_[0]{start_child} }
	sub get_end_child { $_[0]{end_child} }
	sub get_resize_start_child { $_[0]{resize_start} }
	sub get_resize_end_child { $_[0]{resize_end} }
	sub signal_connect { $_[0]{signals}{$_[1]}=$_[2]; return $_[1]; }
	sub signal_handler_disconnect { delete $_[0]{signals}{$_[1]} }
	sub notify
	{	my ($self,$signal)=@_;
		$self->{signals}{$signal}->($self) if $self->{signals}{$signal};
	}
	sub allocate
	{	my ($self,$max)=@_;
		@{$self}{qw/width height max-position/}=(600,400,$max);
		$self->notify('notify::max-position');
	}
}
{	package Gtk4::ScrolledWindow;
	our @ISA=('Gtk4::Widget::Double');
	sub new { bless {},$_[0] }
	sub set_child { $_[0]{child}=$_[1] }
}
{	package Gtk4::Frame;
	our @ISA=('Gtk4::Widget::Double');
	sub new { bless {label=>$_[1]},$_[0] }
	sub set_child { $_[0]{child}=$_[1] }
}
{	package Gtk4::Expander;
	our @ISA=('Gtk4::Widget::Double');
	sub new { bless {label=>$_[1]},$_[0] }
	sub set_child { $_[0]{child}=$_[1] }
	sub set_expanded { $_[0]{expanded}=$_[1] }
}
{	package Gtk4::Label;
	our @ISA=('Gtk4::Widget::Double');
	sub new { bless {label=>$_[1]},$_[0] }
}
{	package Gtk4::Button;
	our @ISA=('Gtk4::Widget::Double');
	sub new { bless {signals=>{}},$_[0] }
	sub new_with_label { bless {label=>$_[1],signals=>{}},$_[0] }
	sub set_label { $_[0]{label}=$_[1] }
	sub set_icon_name { $_[0]{icon_name}=$_[1] }
	sub set_tooltip_text { $_[0]{tooltip}=$_[1] }
	sub signal_connect { $_[0]{signals}{$_[1]}=$_[2] }
	sub activate { $_[0]{signals}{clicked}->($_[0]) }
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
	labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop'},
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

my $containers=File::Spec->catfile('t','layouts','containers.layout');
my $ccatalog=Layout::Parser::ParseFiles(files=>[$containers]);
is(scalar @{$ccatalog->{diagnostics}},0,'container fixture parses without diagnostics');
my $crenderer=Layout::Renderer::Gtk4->new
(	catalog=>$ccatalog,
	frontend=>$frontend,
	labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop'},
);
my $paned=$crenderer->Render('gtk4 containers');

isa_ok($paned,'Gtk4::Paned');
is($paned->{orientation},'horizontal','HP uses horizontal orientation');
is($paned->{position},180,'paned size option restores the handle position');
is($paned->{start_child},$crenderer->Widget('VBleft'),'first paned child becomes the start child');
is($paned->{end_child},$crenderer->Widget('VBright'),'second paned child becomes the end child');
is($paned->{resize_start},1,'"_" packing sets resize on the start child');
is($paned->{resize_end},0,'absent "_" leaves resize off on the end child');
is($paned->{shrink_start},1,'shrink stays on when "+" is absent');
is($paned->{shrink_end},0,'"+" packing disables shrink');

my $left=$crenderer->Widget('VBleft');
is($left->{orientation},'vertical','VB uses vertical orientation');
is($left->{spacing},1,'legacy boxes keep spacing 1');
is($left->{margin_start},4,'container border option becomes a margin');
is($crenderer->Widget('Play')->{vexpand},1,'"_" packing expands along a vertical box');
is($crenderer->Widget('Play')->{hexpand},undef,'"_" packing does not expand across a vertical box');
is($crenderer->Widget('Label')->{vexpand},0,'absent "_" leaves expand off along the packing axis');

my $right=$crenderer->Widget('VBright');
# fill and expand both act on the packing axis; a vertical box uses valign
is($crenderer->Widget('Label3')->{valign},'center','"." packing centres the child instead of filling');
is($crenderer->Widget('Label2')->{valign},'fill','fill is the default packing');
is($crenderer->Widget('Label3')->{halign},undef,'"." packing leaves the cross axis alone');
is($crenderer->Widget('Label4')->{margin_top},6,'numeric packing pads along the packing axis');
is($crenderer->Widget('Label4')->{margin_start},undef,'numeric packing leaves the cross axis alone');
is_deeply([map {$_==$crenderer->Widget('Quit') ? 'Quit' : $_->{label}} @{$right->{children}}],
	['right','nofill','padded','Quit'],'"-" packing places the child at the far end, after the start-packed children');

my %saved=$paned->{SaveOptions}->($paned);
is($saved{size},'180-120','saving before allocation retains the supplied sizes');
$paned->allocate(500);
Glib::Idle::drain();
%saved=$paned->{SaveOptions}->($paned);
is($saved{size},'380-120','allocation restores both sides using the resize policy');
$paned->set_position(210);
%saved=$paned->{SaveOptions}->($paned);
is($saved{size},'210-290','save captures movement before the pending idle runs');
Glib::Idle::drain();
$paned->allocate(600);
Glib::Idle::drain();
is($paned->get_position,310,'resizing preserves the non-resizing end child');
$paned->allocate(200);
Glib::Idle::drain();
%saved=$paned->{SaveOptions}->($paned);
is($saved{size},'310-290','insufficient allocation does not overwrite the saved sizes');
ok($paned->{need_resize},'constrained restoration remains pending');
$paned->allocate(700);
Glib::Idle::drain();
is($paned->get_position,410,'restoration retries after space becomes available');
ok(!$paned->{need_resize},'successful restoration clears the retry');
$paned->set_position(400);
ok($paned->{paned_idle},'movement schedules a size update');
$crenderer->Destroy;
is(scalar keys %Glib::Idle::callbacks,0,'teardown removes the pending size update');
is(scalar keys %{$paned->{signals}},0,'teardown disconnects pane notifications');
$paned->set_position(420);
is(scalar keys %Glib::Idle::callbacks,0,'retained pane cannot reschedule after teardown');

for my $case
(	['HP','_','',400,'200_200'], ['VP','','_',200,'200_200'],
	['HP','_','_',300,'200_200'], ['VP','','',300,'200_200'],
	['HP','_','_',180,'180'], ['VP','','_',0,'0'],
	['HP','_','',600,'200-0'],
	['VP','_','_',0,'0-0'],
)
{	my ($element,$start,$end,$expected,$size)=@$case;
	my $pcatalog=Layout::Parser::ParseFiles(files=>[$containers]);
	my ($node)=grep $_->{element} eq 'HP',@{$pcatalog->{layouts}{'gtk4 containers'}{nodes}};
	$node->{element}=$element;
	$node->{options}{values}{size}=$size;
	$node->{options}{values}{unknown}='keep';
	$node->{children}[0]{packing}{raw}=$start;
	$node->{children}[1]{packing}{raw}=$end;
	my $prenderer=Layout::Renderer::Gtk4->new
	(	catalog=>$pcatalog, frontend=>$frontend,
		labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop'},
	);
	my $pane=$prenderer->Render('gtk4 containers');
	$pane->allocate(600);
	Glib::Idle::drain();
	is($pane->get_position,$expected,"$element restores with resize flags '$start'/'$end'");
	my %options=$pane->{SaveOptions}->($pane);
	my $expected_size=$expected;
	$expected_size.='-'.(600-$expected) if $expected!=600;
	is($options{size},$expected_size,'size saves in legacy format, omitting a zero second side');
	is($node->{options}{values}{size},$size,'saving does not mutate the parsed catalog');
	is($node->{options}{values}{unknown},'keep','unknown parsed options remain intact');
	$prenderer->Destroy;
}

my $packing=File::Spec->catfile('t','layouts','packing.layout');
my $pkcatalog=Layout::Parser::ParseFiles(files=>[$packing]);
is(scalar @{$pkcatalog->{diagnostics}},0,'packing fixture parses without diagnostics');
my $pkrenderer=Layout::Renderer::Gtk4->new
(	catalog=>$pkcatalog,
	frontend=>$frontend,
	labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop'},
);
$pkrenderer->Render('gtk4 packing');

sub pk_order
{	my $box=$pkrenderer->Widget(shift);
	return [map {$_->{label}} @{$box->{children}}];
}

# orders verified against real GTK3 pack_start/pack_end allocations
is_deeply(pk_order('HBmixed'),['start','','padded','end2','end1'],
	'successive "-" packing moves each child inwards from the far edge');
is_deeply(pk_order('HBinterleaved'),['b','','d','c','a'],
	'interleaved start and end packing keeps both groups in legacy order');

is($pkrenderer->Widget('Label9')->{hexpand},1,'"_" expands along a horizontal box');
is($pkrenderer->Widget('Label9')->{halign},'fill','"_" without "." fills the extra space');
is($pkrenderer->Widget('Label10')->{hexpand},1,'"_." still expands');
is($pkrenderer->Widget('Label10')->{halign},'center','"_." keeps the natural size centred in the extra space');
is($pkrenderer->Widget('Label11')->{hexpand},0,'"." alone does not expand');
is($pkrenderer->Widget('Label11')->{halign},'center','"." turns fill off');
is($pkrenderer->Widget('Label2')->{margin_start},undef,'"-" alone adds no padding');
is($pkrenderer->Widget('Label4')->{margin_start},6,'padding applies on both packing-axis sides');
is($pkrenderer->Widget('Label4')->{margin_end},6,'padding applies on both packing-axis sides');
is($pkrenderer->Widget('Label4')->{margin_top},undef,'padding leaves the cross axis alone');
$pkrenderer->Destroy;

my $single=File::Spec->catfile('t','layouts','single.layout');
my $scatalog=Layout::Parser::ParseFiles(files=>[$single]);
is(scalar @{$scatalog->{diagnostics}},0,'single-child fixture parses without diagnostics');
my $srenderer=Layout::Renderer::Gtk4->new
(	catalog=>$scatalog,
	frontend=>$frontend,
	labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop'},
);
$srenderer->Render('gtk4 single');

my $scroll=$srenderer->Widget('SBscroll');
isa_ok($scroll,'Gtk4::ScrolledWindow');
is($scroll->{child},$srenderer->Widget('Label'),'SB takes its child through set_child');

my $frame=$srenderer->Widget('FRframe');
isa_ok($frame,'Gtk4::Frame');
is($frame->{label},'framed','FR keeps its label option');
is($frame->{child},$srenderer->Widget('Label2'),'FR takes a single child');

my $expander=$srenderer->Widget('EBexpand');
isa_ok($expander,'Gtk4::Expander');
is($expander->{label},'more','EB keeps its label option');
is($expander->{expanded},1,'EB restores the saved expanded state');

# GTK4 has no GtkAlignment, so AB becomes alignment properties on its child
my $aligned=$srenderer->Widget('Label4');
is($aligned->{halign},'end','AB xalign=1 with xscale=0 aligns the child to the end');
is($aligned->{valign},'start','AB yalign=0 with yscale=0 aligns the child to the start');

# GTK4 has no GtkEventBox; WB becomes a plain box that can own controllers
my $event=$srenderer->Widget('WBevent');
isa_ok($event,'Gtk4::Box');
is($event->{children}[0],$srenderer->Widget('Label5'),'WB holds its child');

$srenderer->Destroy;

# Stateless command buttons come from the renderer's %Buttons table rather than
# a bespoke branch per widget. There is no icon theme behind the doubles, so
# every icon resolves to nothing here and the buttons must stay operable on the
# text fallback; the icon path itself is covered on real Wayland.
my $buttons=File::Spec->catfile('t','layouts','buttons.layout');
my $bcatalog=Layout::Parser::ParseFiles(files=>[$buttons]);
is(scalar @{$bcatalog->{diagnostics}},0,'button fixture parses without diagnostics');
my $stopped=0;
my $bfrontend;
$bfrontend=GMB::Frontend->new
(	commands =>
	{	Stop => sub {$stopped++; return 1},
		PlayPause => sub {1},
		Quit => sub {1},
	},
	state => {Playing=>sub {0}},
);
my $brenderer=Layout::Renderer::Gtk4->new
(	catalog=>$bcatalog,
	frontend=>$bfrontend,
	labels=>{play=>'Play',pause=>'Pause',quit=>'Quit',stop=>'Stop'},
	context=>{window_id=>'MainWindow',group=>'Play',selected_ids=>[]},
);
$brenderer->Render('gtk4 buttons');

my $stop=$brenderer->Widget('Stop');
isa_ok($stop,'Gtk4::Button');
is($stop->{label},'Stop','Stop falls back to its label when no icon resolves');
is($stop->{tooltip},'Stop','Stop applies the widget default tip as a tooltip');
$stop->activate;
is($stopped,1,'Stop dispatches the exact legacy command name');
$stop->activate;
is($stopped,2,'Stop is stateless and dispatches on every click');

# a tip in the layout overrides the widget default, as %$opt2 over %$ref does
is($brenderer->Widget('Stop2')->{tooltip},'Custom tip','a layout tip overrides the default');
# the authoritative icon option for Layout::Button is stock, not icon
is($brenderer->Widget('Stop3')->{tooltip},'Stop','a layout stock option keeps the default tip');

$brenderer->Destroy;

done_testing;
