# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

package Layout::Renderer::Gtk4;

my %Single= map {$_=>1} qw/SB FR EB AB WB/;	# containers holding exactly one child

# GTK4 reduced GtkIconSize to inherit/normal/large, so the legacy size= names
# cannot be passed through. These are the pixel sizes GTK3 resolves them to,
# read from Gtk3::IconSize::lookup on GTK 3.24.41, and set_pixel_size
# reproduces each one exactly. SIZE_BUTTONS ('large-toolbar', 24) is the
# Layout::Button default, so it applies to every button with no size= of its
# own; SIZE_FLAGS is 'menu'.
my %IconSizes=
(	'menu'		=> 16,
	'small-toolbar'	=> 16,
	'large-toolbar'	=> 24,
	'button'	=> 16,
	'dnd'		=> 32,
	'dialog'	=> 48,
);

# GTK4 removed the stock-item system, so the legacy 'gtk-*' names in existing
# layouts resolve to nothing. Map them to the freedesktop names they stood for.
my %StockNames=
(	'gtk-about'	=> 'help-about',
	'gtk-add'	=> 'list-add',
	'gtk-clear'	=> 'edit-clear',
	'gtk-close'	=> 'window-close',
	'gtk-find'	=> 'edit-find',
	'gtk-fullscreen'=> 'view-fullscreen',
	'gtk-info'	=> 'dialog-information',
	'gtk-media-next'=> 'media-skip-forward',
	'gtk-media-pause'=> 'media-playback-pause',
	'gtk-media-play'=> 'media-playback-start',
	'gtk-media-previous'=> 'media-skip-backward',
	'gtk-media-stop'=> 'media-playback-stop',
	'gtk-preferences'=> 'preferences-system',
	'gtk-properties'=> 'document-properties',
	'gtk-quit'	=> 'application-exit',
	'gtk-refresh'	=> 'view-refresh',
	'gtk-zoom-in'	=> 'zoom-in',
);

# Stateless command buttons, keeping the field names %Layout::Widgets uses so
# the two tables can be compared directly. Only commands the audited production
# bridge already exposes belong here: an unregistered one would build and then
# fail on click. Stateful buttons need a state getter and an event
# subscription, so Play is not in here. 'click2'/'click3' are omitted because
# pointer input is not ported. 'tip' names a caller-supplied label rather than
# holding text, which keeps this module free of the _"..." gettext idiom.
my %Buttons=
(	Prev =>
	{	stock	=> 'gtk-media-previous',
		tip	=> 'prev',
		command	=> 'PrevSong',
	},
	Stop =>
	{	stock	=> 'gtk-media-stop',
		tip	=> 'stop',
		command	=> 'Stop',
	},
	Next =>
	{	stock	=> 'gtk-media-next',
		tip	=> 'next',
		command	=> 'NextSong',
	},
);

# The legacy Layout::Button defaults (gmusicbrowser_layout.pm:3001). These are
# the defaults for every button, not rare options, so a button built without
# them is wrong even when the layout names no size= or relief=.
my %ButtonDefaults= (relief=>'none', size=>'large-toolbar');

# The only options a %Buttons widget acts on. Everything else a layout supplies
# stays in the parsed catalog so a saved layout round trips (D002), and
# Unhandled reports it so an ignored option is recorded rather than silently
# accepted. What that currently covers: 'nbsongs' and 'group', which only feed
# the Prev/Next click3 song chooser, and 'button=0', which asks for the
# EventBox form instead of a real button. 'minwidth'/'minheight' are handled
# for every widget by _ApplyCommonOptions, so they are not reported here.
my %ButtonHandled= map {$_=>1} qw/icon stock text tip size relief minwidth minheight/;

# The same for a Layout::Label widget. 'minsize'/'expand_max' are deliberately
# absent: they drive the legacy scrolling-label machinery. 'font'/'color' are
# handled through CSS, which is where GTK4 moved the widget overrides
# Layout::Label used; see D031.
#
# 'markup' is handled only where it names no song field. Legacy Layout::Label
# already splits on exactly that (gmusicbrowser_layout.pm:3156): a value
# ::UsedFields finds fields in subscribes through WatchSelID and re-renders per
# song, and anything else is set once. The static half needs no state, so it is
# ported and the field-bearing half stays reported. See D033.
my %LabelHandled= map {$_=>1} qw/text markup xalign yalign ellipsize minwidth minheight font color/;

# The legacy Layout::Label defaults (gmusicbrowser_layout.pm:3105). GTK4's own
# Label default is .5/.5, so these are not redundant.
my %LabelDefaults= (xalign=>0, yalign=>.5);
my %Ellipsize= map {$_=>1} qw/none start middle end/;

# the bundled aliases that have no file of their own, from %IconsFallbacks in
# gmusicbrowser.pl
my %IconFallbacks=
(	'gmb-queue0'	=> 'gmb-queue',
	'gmb-queue-window' => 'gmb-queue',
	'gmb-random-album' => 'gmb-random',
	'gmb-view-fullscreen' => 'gtk-fullscreen',
);

