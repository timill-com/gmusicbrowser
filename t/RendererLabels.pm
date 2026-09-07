# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# The GTK4 renderer takes every user-visible string from its caller, and its
# constructor rejects a labels hash missing any %Buttons tooltip. Tests share
# one definition so adding a widget does not mean editing every call site.
# The values match the %Layout::Widgets tips in gmusicbrowser_layout.pm, which
# is what pins a tooltip assertion to the right widget entry.

use strict;
use warnings;

package GMB::Test::RendererLabels;

my %Labels=
(	play	=> 'Play',
	pause	=> 'Pause',
	quit	=> 'Quit',
	stop	=> 'Stop',
	next	=> 'Next Song',
	prev	=> 'Recently played songs',
);

sub labels { return {%Labels} }

1
