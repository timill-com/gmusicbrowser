# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

package GMB::Gtk4::Binding;
use strict;
use warnings;

our $VERSION='0.01';

my $Initialized;
my ($InitError,$InitDetail);

my @Namespaces=
(
	[Gio => '2.0', 'Gio'],
	[Gtk => '4.0', 'Gtk4'],
	[Gdk => '4.0', 'Gtk4::Gdk'],
	[Gsk => '4.0', 'Gtk4::Gsk'],
);

sub init
{	return 1 if $Initialized;
	die "$InitError\n" if defined $InitError;

	my @missing;
	eval { require Glib; 1 } or push @missing, 'Glib';
	eval { require Glib::Object::Introspection; 1 }
		or push @missing, 'Glib::Object::Introspection';
	if (@missing)
	{	$InitError='Gtk4 binding prerequisites unavailable: Perl module'.(@missing>1 ? 's ' : ' ').join(' and ',@missing).' not installed';
		die "$InitError\n";
	}

	my @failed;
	for my $namespace (@Namespaces)
	{	my ($basename,$version,$package)=@$namespace;
		my $ok=eval
		{	Glib::Object::Introspection->setup
			(	basename => $basename,
				version => $version,
				package => $package,
			);
			1;
		};
		next if $ok;
		push @failed, "$basename-$version";
		$InitDetail.="$basename-$version: $@";
	}
	if (@failed)
	{	$InitError='Gtk4 binding prerequisites unavailable: GObject Introspection namespace'.(@failed>1 ? 's ' : ' ').join(', ',@failed).' not installed';
		die "$InitError\n";
	}

	my $major=eval { Gtk4::get_major_version() };
	unless (defined $major && $major==4)
	{	$InitError='Gtk4 binding initialization failed: loaded Gtk namespace is not GTK 4';
		die "$InitError\n";
	}
	$Initialized=1;
	return 1;
}

sub try_init
{	my $ok=eval { init(); 1 };
	return wantarray ? ($ok || 0, $ok ? undef : $InitError) : $ok || 0;
}

sub init_error
{	return $InitError;
}

sub init_detail
{	return $InitDetail;
}

sub version_probe
{	return undef unless $Initialized;
	my %version=
	(	perl => sprintf('%vd',$^V),
		glib => $Glib::VERSION,
		introspection => $Glib::Object::Introspection::VERSION,
	);
	$version{gtk}=join '.', map { $_->() }
		\&Gtk4::get_major_version, \&Gtk4::get_minor_version, \&Gtk4::get_micro_version;
	return \%version;
}

sub backend_probe
{	my %probe=
	(	requested => $ENV{GDK_BACKEND} || '',
		session => $ENV{XDG_SESSION_TYPE} || '',
		wayland_display => $ENV{WAYLAND_DISPLAY} || '',
	);
	unless ($Initialized)
	{	$probe{error}='Gtk4 binding is not initialized';
		return \%probe;
	}

	my $ok=eval { Gtk4::init(); 1 };
	unless ($ok)
	{	$probe{error}="GTK initialization failed: $@";
		return \%probe;
	}
	my $display=Gtk4::Gdk::Display::get_default();
	unless ($display)
	{	$probe{error}='GTK did not open a display';
		return \%probe;
	}
	$probe{class}=ref $display;
	$probe{name}=eval { $display->get_name } || '';
	$probe{wayland}=1 if $probe{class}=~m/Wayland/i;
	$probe{wayland}=1 if $probe{requested} eq 'wayland' &&
		$probe{wayland_display} ne '' && $probe{name} eq $probe{wayland_display};
	return \%probe;
}

1