sub new
{	my ($class,%args)=@_;
	my $catalog=delete $args{catalog};
	my $frontend=delete $args{frontend};
	my $labels=delete $args{labels};
	my $context=delete $args{context} || {window_id=>'MainWindow',group=>'Play',selected_ids=>[]};
	my $icon_path=delete $args{icon_path};
	die "Unknown GTK4 layout renderer option '$_'\n" for sort keys %args;
	die "GTK4 layout renderer needs a version 1 catalog\n"
		unless ref $catalog eq 'HASH' && $catalog->{version} && $catalog->{version}==1;
	die "GTK4 layout renderer needs a frontend\n"
		unless ref $frontend && $frontend->can('Dispatch') && $frontend->can('Subscribe');
	die "GTK4 layout renderer needs labels\n"
		unless ref $labels eq 'HASH' && defined $labels->{play} &&
		defined $labels->{pause} && defined $labels->{quit};
	# Every %Buttons tooltip must be supplied, or the button would render with
	# neither an icon-theme fallback label nor a tooltip on a host whose theme
	# lacks the icon.
	die "GTK4 layout renderer needs the '$Buttons{$_}{tip}' label\n"
		for grep !defined $labels->{$Buttons{$_}{tip}}, sort keys %Buttons;
	return bless
	{ catalog	=> $catalog,
	  frontend	=> $frontend,
	  labels	=> $labels,
	  context	=> $context,
	  icon_path	=> $icon_path,
	  widgets	=> {},
	  unhandled	=> {},
	  subscriptions=> [],
	},$class;
}

sub Render
{	my ($self,$id)=@_;
	my $layout=$self->{catalog}{layouts}{$id}
		or die "Unknown layout '$id'\n";
	die _source($layout).": GTK4 renderer needs exactly one root container\n"
		unless @{$layout->{roots}}==1;
	$self->{layout}=$layout;
	$self->{nodes}={map {$_->{name}=>$_} @{$layout->{nodes}}};
	$self->{stack}={};
	$self->{globals}=_Globals($layout);
	return $self->_CreateContainer($layout->{roots}[0]);
}

# The layout-wide presentation globals, which legacy InitLayout reads into
# {global_options} (gmusicbrowser_layout.pm:971) and NewWidget then merges into
# every widget's options (:1162). The parser keeps them in {metadata}, since
# they are layout properties rather than widget options.
#
# Only these two are read. PATH, SkinPath, and SkinFile belong to the skin
# machinery, which is not ported.
my %Globals= (DefaultFont=>'font', DefaultFontColor=>'color');

sub _Globals
{	my $layout=shift;
	my $metadata=$layout->{metadata} || {};
	return {map {($Globals{$_}=>$metadata->{$_})}
		grep defined $metadata->{$_}, sort keys %Globals};
}

sub Widget
{	return $_[0]{widgets}{$_[1]};
}

# Options the renderer read from the layout but does not implement, by widget
# name. A caller can report them; the parsed values themselves are untouched.
sub Unhandled
{	my ($self,$name)=@_;
	return defined $name ? $self->{unhandled}{$name} : $self->{unhandled};
}

# The same for a layout-wide global whose value could not be translated. It is
# kept apart from the per-widget list because no widget's options named it, so
# reporting it against every inheriting widget would misattribute it.
sub UnhandledGlobals
{	return $_[0]{unhandled_globals};
}

sub Destroy
{	my $self=shift;
	$self->{frontend}->Unsubscribe($_) for @{$self->{subscriptions}};
	$self->{subscriptions}=[];
	for my $widget (values %{$self->{widgets}})
	{	next unless $widget->{paned_signals};
		$widget->signal_handler_disconnect($_) for @{delete $widget->{paned_signals}};
		Glib::Source->remove(delete $widget->{paned_idle}) if $widget->{paned_idle};
	}
	$self->{widgets}={};
	$self->{unhandled}={};
	delete $self->{unhandled_globals};
	delete $self->{globals};
	# the style provider is installed on the display, so it outlives the widget
	# tree unless it is taken off again
	if (my $provider=delete $self->{style_provider})
	{	eval
		{	my $display=Gtk4::Gdk::Display::get_default() or return;
			Gtk4::StyleContext::remove_provider_for_display($display,$provider);
		};
	}
	delete $self->{style_rules};
}

sub _CreateContainer
{	my ($self,$name)=@_;
	my $node=$self->{nodes}{$name}
		or die _source($self->{layout}).": unknown container '$name'\n";
	die _source($node).": recursive container '$name'\n" if $self->{stack}{$name};
	local $self->{stack}{$name}=1;
	my $element=$node->{element};
	my $container= $element eq 'HB' || $element eq 'VB' ? $self->_CreateBox($node)
		: $element eq 'HP' || $element eq 'VP' ? $self->_CreatePaned($node)
		: $Single{$element} ? $self->_CreateSingle($node)
		: die _source($node).": GTK4 container '$element' is not implemented\n";
	$self->_ApplyCommonOptions($container,$node->{options}{values});
	# every legacy container accepts 'border' as padding around its contents
	my $border=$node->{options}{values}{border};
	if (defined $border && $border=~m/^\d+$/)
	{	$container->set_margin_start($border);
		$container->set_margin_end($border);
		$container->set_margin_top($border);
		$container->set_margin_bottom($border);
	}
	return $container;
}

