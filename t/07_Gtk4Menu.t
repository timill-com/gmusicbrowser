#!/usr/bin/env perl

# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# Offline coverage for the GTK4 menu interpreter (D038). The conditional and
# structural halves of ::BuildMenu are plain Perl, so they are tested here
# against the legacy implementation itself rather than against expected values
# written by hand. Model building needs Gio and lives in t/gtk4/60_Menu.t.

use strict;
use warnings;
use utf8;

use Test::More;
use FindBin;
use File::Spec;

my $root=File::Spec->catdir($FindBin::Bin,File::Spec->updir);
require File::Spec->catfile($root,'gmusicbrowser_gtk4_menu.pm');

ok(!grep(/^Gtk(?:3|4)(?:::|\.pm)/,keys %INC),'menu interpreter imports no GTK binding');

# The legacy conditions, transcribed verbatim from gmusicbrowser.pl:4675-4687.
# The point of the transcription is that the expected values below are produced
# by legacy code, not by reading the port and agreeing with it.
sub legacy_skip
{	my ($m,$args)=@_;
	return 1 if $m->{ignore};
	return 1 if $m->{type}		&& index($args->{type},	$m->{type})==-1;
	return 1 if $m->{mode}		&& index($m->{mode},	$args->{mode})==-1;
	return 1 if $m->{notmode}	&& index($m->{notmode},	$args->{mode})!=-1;
	return 1 if $m->{isdefined}	&&   grep !defined $args->{$_}, split /\s+/,$m->{isdefined};
	return 1 if $m->{istrue}	&&   grep !$args->{$_}, split /\s+/,$m->{istrue};
	return 1 if $m->{isfalse}	&&   grep $args->{$_},  split /\s+/,$m->{isfalse};
	return 1 if $m->{empty}		&& (  $args->{ $m->{empty} }	&& @{ $args->{ $m->{empty}   } }!=0 );
	return 1 if $m->{notempty}	&& ( !$args->{ $m->{notempty} }	|| @{ $args->{ $m->{notempty}} }==0 );
	return 1 if $m->{onlyone}	&& ( !$args->{ $m->{onlyone}  }	|| @{ $args->{ $m->{onlyone} } }!=1 );
	return 1 if $m->{onlymany}	&& ( !$args->{ $m->{onlymany} }	|| @{ $args->{ $m->{onlymany}} }<2  );
	return 1 if $m->{test}		&& !$m->{test}($args);
	return 0;
}

my $menu=GMB::Gtk4::Menu->new;

# Both outcomes of every condition, so a filter that never fires cannot pass by
# accident. 'type' reads the args for the entry's value while 'mode' reads the
# entry for the args' value; that inversion is legacy's and is deliberate.
my @cases=
(	['no condition',	{},			{}],
	['ignore',		{ignore=>1},		{}],
	['type present',	{type=>'L'},		{type=>'LP'}],
	['type absent',		{type=>'X'},		{type=>'LP'}],
	['mode exact',		{mode=>'P'},		{mode=>'P'}],
	['mode one of',		{mode=>'PB'},		{mode=>'P'}],
	['mode excluded',	{mode=>'B'},		{mode=>'P'}],
	['notmode matching',	{notmode=>'P'},		{mode=>'P'}],
	['notmode other',	{notmode=>'B'},		{mode=>'P'}],
	['isdefined all',	{isdefined=>'a b'},	{a=>1,b=>2}],
	['isdefined missing',	{isdefined=>'a b'},	{a=>1}],
	['istrue true',		{istrue=>'a'},		{a=>1}],
	['istrue false',	{istrue=>'a'},		{a=>0}],
	['isfalse false',	{isfalse=>'a'},		{a=>0}],
	['isfalse true',	{isfalse=>'a'},		{a=>1}],
	['empty list',		{empty=>'l'},		{l=>[]}],
	['empty populated',	{empty=>'l'},		{l=>[1]}],
	['empty absent key',	{empty=>'l'},		{}],
	['notempty populated',	{notempty=>'l'},	{l=>[1]}],
	['notempty list',	{notempty=>'l'},	{l=>[]}],
	['notempty absent key',	{notempty=>'l'},	{}],
	['onlyone with one',	{onlyone=>'l'},		{l=>[1]}],
	['onlyone with two',	{onlyone=>'l'},		{l=>[1,2]}],
	['onlyone absent key',	{onlyone=>'l'},		{}],
	['onlymany with two',	{onlymany=>'l'},	{l=>[1,2]}],
	['onlymany with one',	{onlymany=>'l'},	{l=>[1]}],
	['onlymany absent key',	{onlymany=>'l'},	{}],
	['test true',		{test=>sub {1}},	{}],
	['test false',		{test=>sub {0}},	{}],
);
my $skipped=0;
for my $case (@cases)
{	my ($name,$entry,$args)=@$case;
	my $expected=legacy_skip($entry,$args) ? 1 : 0;
	$skipped+=$expected;
	is($menu->_Skipped($entry,$args)?1:0,$expected,"condition matches legacy: $name");
}
# Guards the table above: if every case landed the same way the comparison would
# be satisfied by a filter that always answered one thing.
cmp_ok($skipped,'>',0,'some cases are skipped');
cmp_ok($skipped,'<',scalar @cases,'some cases are kept');

