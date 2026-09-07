# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# GTK4 menu interpreter. This is the counterpart of ::BuildMenu
# (gmusicbrowser.pl:4670), and it consumes the same menu-definition arrays
# rather than replacing them: a definition is data, and D002 keeps it that way.
#
# GTK4 removed GtkMenu, so the target is a Gio::Menu model driven by a
# Gtk4::PopoverMenu (D038). The two shapes disagree in one important way. The
# legacy builder evaluates its conditions and its foreach/include/repeat
# operators at popup time against live application state, while a menu model is
# declarative. The model is therefore rebuilt from the definition on every
# popup, which is the supported GTK4 pattern and is what preserves the dynamic
# behaviour.
#
# Actions carry the code. A model item cannot hold a Perl closure, so every
# entry that would have had one is registered as a Gio::SimpleAction in a group
# and referenced by name. Names are generated per build, since the same
# definition can produce different items each time.

use strict;
use warnings;

package GMB::Gtk4::Menu;

# The conditional filters legacy BuildMenu applies, in its order. Each returns
# true when the entry should be skipped. Kept as a table rather than a chain of
# ifs so the list can be compared against the legacy one at a glance.
my @Conditions=
(	[ignore	=> sub { 1 }],
	[type	=> sub { index($_[1]{type},$_[0])==-1 }],
	[mode	=> sub { index($_[0],$_[1]{mode})==-1 }],
	[notmode=> sub { index($_[0],$_[1]{mode})!=-1 }],
	[isdefined => sub { grep !defined $_[1]{$_}, split /\s+/,$_[0] }],
	[istrue	=> sub { grep !$_[1]{$_}, split /\s+/,$_[0] }],
	[isfalse=> sub { grep $_[1]{$_}, split /\s+/,$_[0] }],
	[empty	=> sub { $_[1]{$_[0]} && @{$_[1]{$_[0]}}!=0 }],
	[notempty=> sub { !$_[1]{$_[0]} || @{$_[1]{$_[0]}}==0 }],
	[onlyone=> sub { !$_[1]{$_[0]} || @{$_[1]{$_[0]}}!=1 }],
	[onlymany=> sub { !$_[1]{$_[0]} || @{$_[1]{$_[0]}}<2 }],
	[test	=> sub { !$_[0]->($_[1]) }],
);

sub new
{	my ($class,%args)=@_;
	my $self=bless
	{	frontend=>$args{frontend},
		prefix=>$args{prefix} || 'gmb',
		actions=>{},
		serial=>0,
		unhandled=>[],
	},$class;
	return $self;
}

# Created on demand so that the conditional and structural logic, which is plain
# Perl, can be exercised without a GTK4 display.
sub Group { $_[0]{group} ||= Gio::SimpleActionGroup->new }
sub Prefix { $_[0]{prefix} }

# Entries read but not applied, reported rather than silently accepted.
sub Unhandled { @{$_[0]{unhandled}} }

# Build a Gio::Menu from a legacy menu definition. Call it again for the next
# popup rather than caching: the definition's conditions and operators are meant
# to see current state.
sub Build
{	my ($self,$definition,$args)=@_;
	$self->_Reset;
	my $model=Gio::Menu->new;
	$self->_Append($model,$definition,$args || {});
	return $model;
}

# Legacy BuildMenuOptional (gmusicbrowser.pl:4774): an empty menu is undef, so a
# submenu that produced nothing is dropped instead of appearing as a dead item.
sub BuildOptional
{	my ($self,$definition,$args)=@_;
	my $model=$self->Build($definition,$args);
	return $model->get_n_items ? $model : undef;
}

sub _Reset
{	my $self=shift;
	$self->{group}->remove_action($_) for $self->{group} ? keys %{$self->{actions}} : ();
	$self->{actions}={};
	$self->{serial}=0;
	$self->{unhandled}=[];
}

# A separator becomes a section boundary. Items are collected into a section and
# the section is appended when a separator ends it, because that is how a
# GtkPopoverMenu draws a divider. Appending an empty section at the separator
# does not group anything: measured, the empty section counts as an item of its
# own and the entries after it stay at the top level.
#
# _Append fills one target. When a definition has no separator the target is the
# model itself, which keeps the common case flat.
sub _Append
{	my ($self,$model,$definition,$args)=@_;
	return unless $definition;
	my @groups=([]);
	$args=$self->_Split($definition,$args,\@groups);
	@groups=grep @$_,@groups;
	return unless @groups;
	# Only a definition that really produced two groups needs sections; one group
	# stays flat, so a separator whose side was filtered out leaves no trace.
	if (@groups==1)
	{	$self->_Fill($model,$groups[0],$args);
		return;
	}
	for my $group (@groups)
	{	my $section=Gio::Menu->new;
		$self->_Fill($section,$group,$args);
		$model->append_section(undef,$section) if $section->get_n_items;
	}
}

