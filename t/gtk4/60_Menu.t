# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# The menu interpreter against the real Gio model and a real PopoverMenu
# (D038). t/07_Gtk4Menu.t covers the conditional and structural logic offline;
# what needs a display is that the model is actually built, that the actions
# fire, and that rebuilding per popup works, which is what preserves the
# legacy dynamic behaviour.

use strict;
use warnings;

use Test::More;
use lib '.';

plan skip_all => 'Wayland menu test must run through tools/run-gtk4-smoke'
	unless $ENV{GMB_GTK4_SMOKE};

require 'gmusicbrowser_gtk4_binding.pm';
my ($initialized,$reason)=GMB::Gtk4::Binding::try_init();
plan skip_all => $reason unless $initialized;
my $backend=GMB::Gtk4::Binding::backend_probe();
die (($backend->{error} || 'GTK4 display is not Wayland')."\n") unless $backend->{wayland};

require 'gmusicbrowser_frontend.pm';
require 'gmusicbrowser_gtk4_menu.pm';

ok(!exists $INC{'Gtk3.pm'},'GTK4 menu test does not load Gtk3');

my @dispatched;
my $frontend=GMB::Frontend->new
(	commands=>{ Stop=>sub { push @dispatched,'Stop'; return 1 } },
);

my @ran;
my $menu=GMB::Gtk4::Menu->new(frontend=>$frontend);

my $definition=
[	{label=>'Play',		code=>sub { push @ran,'play' }},
	{label=>'Disabled',	code=>sub { push @ran,'never' }, sensitive=>sub {0}},
	{separator=>1},
	{label=>'Checked',	code=>sub { push @ran,"check=$_[1]" }, check=>sub {1}},
	{label=>'Command',	code=>'Stop'},
	{label=>'Skipped',	code=>sub { push @ran,'never' }, ignore=>1},
	{label=>'Sub',		submenu=>[{label=>'Inner',code=>sub { push @ran,'inner' }}]},
];

my $model=$menu->Build($definition,{});
isa_ok($model,'Gio::Menu','Build returns a Gio menu model');
# Two sections: the entries before the separator and those after it. An empty
# section appended at the separator would instead leave the later entries at the
# top level and count itself as an item, which is what the first attempt did.
is($model->get_n_items,2,'a separator splits the model into two sections');
my $first=$model->get_item_link(0,'section');
my $second=$model->get_item_link(1,'section');
is($first->get_n_items,2,'the first section holds the entries before the separator');
# Checked, Command and Sub; the ignored entry contributes nothing.
is($second->get_n_items,3,'the second section holds the entries after it');

# No separator means no sections at all, so the common menu stays flat.
{	my $flat=GMB::Gtk4::Menu->new(frontend=>$frontend)->Build([{label=>'A'},{label=>'B'}],{});
	is($flat->get_n_items,2,'a definition with no separator builds a flat model');
	ok(!defined $flat->get_item_link(0,'section'),'a flat model has no section links');
}

my $group=$menu->Group;
isa_ok($group,'Gio::SimpleActionGroup','the interpreter owns an action group');
my @names=sort @{$group->list_actions};
is(scalar @names,5,'one action per entry that carries code, and none for the rest')
	or diag("actions: @names");

# Sensitivity is an action property in GTK4, not an item property.
my @disabled=grep !$group->get_action_enabled($_),@names;
is(scalar @disabled,1,'exactly one action is disabled');

# Firing. activate_action is how a popover item reaches the action.
my ($enabled)=grep $group->get_action_enabled($_),@names;
$group->activate_action($enabled,undef);
cmp_ok(scalar @ran,'>',0,'activating an action runs the entry code');

# A string code is a command name and must go through the frontend contract
# rather than being called, since the renderer has no run_command.
for my $name (@names)
{	next unless $group->get_action_enabled($name);
	my $state=$group->get_action_state($name);
	next if $state;			# leave the stateful ones to the change-state path
	$group->activate_action($name,undef);
}
ok(scalar(grep $_ eq 'Stop',@dispatched),'a string code dispatches through the frontend');

