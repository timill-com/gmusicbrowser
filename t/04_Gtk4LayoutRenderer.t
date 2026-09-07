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
	# real GTK spells an unset dimension -1, and _ApplyCommonOptions merges
	# against whatever is already requested, so the double must do the same
	sub get_size_request
	{	my $self=shift;
		return (defined $self->{req_width} ? $self->{req_width} : -1,
			defined $self->{req_height} ? $self->{req_height} : -1);
	}
	sub set_size_request { @{$_[0]}{qw/req_width req_height/}=@_[1,2] }
	# _SetConstraints reads the child's minimum before realization; real GTK
	# returns (minimum, natural, min_baseline, nat_baseline) and spells an
	# unset dimension -1
	sub measure
	{	my ($self,$orientation)=@_;
		my $key= $orientation eq 'horizontal' ? 'req_width' : 'req_height';
		my $min= defined $self->{$key} ? $self->{$key} : 0;
		$min=0 if $min<0;
		return ($min,$min,-1,-1);
	}
	sub set_layout_manager { $_[0]{layout_manager}=$_[1] }
	# GTK4 styles a widget through CSS classes, which is how font=/color= are
	# applied; the real widget keeps them in order and reports them back
	sub add_css_class { push @{$_[0]{css}},$_[1] }
	sub get_css_classes { return $_[0]{css} || [] }
	sub has_css_class { my ($s,$c)=@_; return scalar grep {$_ eq $c} @{$s->{css}||[]} }
}
{	package Gtk4::ConstraintLayout;
	sub new { bless {constraints=>[]},$_[0] }
	sub add_constraint { push @{$_[0]{constraints}},$_[1] }
}
{	package Gtk4::Constraint;
	# the real constructor takes
	# (target,target_attribute,relation,source,source_attribute,multiplier,
	#  constant,strength); strength must be the numeric enum
	sub new
	{	my ($class,@a)=@_;
		my %c; @c{qw/target target_attribute relation source source_attribute
			multiplier constant strength/}=@a;
		return bless \%c,$class;
	}
	sub get_multiplier { $_[0]{multiplier} }
	sub get_constant { $_[0]{constant} }
	sub get_strength { $_[0]{strength} }
}
{	package Gtk4::CssProvider;
	sub new { bless {},$_[0] }
	# the real method needs the byte length as a second argument through this
	# binding, so the double requires it too rather than accepting one arg
	sub load_from_data
	{	my ($self,$css,$length)=@_;
		die "load_from_data needs a length\n" unless defined $length;
		die "load_from_data length disagrees with the data\n" unless $length==length $css;
		$self->{css}=$css;
	}
}
{	package Gtk4::StyleContext;
	our @providers;
	sub add_provider_for_display { push @providers,$_[1] }
}
# Gtk4::Gdk::Display is deliberately NOT doubled. These tests assert that the
# renderer works with no display at all, which is what makes _IconTheme return
# undef and every icon fall back to text; supplying one would quietly remove
# that coverage. It also means the CSS provider cannot be installed offline, so
# a generated font=/color= rule is reported through Unhandled here and its
# rendering is proved on real Wayland in t/gtk4/30_Box.t instead.
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
	# real GTK4 centres a label by default and does not ellipsize, which is what
	# makes the legacy xalign=>0 default observable
	sub new { bless {label=>$_[1],xalign=>0.5,yalign=>0.5,ellipsize=>'none'},$_[0] }
	sub set_xalign { $_[0]{xalign}=$_[1] }
	sub get_xalign { $_[0]{xalign} }
	sub set_yalign { $_[0]{yalign}=$_[1] }
	sub get_yalign { $_[0]{yalign} }
	sub set_ellipsize { $_[0]{ellipsize}=$_[1] }
	sub get_ellipsize { $_[0]{ellipsize} }
}
{	package Gtk4::Image;
	our @ISA=('Gtk4::Widget::Double');
	sub new { bless {pixel_size=>-1},$_[0] }
	sub set_pixel_size { $_[0]{pixel_size}=$_[1] }
	sub get_pixel_size { $_[0]{pixel_size} }
}
{	package Gtk4::Button;
	our @ISA=('Gtk4::Widget::Double');
	sub new { bless {signals=>{},has_frame=>1},$_[0] }
	sub new_with_label { bless {label=>$_[1],signals=>{},has_frame=>1},$_[0] }
	sub set_label { $_[0]{label}=$_[1]; delete $_[0]{child} }
	# real Gtk4::Button->set_icon_name builds a Gtk4::Image child, which is what
	# carries the pixel size, so the double has to produce one too
	sub set_icon_name { $_[0]{icon_name}=$_[1]; $_[0]{child}=Gtk4::Image->new }
	sub get_icon_name { $_[0]{icon_name} }
	sub get_child { $_[0]{child} }
	sub set_has_frame { $_[0]{has_frame}=$_[1] }
	sub get_has_frame { $_[0]{has_frame} }
	sub set_tooltip_text { $_[0]{tooltip}=$_[1] }
	sub signal_connect { $_[0]{signals}{$_[1]}=$_[2] }
	sub activate { $_[0]{signals}{clicked}->($_[0]) }
}