sub _CreateBox
{	my ($self,$node)=@_;
	my $horizontal= $node->{element} eq 'HB';
	my $box=Gtk4::Box->new($horizontal ? 'horizontal' : 'vertical',1);	# legacy boxes are created with spacing 1
	$self->{widgets}{$node->{name}}=$box;
	# GTK4 boxes are one ordered list, so legacy pack_end is reproduced by
	# inserting each later child before the ones already packed from the far
	# edge; the first '-' child stays nearest that edge.
	my ($last_start,$packed_end);
	for my $child (@{$node->{children}})
	{	my $packing=$child->{packing}{raw};
		my $widget=$self->_CreateChild($child);
		# legacy BoxPack: '_' expand, '-' pack_end, '.' fill off, digits padding
		my $end= $packing=~m/-/;
		my $expand= $packing=~m/_/ ? 1 : 0;
		if ($horizontal) { $widget->set_hexpand($expand) } else { $widget->set_vexpand($expand) }
		# expand and fill both act on the packing axis: without fill the child
		# keeps its natural size centred in the extra space expand gave it
		my $align= $packing=~m/\./ ? 'center' : 'fill';
		if ($horizontal) { $widget->set_halign($align) } else { $widget->set_valign($align) }
		if (my ($pad)= $packing=~m/([0-9]+)/)
		{	# legacy padding surrounds the child along the packing axis only
			if ($horizontal) { $widget->set_margin_start($pad); $widget->set_margin_end($pad); }
			else { $widget->set_margin_top($pad); $widget->set_margin_bottom($pad); }
		}
		if ($packed_end) { $box->insert_child_after($widget,$last_start) }
		else { $box->append($widget) }
		if ($end) { $packed_end=1 }
		else { $last_start=$widget }
	}
	return $box;
}