# Flatten a definition into runs of entries separated by separators, resolving
# the conditions and the structural operators on the way. Splitting first is what
# lets a foreach or include that follows a separator land in the right section.
sub _Split
{	my ($self,$definition,$args,$groups)=@_;
	for my $entry (@$definition)
	{	next if $self->_Skipped($entry,$args);

		# change_input rewrites the arguments for the entries that follow it and
		# contributes no item of its own.
		if (my $modify=$entry->{change_input})
		{	$args={%$args,@$modify};
			next;
		}
		if (my $foreach=$entry->{foreach})
		{	my ($key,@values)=$foreach->($args);
			my %copy=(%$entry,foreach=>undef);
			$self->_Split([\%copy],{%$args,$key,$_},$groups) for @values;
			next;
		}
		if (my $include=$entry->{include})
		{	# Legacy passes the menu as the second argument and the two bundled
			# callbacks use it: they call BuildChoiceMenu(menu=>$menu) to append
			# in place and return nothing to splice. Splitting happens before any
			# model exists, so they are collected here and run during the fill.
			if (ref $include eq 'CODE')
			{	push @{$groups->[-1]},[{_include=>$include},$args];
				next;
			}
			$self->_Split($include,$args,$groups) if ref $include eq 'ARRAY';
			next;
		}
		if (my $repeat=$entry->{repeat})
		{	for my $part ($repeat->($args))
			{	my ($nested,@extra)=@$part;
				$self->_Split($nested,{%$args,@extra},$groups);
			}
			next;
		}
		if ($entry->{separator})
		{	# a leading separator, or a run of them, adds no empty group
			push @$groups,[] if @{$groups->[-1]};
			next;
		}
		push @{$groups->[-1]},[$entry,$args];
	}
	return $args;
}

sub _Skipped
{	my ($self,$entry,$args)=@_;
	for my $condition (@Conditions)
	{	my ($key,$test)=@$condition;
		next unless $entry->{$key};
		return 1 if $test->($entry->{$key},$args);
	}
	return 0;
}

sub _Fill
{	my ($self,$target,$group,$args)=@_;
	for my $item (@$group)
	{	my ($entry,$entry_args)=@$item;
		if (my $include=$entry->{_include})
		{	my $result=$include->($entry_args,$target);
			# a callback may append in place and return nothing, or return a
			# definition to splice, or return a model already built
			if (ref $result eq 'ARRAY') { $self->_Append($target,$result,$entry_args); }
			next;
		}
		$self->_AppendItem($target,$entry,$entry_args);
	}
}

sub _AppendItem
{	my ($self,$model,$entry,$args)=@_;

	my $label=$entry->{label};
	$label=$label->($args) if ref $label;
	$label='' unless defined $label;

	if (my $submenu=$entry->{submenu})
	{	$self->_AppendSubmenu($model,$entry,$args,$label,$submenu);
		return;
	}

	my $item=Gio::MenuItem->new($label,undef);
	my $action=$self->_Action($entry,$args);
	$item->set_detailed_action($self->{prefix}.'.'.$action) if $action;
	if (my $icon=$entry->{stockicon})
	{	$icon=$icon->($args) if ref $icon;
		$item->set_icon(Gio::ThemedIcon->new($icon)) if defined $icon && length $icon;
	}
	$model->append_item($item);

	# Recorded rather than approximated: a right-click alternative needs the
	# button number, and a model item is activated without one.
	push @{$self->{unhandled}},$_ for grep exists $entry->{$_}, qw/submenu3 code3/;
}

sub _AppendSubmenu
{	my ($self,$model,$entry,$args,$label,$submenu)=@_;
	$submenu=$submenu->($args) if ref $submenu eq 'CODE';
	my $nested;
	# The order is legacy's (gmusicbrowser.pl:4742): an entry carrying code takes
	# the choice-menu path whatever the submenu's type, because an ordered_hash
	# submenu is an array of alternating labels and values, not a definition.
	if ($entry->{code})
	{	$nested=$self->_ChoiceMenu($submenu,%$entry,args=>$args);
	}
	elsif (ref $submenu eq 'ARRAY')
	{	$nested=Gio::Menu->new;
		$self->_Append($nested,$submenu,$args);
		$nested=undef unless $nested->get_n_items;
	}
	return unless $nested;
	# legacy appends extra entries to a computed submenu
	$self->_Append($nested,$entry->{append},$args) if $entry->{append};
	$model->append_submenu($label,$nested);
}