require 'gmusicbrowser_frontend.pm';
require 'gmusicbrowser_layout_parser.pm';
require 'gmusicbrowser_gtk4_layout.pm';
require 't/RendererLabels.pm';

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
	labels=>GMB::Test::RendererLabels::labels(),
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
	labels=>GMB::Test::RendererLabels::labels(),
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
		labels=>GMB::Test::RendererLabels::labels(),
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
	labels=>GMB::Test::RendererLabels::labels(),
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
	labels=>GMB::Test::RendererLabels::labels(),
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
is($srenderer->Widget('ABalign')->{layout_manager},undef,
	'an AB with integral values keeps the plain box layout');

# A fractional xalign/xscale has no halign/valign enum to land on, so the AB
# container takes a Gtk4::ConstraintLayout expressing the legacy arithmetic
# (D025 alternative 4). The constants are checked here; only a real allocation
# shows the solver applying them, which t/gtk4/30_Box.t does.
{	my $afixture=File::Spec->catfile('t','layouts','align.layout');
	my $acatalog=Layout::Parser::ParseFiles(files=>[$afixture]);
	is(scalar @{$acatalog->{diagnostics}},0,'align fixture parses without diagnostics');
	my $arenderer=Layout::Renderer::Gtk4->new
	(	catalog=>$acatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);
	$arenderer->Render('gtk4 align');
	# the integral cases must not gain a constraint layout, or the common path
	# every bundled layout uses has regressed
	for my $box (qw/ABstart ABcenter ABend ABfill/)
	{	is($arenderer->Widget($box)->{layout_manager},undef,
			"$box stays on the plain box layout");
	}
	my $frac=$arenderer->Widget('ABfrac')->{layout_manager};
	isa_ok($frac,'Gtk4::ConstraintLayout');
	is(scalar @{$frac->{constraints}},4,
		'a fractional AB gets one size and one position constraint per axis');
	# minimum comes from the child's measure(); the doubles model the -1 unset
	# convention, and this fixture requests no size, so the minimum is 0
	my ($width)=grep {$_->{target_attribute} eq 'width'} @{$frac->{constraints}};
	my ($left)=grep {$_->{target_attribute} eq 'left'} @{$frac->{constraints}};
	is($width->{multiplier},0,'xscale=0 makes the size independent of the slot');
	is($left->{multiplier},0.3,'xalign=0.3 reaches the position multiplier unbucketed');
	is($left->{strength},1001001000,
		'constraints use the numeric required strength, which this binding needs');
	is($left->{relation},'eq','a legacy alignment is an equality, not an inequality');
	is($left->{source_attribute},'width',
		'the position is expressed against the slot width so it stays linear');
	my $scale=$arenderer->Widget('ABscale')->{layout_manager};
	my ($swidth)=grep {$_->{target_attribute} eq 'width'} @{$scale->{constraints}};
	is($swidth->{multiplier},0.5,
		'a fractional xscale reaches the size multiplier rather than becoming a fill');
	# a scale of .5 has no enum even though an alignment of .5 is 'center'
	isa_ok($scale,'Gtk4::ConstraintLayout');
	# GTK3 coerces a non-numeric value to 0 and the legacy default is centred,
	# so the value is dropped rather than reaching the constraint arithmetic
	is($arenderer->Widget('ABbad')->{layout_manager},undef,
		'a non-numeric xalign falls back to the legacy default, not a constraint');
	is($arenderer->Widget('Label8')->{halign},'center',
		'a non-numeric xalign renders where the legacy default does');
	is_deeply($arenderer->Unhandled('ABbad'),['xalign'],
		'a rejected alignment value is reported rather than silently dropped');
	is($arenderer->Unhandled('ABfrac'),undef,
		'a fractional alignment the constraint path implements is not reported');
	is($arenderer->Unhandled('ABscale'),undef,
		'a fractional scale the constraint path implements is not reported');
	$arenderer->Destroy;
}

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
my ($stopped,%dispatched)=(0);
my $bfrontend;
$bfrontend=GMB::Frontend->new
(	commands =>
	{	Stop => sub {$stopped++; return 1},
		NextSong => sub {$dispatched{NextSong}++; return 1},
		PrevSong => sub {$dispatched{PrevSong}++; return 1},
		PlayPause => sub {1},
		Quit => sub {1},
	},
	state => {Playing=>sub {0}},
);
my $brenderer=Layout::Renderer::Gtk4->new
(	catalog=>$bcatalog,
	frontend=>$bfrontend,
	labels=>GMB::Test::RendererLabels::labels(),
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

# Next and Prev each dispatch their own core command name. Their %Layout::Widgets
# tips differ from their labels, so the tooltip is what pins the right entry.
for my $case (['Next','Next Song','NextSong'],['Prev','Recently played songs','PrevSong'])
{	my ($name,$tip,$command)=@$case;
	my $button=$brenderer->Widget($name);
	isa_ok($button,'Gtk4::Button');
	is($button->{label},$tip,"$name falls back to its label when no icon resolves");
	is($button->{tooltip},$tip,"$name applies the widget default tip as a tooltip");
	$button->activate;
	is($dispatched{$command},1,"$name dispatches $command");
	$button->activate;
	is($dispatched{$command},2,"$name is stateless and dispatches on every click");
}
# the two transport buttons must not share a command
is($dispatched{NextSong},2,'Prev did not dispatch NextSong');

# a repeated element keeps its own widget while sharing the element behaviour
is($brenderer->Widget('Stop4')->{tooltip},'Stop','a suffixed Stop keeps the element default');
is($brenderer->Widget('Next2')->{tooltip},'Skip','a suffixed Next honours its own layout tip');

# The legacy relief= and size= options. Both come from Layout::Button
# @default_options, so a button naming neither still gets relief=none and
# size=large-toolbar rather than the GTK4 defaults.
is($brenderer->Widget('Stop')->get_has_frame,0,'a button with no relief= takes the legacy relief=none');
is($brenderer->Widget('Next2')->get_has_frame,1,'relief=normal keeps the button frame');
is($brenderer->Widget('Prev3')->get_has_frame,0,'an explicit relief=none is frameless');
is($brenderer->Widget('Play')->get_has_frame,0,'Play is a Layout::Button and takes the same relief default');
is($brenderer->Widget('Quit')->get_has_frame,0,'Quit is a Layout::Button and takes the same relief default');
# size= becomes a pixel size on the button's image child. These doubles have no
# icon theme, so no icon resolves and every button here falls back to a text
# label with no image to size. The pixel sizes themselves are asserted against
# a real theme in t/gtk4/40_Icons.t; all this file can prove is that a
# text-fallback button is left alone rather than being handed a stray image.
is($brenderer->Widget('Stop')->get_child,undef,'a button that fell back to text has no image to size');
is($brenderer->Widget('Stop5')->get_child,undef,'size=dialog does not fabricate an image without an icon');

# Options the renderer does not implement stay in the catalog and are reported
# rather than silently accepted. nbsongs and group only feed the click3 song
# chooser.
is_deeply($brenderer->Unhandled('Prev2'),[qw/nbsongs group/],'Prev2 reports its unhandled options');
is($brenderer->Unhandled('Next2'),undef,'size= and relief= are no longer reported as unhandled');
is_deeply($brenderer->Unhandled('Stop6'),['size'],'a size= value outside the mapping is still reported');
is($brenderer->Unhandled('Next'),undef,'a button with no options reports nothing unhandled');
is($brenderer->Unhandled('Stop2'),undef,'a handled option is not reported as unhandled');
my $b2=$bcatalog->{layouts}{'gtk4 buttons'};
my ($prev2)=grep $_->{name} eq 'Prev2',map @{$_->{children}},@{$b2->{nodes}};
is_deeply($prev2->{options}{values},{nbsongs=>'4',group=>'Recent'},'unhandled options are preserved in the parsed catalog');
is($brenderer->Widget('Prev2')->{tooltip},'Recently played songs','an unhandled option does not disturb the default tip');

$brenderer->Destroy;
is_deeply($brenderer->Unhandled,{},'teardown clears the unhandled report');

# Filler and the legacy ApplyCommonOptions size request. Both toolkits spell an
# unset dimension -1, so the legacy read-then-merge carries over unchanged.
my $sizing=File::Spec->catfile('t','layouts','sizing.layout');
my $zcatalog=Layout::Parser::ParseFiles(files=>[$sizing]);
is(scalar @{$zcatalog->{diagnostics}},0,'sizing fixture parses without diagnostics');
my $zrenderer=Layout::Renderer::Gtk4->new
(	catalog=>$zcatalog,
	frontend=>$frontend,
	labels=>GMB::Test::RendererLabels::labels(),
);
my $zroot=$zrenderer->Render('gtk4 sizing');

# Filler is an empty horizontal box, matching legacy Gtk3::HBox->new
my $filler=$zrenderer->Widget('Filler');
isa_ok($filler,'Gtk4::Box');
is($filler->{orientation},'horizontal','Filler is a horizontal box like the legacy one');
is(scalar @{$filler->{children}},0,'Filler holds no children');
is($filler->{label},undef,'Filler carries no text of its own');

# a Filler earns its space from the packing prefix, exactly as any other child
is($filler->{hexpand},1,'an expanding Filler sets hexpand on the packing axis');
is($zrenderer->Widget('Filler2')->{hexpand},0,'a plain Filler does not expand');
is($zrenderer->Widget('Filler2')->{margin_start},4,'a padded Filler pads the packing axis');
is($zrenderer->Widget('Filler2')->{margin_top},undef,'Filler padding leaves the cross axis alone');

# minwidth/minheight reach every widget, not just buttons
is_deeply([$zrenderer->Widget('Filler3')->get_size_request],[120,-1],'minwidth alone leaves height unset');
is_deeply([$zrenderer->Widget('Label4')->get_size_request],[90,30],'minwidth and minheight both apply');
is_deeply([$zrenderer->Widget('Label5')->get_size_request],[-1,40],'minheight alone leaves width unset');
is_deeply([$zrenderer->Widget('Text')->get_size_request],[-1,-1],'a widget with neither option is left unrequested');
# and containers, matching the second legacy call site
is_deeply([$zroot->get_size_request],[320,-1],'a container honours minwidth');
is_deeply([$zrenderer->Widget('HBfillers')->get_size_request],[-1,-1],'a container with no size option is left unrequested');

# The legacy Layout::Label presentation options. @default_options is
# (xalign=>0, yalign=>.5), so a Label naming neither is left-aligned in GTK3
# while GTK4's own Label default is centred.
{	my $lfixture=File::Spec->catfile('t','layouts','labels.layout');
	my $lcatalog=Layout::Parser::ParseFiles(files=>[$lfixture]);
	is(scalar @{$lcatalog->{diagnostics}},0,'labels fixture parses without diagnostics');
	my $lrenderer=Layout::Renderer::Gtk4->new
	(	catalog=>$lcatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);
	$lrenderer->Render('gtk4 labels');

	is($lrenderer->Widget('Label')->get_xalign,0,'a Label with no xalign takes the legacy left alignment');
	is($lrenderer->Widget('Label')->get_yalign,0.5,'a Label with no yalign takes the legacy centre');
	is($lrenderer->Widget('Label2')->get_xalign,0,'xalign=0 is left');
	is($lrenderer->Widget('Label3')->get_xalign,0.5,'xalign=.5 is centre');
	is($lrenderer->Widget('Label4')->get_xalign,1,'xalign=1 is right');
	is($lrenderer->Widget('Label5')->get_yalign,0,'yalign=0 is top');
	# GTK4 set_xalign takes the same fractional value the deprecated GTK3
	# set_alignment did, so unlike AB's halign enum nothing is bucketed
	is($lrenderer->Widget('Label6')->get_xalign,0.25,'a fractional xalign is preserved exactly');
	is($lrenderer->Widget('Label6')->get_yalign,0.75,'a fractional yalign is preserved exactly');

	# ellipsize is the same Pango enum in both toolkits
	is($lrenderer->Widget('Text')->get_ellipsize,'end','ellipsize=end passes through');
	is($lrenderer->Widget('Text2')->get_ellipsize,'none','ellipsize=none passes through');
	# D028 normalises ellipsize=1 to 'end', following Layout::Button (:3051)
	# rather than Layout::Label, which leaves such a label un-ellipsized
	is($lrenderer->Widget('Text3')->get_ellipsize,'end','ellipsize=1 is normalised to end');
	is($lrenderer->Unhandled('Text3'),undef,'a normalised ellipsize is not reported');
	# an out-of-range value is fatal through this binding, so it must not be
	# passed on; reaching this line at all proves it was filtered
	is($lrenderer->Widget('Text5')->get_ellipsize,'none','an out-of-range ellipsize is left alone');
	is_deeply($lrenderer->Unhandled('Text5'),['ellipsize'],'an out-of-range ellipsize is reported');
	is($lrenderer->Widget('Text4')->get_xalign,0,'a non-numeric xalign falls back to the legacy default');
	is_deeply($lrenderer->Unhandled('Text4'),['xalign'],'a non-numeric xalign is reported');
	is($lrenderer->Unhandled('Label6'),undef,'handled alignment options are not reported');
	is($lrenderer->Unhandled('Text'),undef,'a handled ellipsize is not reported');
	$lrenderer->Destroy;
}

# The fixture must hand out a fresh copy, or one test mutating its labels would
# change another's. A %Buttons entry with no fixture label needs no assertion:
# the constructor already refuses it by name at the first renderer built.
{	my $labels=GMB::Test::RendererLabels::labels();
	isnt($labels,GMB::Test::RendererLabels::labels(),'the labels fixture hands out a copy');
	is_deeply($labels,GMB::Test::RendererLabels::labels(),'each copy has the same content');
}

# the merge must not clobber a dimension the layout did not name
$zrenderer->Widget('Label5')->set_size_request(55,40);
$zrenderer->_ApplyCommonOptions($zrenderer->Widget('Label5'),{minheight=>70});
is_deeply([$zrenderer->Widget('Label5')->get_size_request],[55,70],'merging a later minheight keeps the existing width');

# sizing options are handled, so they are not reported as ignored
is($zrenderer->Unhandled('Label4'),undef,'a sizing option is not reported as unhandled');
$zrenderer->Destroy;

# Legacy font=/color= translation. GTK4 removed the per-widget overrides
# Layout::Label used, so both become CSS (D031). These offline doubles have no
# display, so a generated rule cannot be installed and is reported instead;
# the rendering itself is proved on real Wayland in t/gtk4/30_Box.t.
{	my $sfixture=File::Spec->catfile('t','layouts','styling.layout');
	my $scatalog=Layout::Parser::ParseFiles(files=>[$sfixture]);
	is(scalar @{$scatalog->{diagnostics}},0,'styling fixture parses without diagnostics');
	my $renderer=Layout::Renderer::Gtk4->new
	(	catalog=>$scatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);
	$renderer->Render('gtk4 styling');
	# A grey is de-emphasis, and dim-label ships with GTK4, so it applies with
	# no provider and is the one styling that works here.
	ok($renderer->Widget('Label2')->has_css_class('dim-label'),
		'color=grey becomes dim-label without needing a provider');
	is($renderer->Unhandled('Label2'),undef,'a mapped grey is not reported');
	# Everything needing a generated rule cannot be applied without a display,
	# and must be reported rather than silently swallowed.
	is_deeply($renderer->Unhandled('Text2'),['font'],
		'a font= needing a provider is reported when none can be installed');
	is_deeply($renderer->Unhandled('Label3'),['color'],
		'an explicit colour needing a provider is reported likewise');
	is_deeply($renderer->Unhandled('Text4'),['font'],'an unparseable font= is reported');
	is_deeply($renderer->Unhandled('Label4'),['color'],'an invalid colour is reported');
	# control: a widget naming neither option reports nothing and carries no
	# styling class, so the comparison turns on the options
	is($renderer->Unhandled('Text'),undef,'a label with no styling options reports nothing');
	is_deeply($renderer->Widget('Text')->get_css_classes,[],
		'a label with no styling options gets no css class');
	# the provider is installed on the display, so Destroy must take it off
	# again or it outlives the widget tree it was created for
	$renderer->{style_provider}='sentinel';
	$renderer->{style_rules}={'gmb-font-200'=>'font-size: 200%'};
	$renderer->Destroy;
	is($renderer->{style_provider},undef,'Destroy releases the style provider');
	is($renderer->{style_rules},undef,'Destroy drops the collected style rules');
}

# Layout-level inheritance of DefaultFont/DefaultFontColor. Legacy InitLayout
# reads them into {global_options} (gmusicbrowser_layout.pm:971) and NewWidget
# merges them into every widget (:1162), but both fall back with || - at :1163
# for the font and at :3120 for the colour - so a widget's own font=/color=
# wins. The parser keeps them in {metadata}, which the renderer previously
# never read at all.
{	my $ifixture=File::Spec->catfile('t','layouts','inherit.layout');
	my $icatalog=Layout::Parser::ParseFiles(files=>[$ifixture]);
	is(scalar @{$icatalog->{diagnostics}},0,'inherit fixture parses without diagnostics');
	my $renderer=Layout::Renderer::Gtk4->new
	(	catalog=>$icatalog,
		frontend=>$frontend,
		labels=>GMB::Test::RendererLabels::labels(),
	);

	# A grey global is the one inheritance path these doubles can assert, since
	# dim-label ships with GTK4 and needs no provider.
	$renderer->Render('gtk4 inherit grey');
	is_deeply($renderer->{globals},{color=>'grey'},
		'a layout-wide DefaultFontColor is read from the parser metadata');
	ok($renderer->Widget('Text')->has_css_class('dim-label'),
		'a label with no color= inherits the layout DefaultFontColor');
	is($renderer->Unhandled('Text'),undef,'an inherited colour that applies is not reported');
	# The legacy precedence: the widget's own value wins over the global. Both
	# labels must end up in a DIFFERENT state for this to turn on the option -
	# asserting that Text2 merely lacks dim-label passes against a renderer
	# that never applies dim-label to anything.
	ok(!$renderer->Widget('Text2')->has_css_class('dim-label'),
		"a widget's own color= overrides the inherited DefaultFontColor");
	isnt($renderer->Widget('Text')->has_css_class('dim-label') ? 1 : 0,
		$renderer->Widget('Text2')->has_css_class('dim-label') ? 1 : 0,
		'the inheriting and the overriding label differ in their styling');
	is_deeply($renderer->Unhandled('Text2'),['color'],
		"the overriding color= is what gets reported, not the inherited grey");
	$renderer->Destroy;

	# A global needing a generated rule cannot be installed without a display,
	# so it is reported - but against the layout, because no widget's options
	# named it and attributing it to every inheriting widget would be wrong.
	$renderer->Render('gtk4 inherit');
	is_deeply($renderer->{globals},{font=>'20',color=>'white'},
		'both layout-wide globals are read');
	is_deeply($renderer->UnhandledGlobals,{font=>1,color=>1},
		'globals needing a provider are reported against the layout');
	is($renderer->Unhandled('Text'),undef,
		'a widget inheriting an untranslatable global reports no option of its own');
	# a widget naming its own value is reported under its own name as before
	is_deeply($renderer->Unhandled('Text2'),['font'],
		"a widget's own font= is still reported under the widget");
	ok($renderer->Widget('Text3')->has_css_class('dim-label'),
		'an explicit grey still applies while a global is present');
	# the widget's own refused value is taken rather than falling through to
	# the global, which is what || does in the legacy code
	is_deeply([sort @{$renderer->Unhandled('Text4')}],['color','font'],
		"a widget's own refused values are reported, not replaced by the globals");
	$renderer->Destroy;
	is($renderer->UnhandledGlobals,undef,'Destroy drops the reported globals');
	is($renderer->{globals},undef,'Destroy drops the collected globals');

	# Controls. A layout with no globals must behave exactly as before, and a
	# refused global must not be silently swallowed.
	$renderer->Render('gtk4 inherit none');
	is_deeply($renderer->{globals},{},'a layout with no globals collects none');
	is_deeply($renderer->Widget('Text')->get_css_classes,[],
		'a label in a layout with no globals gets no css class');
	is($renderer->UnhandledGlobals,undef,'a layout with no globals reports none');
	$renderer->Destroy;

	$renderer->Render('gtk4 inherit refused');
	is_deeply($renderer->UnhandledGlobals,{font=>1,color=>1},
		'an untranslatable global is reported rather than dropped');
	is_deeply($renderer->Widget('Text')->get_css_classes,[],
		'an untranslatable global leaves the label unstyled');
	$renderer->Destroy;
}

# The font= and colour translation itself, independent of any display. These
# are the arithmetic and the grey classification, which is where the parity
# exception in D031 actually lives.
{	my $r=bless {unhandled=>{}},'Layout::Renderer::Gtk4';
	# the ratio is fixed against the 10pt baseline the bundled layouts were
	# authored against, NOT against the live theme size: dividing by the live
	# size cancels out and reproduces the absolute legacy points, which is what
	# would stop the desktop font reaching the widget
	is(Layout::Renderer::Gtk4::LEGACY_FONT_BASELINE(),10,
		'the legacy font baseline is the 10pt GTK3 default');
	# _StyleRule cannot run without a provider here, so the class name is
	# checked through the rule generator's own naming
	# a '#' inside qw() would start a comment, so these are listed explicitly
	my %grey=map {($_=>Layout::Renderer::Gtk4::_IsGrey($_))}
		('grey','gray','Grey','silver','darkgrey','#ccc','#888888',
		 'white','red','#f00','#1a2b3c');
	ok($grey{$_},"'$_' is classified as a grey") for qw/grey gray Grey silver darkgrey/;
	ok($grey{'#ccc'},'a short hex with equal channels is a grey');
	ok($grey{'#888888'},'a long hex with equal channels is a grey');
	ok(!$grey{$_},"'$_' is not a grey") for qw/white red/;
	ok(!$grey{'#f00'},'a hex with unequal channels is not a grey');
	ok(!$grey{'#1a2b3c'},'a long hex with unequal channels is not a grey');
	# a grey maps to dim-label with no provider; a non-grey needs one and so
	# returns nothing here, which is what the reporting above relies on
	is($r->_ColorRule('grey'),'dim-label','a grey maps to the theme-following class');
	is($r->_ColorRule('#ccc'),'dim-label','a grey hex maps to the same class');
	is($r->_ColorRule('white'),undef,'a non-grey needs a provider and reports without one');
	is($r->_ColorRule(''),undef,'an empty colour is refused');
	is($r->_ColorRule(undef),undef,'a missing colour is refused');
	# a font= with no size in it cannot be translated at all, provider or not
	is($r->_FontRule('oops'),undef,'a font= naming no size is refused');
	is($r->_FontRule(''),undef,'an empty font= is refused');
	is($r->_FontRule('0'),undef,'a zero font size is refused');
}

done_testing;