# The structural operators, collected through a recording double so the offline
# test does not need Gio. _Append only ever calls append_section, append_item
# and append_submenu on what it is given.
{	package Recorder;
	sub new { bless {items=>[]},shift }
	sub append_item { push @{$_[0]{items}},$_[1]; }
	sub append_section { push @{$_[0]{items}},['section',$_[2]]; }
	sub append_submenu { push @{$_[0]{items}},"submenu:$_[1]"; }
	sub get_n_items { scalar @{$_[0]{items}} }
}
# Labels reach the model through Gio::MenuItem, so record them instead. The
# Gio::Menu double is a Recorder, which is what makes a nested definition's
# emptiness observable the way get_n_items makes it observable for real.
{	no warnings 'redefine','once';
	*Gio::MenuItem::new=sub { my (undef,$label)=@_; return bless {label=>$label},'Gio::MenuItem' };
	*Gio::MenuItem::set_detailed_action=sub {};
	*Gio::MenuItem::set_icon=sub { $_[0]{icon}=1 };
	*Gio::ThemedIcon::new=sub { bless {},'Gio::ThemedIcon' };
	*Gio::Menu::new=sub { Recorder->new };
	# Action registration is exercised for real in t/gtk4/60_Menu.t. Here it only
	# needs to not be the reason a definition fails to build, so the doubles
	# record what they were asked for rather than pretending to be actions.
	*Gio::SimpleAction::new=sub { my (undef,$name)=@_; bless {name=>$name},'Gio::SimpleAction' };
	*Gio::SimpleAction::new_stateful=sub { my (undef,$name,undef,$state)=@_; bless {name=>$name,state=>$state},'Gio::SimpleAction' };
	*Gio::SimpleAction::signal_connect=sub { $_[0]{connected}=$_[1] };
	*Gio::SimpleAction::set_enabled=sub { $_[0]{enabled}=$_[1] };
	*Gio::SimpleActionGroup::new=sub { bless {added=>[]},'Gio::SimpleActionGroup' };
	*Gio::SimpleActionGroup::add_action=sub { push @{$_[0]{added}},$_[1] };
	*Gio::SimpleActionGroup::remove_action=sub {};
	*Glib::Variant::new_boolean=sub { my (undef,$v)=@_; bless {boolean=>$v},'Glib::Variant' };
}
# Flatten the recorded structure. A section is rendered as '--' followed by its
# own items, so a separator's effect stays visible in a single expected list.
sub flatten
{	my $recorder=shift;
	my @out;
	for my $item (@{$recorder->{items}})
	{	if (ref $item eq 'ARRAY') { push @out,'--',@{flatten($item->[1])}; }
		elsif (ref $item) { push @out,$item->{label}; }
		else { push @out,$item; }
	}
	return \@out;
}
sub labels
{	my ($definition,$args)=@_;
	my $interpreter=GMB::Gtk4::Menu->new;
	my $recorder=Recorder->new;
	$interpreter->_Append($recorder,$definition,$args || {});
	return flatten($recorder);
}

is_deeply(labels([{label=>'A'},{label=>'B'}]),[qw/A B/],'plain entries append in order');
is_deeply(labels([{label=>sub {"dyn-$_[0]{x}"}}],{x=>7}),['dyn-7'],'a coderef label is called with the arguments');
# Each side of the separator becomes its own section, so both are prefixed.
is_deeply(labels([{label=>'A'},{separator=>1},{label=>'B'}]),['--','A','--','B'],'a separator splits the items into two sections');
is_deeply(labels([{label=>'A'},{label=>'B'}]),[qw/A B/],'no separator means no sections');
is_deeply(labels([{separator=>1},{label=>'A'}]),['A'],'a leading separator adds no empty section');
is_deeply(labels([{label=>'A'},{separator=>1},{separator=>1},{label=>'B'}]),['--','A','--','B'],'a run of separators adds one boundary');
is_deeply(labels([{label=>'A'},{separator=>1},{label=>'B',ignore=>1}]),['A'],'a separator whose section ends up empty adds nothing');