# A stateful action is what a check item becomes, and it starts from the
# entry's own check callback rather than from a default.
my ($stateful)=grep { my $s=$group->get_action_state($_); $s && $s->get_boolean } @names;
ok($stateful,'a check entry becomes a stateful action that starts active');

# The model drives a real popover.
my $app=Gtk4::Application->new('org.gmusicbrowser.Gtk4MenuTest',['non-unique']);
my $popped=0;
$app->signal_connect(activate => sub
{	my $application=shift;
	my $window=Gtk4::ApplicationWindow->new($application);
	my $label=Gtk4::Label->new('menu');
	$window->set_child($label);
	$window->insert_action_group($menu->Prefix,$group);
	$window->present;
	my $popover=Gtk4::PopoverMenu->new_from_model($model);
	$popover->set_parent($label);
	Glib::Idle->add(sub
	{	$popover->popup;
		$popped=1;
		$popover->popdown;
		$popover->unparent;
		$application->quit;
		return 0;
	});
});
$app->run([]);
ok($popped,'the model drives a real PopoverMenu');

# Rebuilding per popup is what keeps the dynamic behaviour, so the second build
# must see the new state and must not accumulate actions from the first.
my $visible=0;
my $dynamic=[{label=>'Conditional',code=>sub {},test=>sub { $visible }}];
my $rebuilt=GMB::Gtk4::Menu->new(frontend=>$frontend);
is($rebuilt->Build($dynamic,{})->get_n_items,0,'a failing condition yields no item');
$visible=1;
is($rebuilt->Build($dynamic,{})->get_n_items,1,'rebuilding after the state changed yields the item');
is(scalar @{$rebuilt->Group->list_actions},1,'a rebuild replaces the previous actions rather than adding to them');

# BuildOptional is legacy BuildMenuOptional: an empty menu is undef so a dead
# submenu never appears.
ok(!defined $rebuilt->BuildOptional([{label=>'x',ignore=>1}],{}),'an entirely filtered definition builds no menu');
ok(defined $rebuilt->BuildOptional([{label=>'x'}],{}),'a definition with an item builds a menu');

# A definition shaped like a real one. The synthetic fixtures above missed a
# dispatch bug that this shape exposed: legacy sends an entry carrying 'code'
# to BuildChoiceMenu whatever its submenu's type, and an ordered_hash submenu is
# an array of alternating labels and values rather than a definition, so a port
# that dispatched on the submenu's type instead read 'Main' as a menu entry.
{	my $playing=0;
	my $tray=
	[	{label=>sub { $playing ? 'Pause' : 'Play' }, code=>sub {}, id=>'playpause'},
		{label=>'Stop', code=>sub {}},
		{label=>'Recently played', submenu=>sub { undef }},
		{label=>'Windows', code=>sub {}, submenu_ordered_hash=>1,
			submenu=>sub { ['Main','w1','Queue','w2'] }},
		{label=>'Quit', code=>sub {}},
	];
	my $interpreter=GMB::Gtk4::Menu->new(frontend=>$frontend);
	my $built=$interpreter->Build($tray,{});
	is($built->get_n_items,4,'a submenu returning undef is dropped, the rest are kept');
	is($built->get_item_attribute_value(0,'label',undef)->get_string,'Play','a dynamic label resolves against current state');
	my $windows=$built->get_item_link(2,'submenu');
	ok($windows,'an ordered_hash submenu builds');
	is($windows->get_n_items,2,'an ordered_hash submenu pairs labels with values');
	is($windows->get_item_attribute_value(0,'label',undef)->get_string,'Main','the ordered hash keeps its label as the label');

	$playing=1;
	my $again=$interpreter->Build($tray,{});
	is($again->get_item_attribute_value(0,'label',undef)->get_string,'Pause','rebuilding picks up the new state');
}

done_testing();