sub _CreatePaned
{	my ($self,$node)=@_;
	my $orientation= $node->{element} eq 'HP' ? 'horizontal' : 'vertical';
	my $paned=Gtk4::Paned->new($orientation);
	$self->{widgets}{$node->{name}}=$paned;
	my @children=@{$node->{children}};
	die _source($node).": GTK4 paned '$node->{name}' takes at most 2 children\n" if @children>2;
	for my $index (0..$#children)
	{	my $child=$children[$index];
		my $packing=$child->{packing}{raw};
		my $widget=$self->_CreateChild($child);
		# legacy PanedPack: '_' resize, shrink stays on unless '+' is present
		my $resize= $packing=~m/_/ ? 1 : 0;
		my $shrink= $packing=~m/\+/ ? 0 : 1;
		if ($index==0)
		{	$paned->set_start_child($widget);
			$paned->set_resize_start_child($resize);
			$paned->set_shrink_start_child($shrink);
		}
		else
		{	$paned->set_end_child($widget);
			$paned->set_resize_end_child($resize);
			$paned->set_shrink_end_child($shrink);
		}
	}
	$self->_SetPanedSize($paned,$node);
	$paned->{SaveOptions}=sub
	{	my $widget=shift;
		_PanedSize($widget);
		my $size=$widget->{size1};
		$size.='-'.$widget->{size2} if $widget->{size2};
		return size=>$size;
	};
	$paned->{paned_signals}=[map {$paned->signal_connect($_ => \&_QueuePanedSize)}
		qw/notify::position notify::max-position map/];
	return $paned;
}

# size="N" or "N-M"/"N_M" is a saved handle position; it is parsed under the C
# locale because the legacy option is written with a '.' decimal separator
sub _SetPanedSize
{	my ($self,$paned,$node)=@_;
	my $size=$node->{options}{values}{size};
	return unless defined $size && $size ne '';
	my ($size1,$size2)=map {$_+0} split /-|_/,$size;
	return unless defined $size1;
	$paned->{size1}=$size1;
	$paned->{size2}=$size2 if defined $size2;
	$paned->set_position($size1);
}

sub _QueuePanedSize
{	my $paned=shift;
	return if $paned->{paned_idle};
	# Position and bounds notifications can arrive during the same allocation.
	$paned->{paned_idle}=Glib::Idle->add(sub
	{	delete $paned->{paned_idle};
		_PanedSize($paned);
		return 0;
	});
}

sub _PanedSize
{	my $paned=shift;
	return unless $paned->get_width && $paned->get_height;
	return unless $paned->get_start_child && $paned->get_end_child;
	my $max=$paned->get('max-position');
	return unless $max;
	my ($size1,$size2)=@{$paned}{qw/size1 size2/};
	# Keep the legacy resize policy, including retrying a constrained restore.
	if (defined $size1 && defined $size2 && abs($max-$size1-$size2)>5 || $paned->{need_resize})
	{	my $not_enough;
		my $resize1=$paned->get_resize_start_child;
		my $resize2=$paned->get_resize_end_child;
		if ($resize1 && !$resize2)
		{	$size1=$max-$size2;
			$size1=0 if $size1<0;
			$not_enough=$size2>$max;
		}
		elsif ($resize2 && !$resize1) { $size1=$max if $not_enough=$size1>$max; }
		else { $size1= $size1+$size2 ? $max*$size1/($size1+$size2) : 0; }
		if ($not_enough) { $paned->{need_resize}=1; }
		else
		{	$paned->set_position($size1);
			$paned->{size1}=$size1;
			$paned->{size2}=$max-$size1;
			delete $paned->{need_resize};
		}
	}
	else
	{	$paned->{size1}=$paned->get_position;
		$paned->{size2}=$max-$paned->{size1};
		delete $paned->{need_resize};
	}
}

# SB/FR/EB/AB/WB take exactly one child. GTK4 removed GtkAlignment and
# GtkEventBox, so AB becomes alignment properties on the child and WB becomes a
# plain box that can take a background and event controllers of its own.
sub _CreateSingle
{	my ($self,$node)=@_;
	my $element=$node->{element};
	my $values=$node->{options}{values};
	my @children=@{$node->{children}};
	die _source($node).": GTK4 container '$node->{name}' takes a single child\n" if @children>1;
	my $container;
	if ($element eq 'SB') { $container=Gtk4::ScrolledWindow->new }
	elsif ($element eq 'FR')
	{	$container=Gtk4::Frame->new(defined $values->{label} ? $values->{label} : undef);
	}
	elsif ($element eq 'EB')
	{	$container=Gtk4::Expander->new(defined $values->{label} ? $values->{label} : undef);
		$container->set_expanded($values->{expand} ? 1 : 0);
	}
	else { $container=Gtk4::Box->new('vertical',0) }
	$self->{widgets}{$node->{name}}=$container;
	return $container unless @children;
	my $widget=$self->_CreateChild($children[0]);
	$self->_SetAlignment($widget,$container,$values,$node->{name}) if $element eq 'AB';
	if ($element eq 'AB' || $element eq 'WB') { $container->append($widget) }
	else { $container->set_child($widget) }
	return $container;
}

# legacy AB defaults: xalign/yalign .5, xscale/yscale 1. A scale of 0 keeps the
# child at its natural size so the alignment is visible, otherwise it fills.
# halign/valign express that exactly whenever both numbers are integral, which
# is every bundled layout, so the common path stays a plain property set. A
# fractional value has no enum to land on and goes through _SetConstraints
# instead (D025 alternative 4).
sub _SetAlignment
{	my ($self,$widget,$container,$values,$name)=@_;
	my %default=(xalign=>.5, yalign=>.5, xscale=>1, yscale=>1);
	my %opt=(%default, %$values);
	my @ignored;
	for my $key (qw/xalign yalign xscale yscale/)
	{	# _number returns nothing for a value the constraint arithmetic cannot
		# use, which is what separates a refused value from one merely spelled
		# differently: the bundled layouts write '.5', '0.0' and '1.0'
		my $value=_number($opt{$key});
		push @ignored,$key if exists $values->{$key} && !defined $value;
		$opt{$key}= defined $value ? $value : $default{$key};
	}
	$self->{unhandled}{$name}=\@ignored if @ignored;
	# an alignment of .5 is 'center', but a scale of .5 has no enum at all
	if (grep(_fractional($opt{$_}), qw/xalign yalign/)
		|| grep($opt{$_}!=0 && $opt{$_}!=1, qw/xscale yscale/))
	{	$self->_SetConstraints($widget,$container,\%opt);
		return;
	}
	$widget->set_halign($opt{xscale} ? 'fill' : _align($opt{xalign}));
	$widget->set_valign($opt{yscale} ? 'fill' : _align($opt{yalign}));
}

# GTK_CONSTRAINT_STRENGTH_REQUIRED. The nickname 'required' warns "isn't
# numeric" through this binding and silently coerces to 0, which builds a
# constraint that does not bind at all, so the number is passed directly.
my $STRENGTH_REQUIRED= 1001001000;

# GtkAlignment's arithmetic, per axis: the child takes its minimum plus the
# named fraction of the slack, then sits the named fraction of the way across
# whatever slack is left. Measured against Gtk3::Alignment on the same fixture,
# a ConstraintLayout reproduces both fractional cases exactly; see D025.
#
#	size = scale*slot + (1-scale)*minimum
#	pos  = align*(1-scale)*slot - align*(1-scale)*minimum
#
# The second line is the substituted form of align*(slot-size), which keeps
# each constraint linear in one source term as GtkConstraint requires. Both
# constraints are always added: an align of 0 makes the position multiplier 0,
# but the constraint is still what pins the child to the near edge, and
# omitting it leaves the layout free to fill the slot instead.
sub _SetConstraints
{	my ($self,$widget,$container,$opt)=@_;
	my $layout=Gtk4::ConstraintLayout->new;
	$container->set_layout_manager($layout);
	for my $axis ([qw/xalign xscale width left horizontal/], [qw/yalign yscale height top vertical/])
	{	my ($align,$scale,$size,$edge,$orientation)=@$axis;
		my ($a,$s)=($opt->{$align},$opt->{$scale});
		my ($min)= $widget->measure($orientation,-1);
		$layout->add_constraint(Gtk4::Constraint->new(
			$widget,$size,'eq',$container,$size,$s,(1-$s)*$min,$STRENGTH_REQUIRED));
		$layout->add_constraint(Gtk4::Constraint->new(
			$widget,$edge,'eq',$container,$size,$a*(1-$s),-$a*(1-$s)*$min,$STRENGTH_REQUIRED));
	}
}

sub _align
{	my $align=shift;
	return 'start' if $align<=.25;
	return 'end' if $align>=.75;
	return 'center';
}

# An alignment of 0, .5 or 1 is start/center/end; anything else has no enum
# value and needs the constraint path. A scale is handled by its caller, since
# only 0 ('do not expand') and 1 ('fill') have enum equivalents.
sub _fractional
{	my $n=shift;
	return 0 if $n==0 || $n==1 || $n==.5;
	return 1;
}

# GTK3 coerces a non-numeric alignment or scale to 0 with a Perl warning. An
# out-of-range value would make the constraint arithmetic meaningless. Returns
# nothing for either, so the caller can both fall back to the legacy default
# and report the value it refused.
sub _number
{	my $value=shift;
	return undef unless defined $value && $value=~m/^[0-9]*\.?[0-9]+$/;
	return undef if $value<0 || $value>1;
	return $value+0;
}

# Resolve a legacy 'icon' or 'stock' option to a name GTK4 can display.
# The chain is: bundled alias, then the stock-name replacement, then the name
# itself. Returns nothing when no step resolves, so callers can fall back to a
# text label instead of showing a broken image.
sub _IconName
{	my ($self,$name)=@_;
	return unless defined $name && $name ne '';
	my $theme=$self->_IconTheme or return;
	my @chain=grep defined && $_ ne '',
		$name,$IconFallbacks{$name},$StockNames{$name},
		$StockNames{$IconFallbacks{$name} || ''};
	# Full-colour names are tried first so a theme that still carries them keeps
	# supplying them. Adwaita, which stock GNOME uses, ships only the '-symbolic'
	# variant of many action names: 'application-exit' and 'view-refresh' are
	# absent there but resolve as '-symbolic' in every theme measured, so the
	# suffixed pass is what makes these names follow the host theme on GNOME.
	for my $candidate (@chain,map $_.'-symbolic', grep !m/-symbolic$/, @chain)
	{	return $candidate if $theme->has_icon($candidate);
	}
	# A mapped name that this icon theme happens not to carry is still a better
	# answer than nothing, but an unmapped unknown name is not: that would show
	# a broken image where the layout expected a usable button.
	return $chain[1] if @chain>1;
	return;
}

# The bundled icons live in a flat pix/ directory; GTK4 resolves that directly,
# so the files do not need a themed hierarchy.
sub _IconTheme
{	my $self=shift;
	return $self->{icon_theme} if exists $self->{icon_theme};
	$self->{icon_theme}=undef;
	# No display means no icon theme, and every icon then resolves to nothing so
	# widgets keep their text. Wrapped because the lookup itself is absent, not
	# merely empty, when the renderer is driven without a real binding.
	my $theme=eval
	{	my $display=Gtk4::Gdk::Display::get_default() or return;
		Gtk4::IconTheme::get_for_display($display);
	} or return;
	if (defined $self->{icon_path} && -d $self->{icon_path})
	{	$theme->add_search_path($self->{icon_path});
	}
	$self->{icon_theme}=$theme;
	return $theme;
}

sub _CreateChild
{	my ($self,$child)=@_;
	return $child->{kind} eq 'container_ref'
		? $self->_CreateContainer($child->{target})
		: $self->_CreateWidget($child);
}

sub _CreateWidget
{	my ($self,$node)=@_;
	my $element=$node->{element};
	my $widget;
	if ($element eq 'Label' || $element eq 'Text')
	{	my $text=$node->{options}{values}{text};
		$text='' unless defined $text;
		$widget=Gtk4::Label->new($text);
		$self->_ApplyLabelOptions($widget,$node);
	}
	elsif ($element eq 'Filler')
	{	# an empty box, as in legacy Gtk3::HBox->new; it exists to take up space
		# through its packing prefix and minwidth/minheight, not to draw anything
		$widget=Gtk4::Box->new('horizontal',0);
	}
	elsif ($element eq 'Play')
	{	$widget=Gtk4::Button->new_with_label('');
		# with no icon option the button follows the state through its label
		$self->_SetIcon($widget,$node->{options}{values});
		$self->_ApplyButtonStyle($widget,$node->{options}{values});
		$self->_SetPlayLabel($widget,$self->{frontend}->State('Playing'));
		$widget->signal_connect(clicked => sub
		{	my $result=$self->{frontend}->Dispatch('PlayPause',undef,$self->{context});
			warn "$result->{error}\n" unless $result->{ok};
		});
		my $token=$self->{frontend}->Subscribe(Playing => sub
		{	my (undef,$payload)=@_;
			$self->_SetPlayLabel($widget,$payload->{playing});
		});
		push @{$self->{subscriptions}},$token;
	}
	elsif ($element eq 'Quit')
	{	$widget=Gtk4::Button->new_with_label($self->{labels}{quit});
		$self->_SetIcon($widget,$node->{options}{values});
		$self->_ApplyButtonStyle($widget,$node->{options}{values});
		$widget->signal_connect(clicked => sub
		{	my $result=$self->{frontend}->Dispatch('Quit',undef,$self->{context});
			warn "$result->{error}\n" unless $result->{ok};
		});
	}
	elsif (my $button=$Buttons{$element})
	{	$widget=$self->_CreateButton($node,$button);
	}
	else
	{	die _source($node).": GTK4 widget '$element' is not implemented\n"; }
	$self->_SetTip($widget,$node,$Buttons{$element});
	$self->_ApplyCommonOptions($widget,$node->{options}{values});
	$self->{widgets}{$node->{name}}=$widget;
	return $widget;
}

# The options legacy ApplyCommonOptions (gmusicbrowser_layout.pm:1239) applies to
# both boxes and widgets. Only the size request is portable: hover_layout needs a
# popup window and its own GdkWindow, neither of which is ported.
# The read-then-merge order is the legacy one, so a widget that already requested
# a size of its own keeps whichever dimension the layout did not override. Both
# toolkits spell an unset dimension -1, so the merge carries over unchanged.
sub _ApplyCommonOptions
{	my ($self,$widget,$values)=@_;
	return unless $values->{minwidth} || $values->{minheight};
	my ($minwidth,$minheight)=$widget->get_size_request;
	$minwidth=  $values->{minwidth}  || $minwidth;
	$minheight= $values->{minheight} || $minheight;
	$widget->set_size_request($minwidth,$minheight);
}

# The legacy Layout::Label options that carry over without song-field state.
#
# xalign/yalign: legacy @default_options is (xalign=>0, yalign=>.5)
# (gmusicbrowser_layout.pm:3105), applied through the deprecated
# Gtk3::Label::set_alignment. GTK4 splits that into set_xalign/set_yalign, which
# take the same fractional value, so unlike AB's halign enum (D025) nothing is
# bucketed. GTK4's own default is .5/.5, so a Label built without this is
# centred where GTK3 left-aligns it.
#
# ellipsize: the same Pango enum in both toolkits. Legacy Layout::Label passes
# the value through unchanged (:3127), so 'ellipsize=1' does not ellipsize in
# GTK3, while Layout::Button maps '1' to 'end' (:3051). D028 normalises the
# label to the button's reading, which is a deliberate parity exception: no
# bundled layout uses the form. An out-of-range value is fatal through this
# binding, so anything but a Pango mode is still reported rather than passed on.
sub _ApplyLabelOptions
{	my ($self,$widget,$node)=@_;
	my $values=$node->{options}{values};
	my %opt=(%LabelDefaults, map {($_=>$values->{$_})}
		grep defined $values->{$_}, qw/xalign yalign/);
	# A non-numeric alignment would be a binding error. GTK3 coerces it to 0
	# silently, so falling back to the legacy default keeps the widget usable
	# and still leaves the option reported.
	for my $key (qw/xalign yalign/)
	{	$opt{$key}=$LabelDefaults{$key} unless $opt{$key}=~m/^[0-9]*\.?[0-9]+$/;
		my $method="set_$key";
		$widget->$method($opt{$key}+0);
	}
	my $ellipsize=_Ellipsize($values->{ellipsize});
	$widget->set_ellipsize($ellipsize) if defined $ellipsize;
	# markup= over text=, which is the legacy order at
	# gmusicbrowser_layout.pm:3156. A field-bearing value needs the song state
	# path and is left reported; a malformed one falls back to plain text so a
	# typo shows its own source rather than an empty widget.
	my $markup=$values->{markup};
	my $marked;
	if (defined $markup && !_MarkupUsesFields($markup))
	{	$marked=_Markup($widget,$markup);
		$widget->set_text($markup) unless defined $marked;
	}
	# font=/color= become style classes; a value that cannot be translated, or
	# a display with no provider at all, leaves the option reported instead.
	# A widget with neither inherits the layout's DefaultFont/DefaultFontColor,
	# which is the legacy precedence at gmusicbrowser_layout.pm:1163 and :3120:
	# both spell the fallback with ||, so the widget's own value wins.
	my $globals=$self->{globals} || {};
	my %styled;
	for my $key (qw/font color/)
	{	my $value= defined $values->{$key} ? $values->{$key} : $globals->{$key};
		next unless defined $value;
		my $method= $key eq 'font' ? '_FontRule' : '_ColorRule';
		my $class=$self->$method($value);
		# an inherited value the renderer cannot translate is a layout-level
		# problem, so it is reported against the layout rather than against a
		# widget whose options never named it
		unless (defined $class)
		{	$self->{unhandled_globals}{$key}=1 unless defined $values->{$key};
			next;
		}
		$widget->add_css_class($class);
		$styled{$key}=1;
	}
	my @ignored=grep { !$LabelHandled{$_}
		|| ($_ eq 'ellipsize' && !defined _Ellipsize($values->{$_}))
		|| ($_ eq 'markup' && !defined $marked)
		|| ($_=~m/^(?:font|color)$/ && !$styled{$_})
		|| ($_=~m/^[xy]align$/ && $values->{$_}!~m/^[0-9]*\.?[0-9]+$/) }
		@{$node->{options}{order}};
	$self->{unhandled}{$node->{name}}=\@ignored if @ignored;
}

# GTK4 moved the per-widget font and colour overrides Layout::Label used
# (modify_font and override_color, gmusicbrowser_layout.pm:3119-3122) to CSS, so
# both options become a style class on a provider shared by the whole renderer.
# See D031.
#
# The provider is installed on the display, which is what GTK4 offers: there is
# no per-widget override left. It is created on first use so a renderer that
# needs neither option touches no global state, and the class names are derived
# from the value so two widgets asking for the same font or colour share one
# rule rather than accumulating duplicates.
sub _StyleProvider
{	my $self=shift;
	return $self->{style_provider} if $self->{style_provider};
	my $provider=eval { Gtk4::CssProvider->new } or return undef;
	# add_provider_for_display is the GTK4 replacement for the removed
	# gtk_style_context_add_provider_for_screen
	my $display=eval { Gtk4::Gdk::Display::get_default() } or return undef;
	eval { Gtk4::StyleContext::add_provider_for_display($display,$provider,800); 1 }
		or return undef;
	$self->{style_rules}={};
	return $self->{style_provider}=$provider;
}

# Reload the shared provider with every rule collected so far. load_from_data
# needs the byte length as a second argument through this binding.
sub _StyleRule
{	my ($self,$class,$body)=@_;
	my $provider=$self->_StyleProvider or return undef;
	return $class if $self->{style_rules}{$class};
	$self->{style_rules}{$class}=$body;
	# the trailing semicolon matters: without it GTK's parser warns
	# "Expected ';' at end of block" for every rule
	my $css=join '', map {".$_ { $self->{style_rules}{$_}; }\n"}
		sort keys %{$self->{style_rules}};
	eval { $provider->load_from_data($css,length $css); 1 } or return undef;
	return $class;
}

# The point size the bundled layouts were authored against. It is the GTK3
# default on the reference host, verified rather than assumed: GTK3 and GTK4
# both report 'Roboto 10' here and an unstyled label measures 19x17 in each.
# The ratio is fixed against this rather than against the live theme size,
# because dividing by the live size cancels out - 20/16 of a 16pt theme is
# 20pt again - which reproduces the absolute legacy size and stops the desktop
# font reaching the widget. See D031.
use constant LEGACY_FONT_BASELINE => 10;

# A legacy font= is an absolute Pango size. Emitting it as absolute points
# would pin the text and override the user's font preference, so it becomes a
# percentage of whatever the theme font is: font=20 is always 200%, so it stays
# twice the surrounding text on a 10pt desktop and on a 16pt one. Identical to
# GTK3 on a baseline desktop; a deliberate parity exception elsewhere.
sub _FontRule
{	my ($self,$value)=@_;
	return undef unless defined $value && $value=~m/^\s*(.*?)\s*$/ && length $1;
	my $spec=$1;
	# only the size is translated: a family or weight named in the legacy
	# string would override the theme's own, which is what this avoids
	my ($size)= $spec=~m/([0-9]+(?:\.[0-9]+)?)\s*$/;
	return undef unless $size && $size>0;
	my $percent= int(100*$size/LEGACY_FONT_BASELINE+.5);
	return undef if $percent<=0;
	my $class="gmb-font-$percent";
	return $self->_StyleRule($class,"font-size: $percent%");
}

# Greys are the legacy way of asking for de-emphasised text, and every bundled
# use is one. GTK4 expresses that with the dim-label style class, which follows
# the theme and its dark variant instead of pinning a shade, so a grey maps onto
# it. Any other colour is emitted as written, since the layout is asking for
# that specific colour rather than for de-emphasis.
my %Greys= map {$_=>1} qw/grey gray darkgrey darkgray dimgrey dimgray
	lightgrey lightgray silver/;

sub _ColorRule
{	my ($self,$value)=@_;
	return undef unless defined $value && $value=~m/^\s*(.*?)\s*$/ && length $1;
	my $color=$1;
	# dim-label ships with GTK4, so unlike a generated rule it needs no
	# provider and is available even where one cannot be installed
	return 'dim-label' if _IsGrey($color);
	# a value CSS cannot parse would poison the whole provider, since one bad
	# rule makes GTK drop the sheet, so only known-safe spellings are emitted
	return undef unless $color=~m/^#[0-9a-fA-F]{3}$|^#[0-9a-fA-F]{6}$|^[a-zA-Z]+$/;
	my $class='gmb-color-'.(lc($color)=~s/[^a-z0-9]+//gr);
	return $self->_StyleRule($class,"color: $color");
}

# A grey is either a named grey or a hex value whose channels are equal, which
# is how '#ccc' and '#888888' in a layout spell the same intent.
sub _IsGrey
{	my $color=lc shift;
	return 1 if $Greys{$color};
	if (my ($r,$g,$b)= $color=~m/^#([0-9a-f])([0-9a-f])([0-9a-f])$/)
	{	return $r eq $g && $g eq $b;
	}
	if (my ($r,$g,$b)= $color=~m/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/)
	{	return $r eq $g && $g eq $b;
	}
	return 0;
}

# Whether a legacy markup= refers to song fields, which is what legacy
# Layout::Label branches on at gmusicbrowser_layout.pm:3156. ::UsedFields
# (gmusicbrowser.pl:1012) looks for %<letter>, $name, and ${expr}, mapping the
# letters through %::ReplaceFields and keeping only the ones it defines.
#
# That table is built from the song field definitions in
# gmusicbrowser_songs.pm:1935, which is shared core the renderer must not pull
# in, so any field sigil counts here rather than only a defined one. The
# difference is deliberately on the safe side: an unmapped '%X' is reported
# instead of being drawn as literal text. It changes nothing for the bundled
# layouts, whose markup= values name only real fields (%a %g %l %m %s %t %y %Y
# and the $album/$artist/$length/$title_or_file/$track aliases).
sub _MarkupUsesFields
{	my $value=shift;
	return 1 if $value=~m/%[a-zA-Z]/;
	return 1 if $value=~m/\$[a-zA-Z{]/;
	return 0;
}

# A markup value the label can actually render, or nothing.
#
# GTK4's set_markup neither dies nor raises a trappable Perl warning on a
# malformed value: it prints a GTK warning, leaves the displayed text as it
# was, and keeps the raw string in get_label. So the only way to tell is to
# try it over a sentinel the markup itself cannot produce and see whether the
# text moved. Checking for empty text instead would misjudge the valid
# '<b></b>' and '' cases, which legitimately render nothing.
#
# The GTK warning still reaches stderr once per refused value; it cannot be
# suppressed from Perl. That is the cost of GTK4 offering no validator - Pango
# is unreachable through this binding, so Pango::parse_markup is not available.
my $MARKUP_SENTINEL= "\x{1}gmb-markup\x{1}";

sub _Markup
{	my ($widget,$value)=@_;
	return undef unless defined $value;
	$widget->set_text($MARKUP_SENTINEL);
	$widget->set_markup($value);
	return $widget->get_text ne $MARKUP_SENTINEL ? $value : undef;
}

# The Pango mode a legacy ellipsize= asks for, or undef if it names none. '1' is
# the Layout::Button spelling of 'end' (gmusicbrowser_layout.pm:3051), accepted
# here as well under D028.
sub _Ellipsize
{	my $value=shift;
	return undef unless defined $value;
	$value='end' if $value eq '1';
	return $Ellipsize{$value} ? $value : undef;
}

# The legacy relief= and size= options, which apply to every Layout::Button
# through @default_options rather than only where a layout names them.
#
# relief: GTK4 removed set_relief. 'none' is the has-frame-off button, which is
# what GTK3 draws for relief=none, and 'normal' is the framed default.
#
# size: GTK4 reduced GtkIconSize to inherit/normal/large, so the legacy name
# cannot be passed through. set_pixel_size on the image reproduces the GTK3
# pixel size exactly. set_icon_name creates that image itself, so styling its
# child keeps Button->get_icon_name working; replacing the child with an
# explicit image would leave get_icon_name undefined.
sub _ApplyButtonStyle
{	my ($self,$widget,$values)=@_;
	# the layout's own value over the Layout::Button default, matching how %$opt
	# overrides @default_options. No %Buttons entry sets either yet; the ones
	# that will are the SIZE_FLAGS widgets, which need state first.
	my %opt=(%ButtonDefaults, map {($_=>$values->{$_})}
		grep defined $values->{$_}, qw/relief size/);
	$widget->set_has_frame($opt{relief} eq 'none' ? 0 : 1);
	my $pixels=$IconSizes{$opt{size}};
	# an unknown size= name is left to the theme rather than guessed at, and is
	# reported through Unhandled
	return unless defined $pixels;
	my $image=$widget->get_child;
	return unless $image && $image->isa('Gtk4::Image');
	$image->set_pixel_size($pixels);
}

# A stateless button: one command, an icon from the widget's default 'stock'
# unless the layout names its own, and a text label only when no icon resolves.
sub _CreateButton
{	my ($self,$node,$def)=@_;
	my $values=$node->{options}{values};
	# a size= naming something outside %IconSizes is read but not acted on, so
	# it stays reported rather than silently accepted
	my @ignored=grep { !$ButtonHandled{$_}
		|| ($_ eq 'size' && !defined $IconSizes{$values->{$_} || ''}) }
		@{$node->{options}{order}};
	$self->{unhandled}{$node->{name}}=\@ignored if @ignored;
	my $widget=Gtk4::Button->new;
	# the layout's own icon= or stock= wins over the widget's default, matching
	# how %$opt overrides @default_options in legacy Layout::Button
	my %icon=%$values;
	$icon{stock}=$def->{stock} unless defined $icon{icon} || defined $icon{stock};
	my $name=$self->_SetIcon($widget,\%icon);
	$self->_ApplyButtonStyle($widget,$values);
	# a button with no usable icon must still be operable, so fall back to text
	unless (defined $name)
	{	my $text= defined $values->{text} ? $values->{text}
			: $self->{labels}{$def->{tip}};
		$widget->set_label($text) if defined $text;
	}
	$widget->signal_connect(clicked => sub
	{	my $result=$self->{frontend}->Dispatch($def->{command},undef,$self->{context});
		warn "$result->{error}\n" unless $result->{ok};
	});
	return $widget;
}

# The legacy tip option is a literal tooltip once '\n' is unescaped. A tip
# containing song fields is state-dependent and is not handled here.
sub _SetTip
{	my ($self,$widget,$node,$def)=@_;
	my $tip=$node->{options}{values}{tip};
	$tip=$self->{labels}{$def->{tip}} if !defined $tip && $def && defined $def->{tip};
	return unless defined $tip && $tip ne '';
	$tip=~s#\\n#\n#g;
	$widget->set_tooltip_text($tip);
}

# legacy layouts name an icon with either 'icon' or 'stock'
sub _SetIcon
{	my ($self,$widget,$values)=@_;
	my $requested= defined $values->{icon} ? $values->{icon} : $values->{stock};
	my $name=$self->_IconName($requested);
	return unless defined $name;
	$widget->set_icon_name($name);
	$widget->{icon_name}=$name;	# an icon button keeps its icon instead of a label
	# only the play/pause pair is swapped as the state changes
	$widget->{play_icon}=1 if $requested=~m/^(?:gtk-media-)?(?:play|pause)$/
		|| $requested eq 'media-playback-start' || $requested eq 'media-playback-pause';
	return $name;
}

sub _SetPlayLabel
{	my ($self,$widget,$playing)=@_;
	# a layout that named its own icon keeps it; only a play/pause icon follows
	# the state, so 'Play(icon=gmb-random)' is not overwritten here
	if ($widget->{play_icon})
	{	my $name=$self->_IconName($playing ? 'gtk-media-pause' : 'gtk-media-play');
		if (defined $name) { $widget->set_icon_name($name); return }
	}
	return if $widget->{icon_name};
	$widget->set_label($self->{labels}{$playing ? 'pause' : 'play'});
}

sub _source
{	my $item=shift;
	my $source=$item->{source} || {};
	return ($source->{file} || '<layout>').':'.($source->{line} || 0);
}

1