# Legacy BuildChoiceMenu (gmusicbrowser.pl): a list of values becomes a menu,
# optionally checkable against a current selection. Only the shapes the bundled
# definitions use are built here; anything else is reported.
sub _ChoiceMenu
{	my ($self,$choices,%options)=@_;
	return undef unless $choices;
	my $args=$options{args};
	my $tree=$options{submenu_tree} || $options{tree};
	my $reverse=$options{submenu_reverse} || $options{'reverse'} || $tree;
	my $ordered=$options{submenu_ordered_hash} || $options{ordered_hash} || $tree;

	my (@labels,@values);
	if ($ordered)
	{	my $i=0;
		while ($i<$#$choices) { push @labels,$choices->[$i++]; push @values,$choices->[$i++]; }
	}
	elsif (ref $choices eq 'ARRAY') { @labels=@values=@$choices; }
	else { @labels=keys %$choices; @values=values %$choices; }
	if ($reverse) { my @swap=@values; @values=@labels; @labels=@swap; }
	return undef unless @labels;

	my $selection=$self->_Selection(\%options,$args);
	my $model=Gio::Menu->new;
	for my $i (0..$#labels)
	{	my $label=$labels[$i];
		my $value=$values[$i];
		if (ref $value && $tree)
		{	my $nested=$self->_ChoiceMenu($value,%options);
			$model->append_submenu($label,$nested) if $nested;
			next;
		}
		my $item=Gio::MenuItem->new($label,undef);
		my $action=$self->_ChoiceAction($options{code},$args,$value,$selection);
		$item->set_detailed_action($self->{prefix}.'.'.$action);
		$model->append_item($item);
	}
	return $model->get_n_items ? $model : undef;
}

sub _Selection
{	my ($self,$options,$args)=@_;
	my $check=$options->{check};
	return undef unless defined $check;
	if (ref $check) { $check=$check->($args); }
	else { my (undef,$ref)=_KeyPath($args,$check); $check=$$ref; }
	return undef unless defined $check;
	return {map {$_=>1} @$check} if ref $check eq 'ARRAY';
	return {$check=>1};
}

# A model item holds a name, never a closure, so each entry that carries code
# gets its own action. Names are generated because the same definition can
# produce a different set of items on the next popup.
sub _Action
{	my ($self,$entry,$args)=@_;
	my $code=$entry->{code};
	my $keypath=$entry->{toggleoption};
	my $state=$entry->{check} || $entry->{radio};
	return undef unless $code || $keypath || $state;

	my $name='act'.$self->{serial}++;
	my $action;
	if ($keypath)
	{	my ($not,$ref)=_KeyPath($args,$keypath);
		my $active=$$ref ? 1 : 0;
		$active=$active ? 0 : 1 if $not;
		$action=Gio::SimpleAction->new_stateful($name,undef,Glib::Variant->new_boolean($active));
		$action->signal_connect('change-state' => sub
		{	my ($self_action,$value)=@_;
			$$ref^=1;
			$self_action->set_state($value);
			$self->_Run($code,$args,$value->get_boolean) if $code;
		});
	}
	elsif ($state)
	{	my $active=$state->($args) ? 1 : 0;
		$action=Gio::SimpleAction->new_stateful($name,undef,Glib::Variant->new_boolean($active));
		$action->signal_connect('change-state' => sub
		{	my ($self_action,$value)=@_;
			$self_action->set_state($value);
			$self->_Run($code,$args,$value->get_boolean) if $code;
		});
	}
	else
	{	$action=Gio::SimpleAction->new($name,undef);
		$action->signal_connect(activate => sub { $self->_Run($code,$args) });
	}
	# legacy sets an item insensitive rather than dropping it
	$action->set_enabled(0) if $entry->{sensitive} && !$entry->{sensitive}->($args);
	$self->Group->add_action($action);
	$self->{actions}{$name}=1;
	return $name;
}

sub _ChoiceAction
{	my ($self,$code,$args,$value,$selection)=@_;
	my $name='act'.$self->{serial}++;
	my $action;
	if ($selection)
	{	my $active=$selection->{$value} ? 1 : 0;
		$action=Gio::SimpleAction->new_stateful($name,undef,Glib::Variant->new_boolean($active));
		$action->signal_connect('change-state' => sub
		{	my ($self_action,$state)=@_;
			$self_action->set_state($state);
			$self->_Run($code,$args,$value);
		});
	}
	else
	{	$action=Gio::SimpleAction->new($name,undef);
		$action->signal_connect(activate => sub { $self->_Run($code,$args,$value) });
	}
	$self->Group->add_action($action);
	$self->{actions}{$name}=1;
	return $name;
}

# A code reference is called directly, as legacy does. A string is a command
# name and goes through the frontend contract, never to a widget: the renderer
# has no run_command and commands belong to the shared application model.
sub _Run
{	my ($self,$code,$args,$extra)=@_;
	return unless defined $code;
	if (ref $code) { $code->($args,$extra); return }
	unless ($self->{frontend})
	{	push @{$self->{unhandled}},$code;
		return;
	}
	my $result=$self->{frontend}->Dispatch($code,undef,{});
	warn "$result->{error}\n" unless $result->{ok};
}

# Legacy ParseKeyPath (gmusicbrowser.pl): 'a/b/c' walks into nested hashes and
# returns a reference to the last key, with a leading '!' inverting the reading.
sub _KeyPath
{	my ($ref,$keypath)=@_;
	my $not=$keypath=~s/^!//;
	my @parents=split m#/#,$keypath;
	my $last=pop @parents;
	for my $key (@parents)
	{	$ref=$ref->{$key};
		if (!ref $ref) { $ref={}; last }
	}
	return $not,\$ref->{$last};
}

1;
