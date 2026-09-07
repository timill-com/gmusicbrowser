# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# M1 gate probe: click, motion, scroll, keyboard, and context-menu controllers.
# This file answers whether the binding can carry the legacy input surface at
# all. It is a feasibility probe, not a renderer test: nothing here asserts that
# a layout option is wired up, only that the mechanism a port would use exists,
# fires, and can be taken back off a widget again.

use strict;
use warnings;

use Test::More;
use lib '.';

plan skip_all => 'Wayland input probe must run through tools/run-gtk4-smoke'
	unless $ENV{GMB_GTK4_SMOKE};

require 'gmusicbrowser_gtk4_binding.pm';
my ($initialized,$reason)=GMB::Gtk4::Binding::try_init();
plan skip_all => $reason unless $initialized;
my $backend=GMB::Gtk4::Binding::backend_probe();
die (($backend->{error} || 'GTK4 display is not Wayland')."\n") unless $backend->{wayland};

ok(!exists $INC{'Gtk3.pm'},'GTK4 input probe does not load Gtk3');

# Construction. Probe by calling inside eval, never through ->can, which
# segfaults on an introspected class (D006).
my %Constructed;
for my $class (qw/Gtk4::GestureClick Gtk4::GestureSingle Gtk4::GestureDrag
	Gtk4::GestureLongPress Gtk4::EventControllerKey Gtk4::EventControllerMotion
	Gtk4::EventControllerFocus Gtk4::ShortcutController Gtk4::DragSource
	Gtk4::PopoverMenu Gtk4::Popover/)
{	my $object=eval { $class->new };
	$Constructed{$class}=1 if $object;
	ok($object,"$class constructs");
}

# Two take mandatory arguments, like Gtk4::Constraint (D006). A bare ->new
# reports 'passed too few parameters' rather than returning undef.
ok(!eval { Gtk4::EventControllerScroll->new },'EventControllerScroll->new needs scroll flags');
ok(Gtk4::EventControllerScroll->new('vertical'),'EventControllerScroll takes a flags argument');
ok(!eval { Gtk4::DropTarget->new },'DropTarget->new needs a type and actions');
ok(Gtk4::DropTarget->new('Glib::String','copy'),'DropTarget takes a type and actions');

my @Fired;
my $Gesture;
my $app=Gtk4::Application->new('org.gmusicbrowser.Gtk4InputProbe',['non-unique']);
$app->signal_connect(activate => sub
{	my $application=shift;
	my $window=Gtk4::ApplicationWindow->new($application);
	my $label=Gtk4::Label->new('probe');
	$window->set_child($label);

	# A widget carries controllers of its own before anything is added, and how
	# many depends on its type, so a test must identify a controller rather than
	# count them.
	my %baseline;
	for my $probe (['Gtk4::Label',Gtk4::Label->new('x')],['Gtk4::Box',Gtk4::Box->new('vertical',0)])
	{	$baseline{$probe->[0]}=$probe->[1]->observe_controllers->get_n_items;
	}
	is($baseline{'Gtk4::Box'},0,'a plain box starts with no controllers');
	cmp_ok($baseline{'Gtk4::Label'},'>',0,'a label starts with a controller of its own');

	# The legacy contract keys actions on the button number
	# (gmusicbrowser_layout.pm:1284, 'click'.$event->button), so per-button
	# filtering is what a port needs.
	my %gesture;
	for my $button (1,2,3)
	{	my $gesture=Gtk4::GestureClick->new;
		$gesture->set_button($button);
		$gesture->signal_connect(pressed => sub { push @Fired,"click$button" });
		$label->add_controller($gesture);
		$gesture{$button}=$gesture;
	}
	is($gesture{3}->get_button,3,'a click gesture filters on its button number');
	is($gesture{1}->get_button,1,'each click gesture keeps its own button number');

	my $motion=Gtk4::EventControllerMotion->new;
	$motion->signal_connect(enter => sub { push @Fired,'enter' });
	$motion->signal_connect(leave => sub { push @Fired,'leave' });
	$label->add_controller($motion);

	my $scroll=Gtk4::EventControllerScroll->new('vertical');
	$scroll->signal_connect(scroll => sub { my (undef,$dx,$dy)=@_; push @Fired,"scroll:$dx,$dy"; 1 });
	$label->add_controller($scroll);

	my $key=Gtk4::EventControllerKey->new;
	$key->signal_connect('key-pressed' => sub { my (undef,$keyval)=@_; push @Fired,"key:$keyval"; 1 });
	$window->add_controller($key);

	$window->present;
	Glib::Idle->add(sub
	{	$gesture{$_}->signal_emit('pressed',1,0,0) for 1,2,3;
		$scroll->signal_emit('scroll',0,-1);
		$key->signal_emit('key-pressed',0x20,65,[]);

		# A synthetic emission has no GDK event behind it, so the gesture reports
		# button 0 however it was filtered. A port must therefore read the button
		# from the gesture it registered, never from the event.
		is($gesture{3}->get_current_button,0,'a synthetic press carries no current button');

		my $controllers=$label->observe_controllers;
		my $before=$controllers->get_n_items;
		$label->remove_controller($gesture{2});
		is($label->observe_controllers->get_n_items,$before-1,'a controller can be removed again');

		$Gesture=$gesture{3};
		$application->quit;
		return 0;
	});
});
$app->run([]);

# GdkEvent is not marshallable through this binding, in the same way as the
# graphene types (D006). Checked outside the signal handler on purpose: inside
# one, Glib catches the error and prints 'unhandled exception in callback' to
# stderr, so an eval there would pass without ever seeing the failure.
ok(!eval { $Gesture->get_current_event; 1 },'the current GDK event is not marshallable');
like($@,qr/GdkEvent/,'reading the current event fails on the GdkEvent type itself');

is_deeply([grep m/^click/,@Fired],[qw/click1 click2 click3/],'each button gesture fires separately');
is_deeply([grep m/^scroll/,@Fired],['scroll:0,-1'],'a scroll controller delivers its deltas');
is_deeply([grep m/^key/,@Fired],['key:32'],'a key controller delivers its keyval');

done_testing();
