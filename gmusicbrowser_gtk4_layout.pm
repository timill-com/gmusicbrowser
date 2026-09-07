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
	return bless
	{ catalog	=> $catalog,
	  frontend	=> $frontend,
	  labels	=> $labels,
	  context	=> $context,
	  icon_path	=> $icon_path,
	  widgets	=> {},
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
	return $self->_CreateContainer($layout->{roots}[0]);
}

sub Widget
{	return $_[0]{widgets}{$_[1]};
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
	$self->_SetAlignment($widget,$values) if $element eq 'AB';
	if ($element eq 'AB' || $element eq 'WB') { $container->append($widget) }
	else { $container->set_child($widget) }
	return $container;
}

# legacy AB defaults: xalign/yalign .5, xscale/yscale 1. A scale of 0 keeps the
# child at its natural size so the alignment is visible, otherwise it fills.
sub _SetAlignment
{	my ($self,$widget,$values)=@_;
	my %opt=(xalign=>.5, yalign=>.5, xscale=>1, yscale=>1, %$values);
	$widget->set_halign($opt{xscale} ? 'fill' : _align($opt{xalign}));
	$widget->set_valign($opt{yscale} ? 'fill' : _align($opt{yalign}));
}

sub _align
{	my $align=shift;
	return 'start' if $align<=.25;
	return 'end' if $align>=.75;
	return 'center';
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
	my $display=Gtk4::Gdk::Display::get_default() or return;
	my $theme=Gtk4::IconTheme::get_for_display($display) or return;
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
	}
	elsif ($element eq 'Play')
	{	$widget=Gtk4::Button->new_with_label('');
		# with no icon option the button follows the state through its label
		$self->_SetIcon($widget,$node->{options}{values});
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
		$widget->signal_connect(clicked => sub
		{	my $result=$self->{frontend}->Dispatch('Quit',undef,$self->{context});
			warn "$result->{error}\n" unless $result->{ok};
		});
	}
	else
	{	die _source($node).": GTK4 widget '$element' is not implemented\n"; }
	$self->{widgets}{$node->{name}}=$widget;
	return $widget;
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
