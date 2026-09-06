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

plan skip_all => 'Wayland proof must run through tools/run-gtk4-smoke'
	unless $ENV{GMB_GTK4_SMOKE};

require 'gmusicbrowser_gtk4_binding.pm';
my ($initialized,$reason)=GMB::Gtk4::Binding::try_init();
plan skip_all => $reason unless $initialized;

local $ENV{GMB_GTK4_LAYOUT_FILE}=File::Spec->catfile('t','layouts','proof.layout');
my ($pid,$output,$timedout,$exitstatus);
$pid=open my $proof,'-|',$^X,'gmusicbrowser_gtk4.pl';
ok($pid,'GTK4 proof process started');
if ($pid)
{	local $SIG{ALRM}=sub
	{	$timedout=1;
		kill 'TERM',$pid;
	};
	alarm 20;
	{ local $/; $output=<$proof>; }
	close $proof;
	$exitstatus=$? >> 8;
	alarm 0;
}
ok(!$timedout,'GTK4 proof process completed before timeout');
is($exitstatus,0,'GTK4 proof process exited successfully') unless $timedout;
like($output || '',qr/^GTK4_PROOF backend=wayland layout=gtk4 proof action=PlayPause gtk3=absent$/m,
	'GTK4 application, layout, action, and frontend boundary passed on Wayland');

done_testing;
