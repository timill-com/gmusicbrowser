# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;

use Test::More;
use lib '.';

require 'gmusicbrowser_gtk4_binding.pm';

my ($initialized,$reason)=GMB::Gtk4::Binding::try_init();
plan skip_all => $reason unless $initialized;

ok($initialized, 'Gtk4 binding initialized');
ok(Gio::Application->can('run'), 'Gio 2.0 application package loaded');
ok(Gtk4::Application->can('new'), 'Gtk 4.0 package loaded');
ok(Gtk4::Application->can('run'), 'Gtk4 application inherits Gio methods');
ok(Gtk4::Gdk::Display->can('get_default'), 'Gdk 4.0 package loaded');
ok(Gtk4::Gsk::Renderer->can('new_for_surface'), 'Gsk 4.0 package loaded');
ok(!exists $INC{'Gtk3.pm'}, 'Gtk3 binding not loaded');

my $version=GMB::Gtk4::Binding::version_probe();
ok($version->{perl}, 'Perl version probed');
ok($version->{glib}, 'GLib version probed');
ok($version->{introspection}, 'introspection version probed');
like($version->{gtk},qr/^4\./,'GTK4 version probed');

SKIP:
{	skip 'Wayland backend probe requires tools/run-gtk4-smoke',1
		unless $ENV{GMB_GTK4_SMOKE};
	my $backend=GMB::Gtk4::Binding::backend_probe();
	ok($backend->{wayland},'GTK4 display uses Wayland')
		or diag($backend->{error} || "display=$backend->{name} class=$backend->{class}");
}

SKIP: { skip 'BLOCKED: 100,000-row GListModel/ListView proof is not implemented',1; }
SKIP: { skip 'BLOCKED: custom widget/drawing proof is not implemented',1; }
ok(!!eval { Gtk4::GestureClick->new },'click, motion, scroll, and keyboard controllers are proven in t/gtk4/50_Input.t');
SKIP: { skip 'BLOCKED: drag-and-drop proof is not implemented',1; }
SKIP: { skip 'BLOCKED: asynchronous finish/error propagation proof is not implemented',1; }
SKIP: { skip 'BLOCKED: GLib/GStreamer loop coexistence proof is not implemented',1; }

done_testing();