# foreach builds one item per value and passes each through the named key.
is_deeply
(	labels([{foreach=>sub {(v=>1,2,3)},label=>sub {"item$_[0]{v}"}}]),
	[qw/item1 item2 item3/],
	'foreach repeats an entry once per value'
);
# change_input rewrites the arguments for later entries and adds nothing itself.
is_deeply
(	labels([{label=>sub {"before-$_[0]{k}"}},{change_input=>[k=>'new']},{label=>sub {"after-$_[0]{k}"}}],{k=>'old'}),
	['before-old','after-new'],
	'change_input rewrites arguments for subsequent entries only'
);
is_deeply
(	labels([{include=>sub {[{label=>'x'},{label=>'y'}]}},{label=>'z'}]),
	[qw/x y z/],
	'include splices in a computed definition'
);
is_deeply
(	labels([{include=>[{label=>'lit'}]}]),
	['lit'],
	'include accepts a literal array reference'
);
is_deeply
(	labels([{repeat=>sub {([[{label=>sub {"r$_[0]{n}"}}],n=>1],[[{label=>sub {"r$_[0]{n}"}}],n=>2])}}]),
	[qw/r1 r2/],
	'repeat splices each part with its own arguments'
);
# A skipped entry must not consume its operator.
is_deeply(labels([{foreach=>sub {(v=>1)},label=>'never',ignore=>1},{label=>'kept'}]),['kept'],'a filtered entry runs no operator');

# Nested definitions become submenus, and an empty one is dropped rather than
# appearing as a dead item (legacy BuildMenuOptional).
is_deeply(labels([{label=>'Top',submenu=>[{label=>'Inner'}]}]),['submenu:Top'],'a nested definition becomes a submenu');
is_deeply(labels([{label=>'Empty',submenu=>[]}]),[],'a submenu with no items is dropped');
is_deeply(labels([{label=>'Cond',submenu=>[{label=>'x',ignore=>1}]}]),[],'a submenu whose items are all filtered is dropped');
is_deeply(labels([{label=>'Dyn',submenu=>sub {[{label=>'i'}]}}]),['submenu:Dyn'],'a coderef submenu is called');

# Unported entry keys are reported rather than silently accepted.
{	my $interpreter=GMB::Gtk4::Menu->new;
	my $recorder=Recorder->new;
	$interpreter->_Append($recorder,[{label=>'A',code3=>sub {}},{label=>'B',submenu3=>[]}],{});
	is_deeply([sort $interpreter->Unhandled],[qw/code3 submenu3/],'right-click alternatives are reported');
}
{	my $interpreter=GMB::Gtk4::Menu->new;
	my $recorder=Recorder->new;
	$interpreter->_Append($recorder,[{label=>'A',code=>sub {}}],{});
	is_deeply([$interpreter->Unhandled],[],'a plain entry reports nothing');
}

# Action shape per entry kind. What is asserted here is the interpreter's
# decision - plain, stateful, or disabled - not GTK's behaviour, which
# t/gtk4/60_Menu.t covers against the real Gio.
{	my $interpreter=GMB::Gtk4::Menu->new;
	my $plain=$interpreter->_Action({code=>sub {}},{});
	ok(defined $plain,'an entry with code gets an action');
	is($interpreter->Group->{added}[-1]{state},undef,'a plain entry action is stateless');

	my $checked=$interpreter->_Action({code=>sub {},check=>sub {1}},{});
	is($interpreter->Group->{added}[-1]{state}{boolean},1,'a check entry carries its current state');
	my $unchecked=$interpreter->_Action({code=>sub {},check=>sub {0}},{});
	is($interpreter->Group->{added}[-1]{state}{boolean},0,'an unchecked entry starts inactive');
	isnt($checked,$unchecked,'each entry gets its own action name');

	$interpreter->_Action({code=>sub {},sensitive=>sub {0}},{});
	is($interpreter->Group->{added}[-1]{enabled},0,'an insensitive entry is disabled rather than dropped');
	$interpreter->_Action({code=>sub {},sensitive=>sub {1}},{});
	is($interpreter->Group->{added}[-1]{enabled},undef,'a sensitive entry is left enabled');

	is($interpreter->_Action({label=>'plain'},{}),undef,'an entry with no code needs no action');
}
# toggleoption reads its initial state through the key path, and '!' inverts it.
{	my $interpreter=GMB::Gtk4::Menu->new;
	$interpreter->_Action({toggleoption=>'opt/flag'},{opt=>{flag=>1}});
	is($interpreter->Group->{added}[-1]{state}{boolean},1,'toggleoption reads its state from the key path');
	$interpreter->_Action({toggleoption=>'!opt/flag'},{opt=>{flag=>1}});
	is($interpreter->Group->{added}[-1]{state}{boolean},0,'an inverted toggleoption starts from the negated value');
}

# The key path used by toggleoption, which legacy shares with its preferences.
{	my $args={a=>{b=>{c=>0}}};
	my ($not,$ref)=GMB::Gtk4::Menu::_KeyPath($args,'a/b/c');
	is($not,'','a plain key path is not inverted');
	$$ref=1;
	is($args->{a}{b}{c},1,'a key path returns a writable reference into the arguments');
	my ($negated)=GMB::Gtk4::Menu::_KeyPath($args,'!a/b/c');
	ok($negated,'a leading exclamation mark inverts the reading');
}

done_testing;
