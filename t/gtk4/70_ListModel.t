# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# M1 gate probe: GListModel and selection models at 100,000 rows, and list
# item factory closures and recycling. Three of D006's evidence lines, and the
# measurement D010 needs to choose a SongTree architecture.
#
# This is a feasibility probe, not a renderer test: no layout widget uses any
# of this yet. It answers whether the binding can carry a library-sized model
# at all, what it costs, and which parts of the GTK4 list API are unreachable
# from Perl.

use strict;
use warnings;

use Test::More;
use Time::HiRes ();
use File::Temp ();
use lib '.';

plan skip_all => 'Wayland list-model probe must run through tools/run-gtk4-smoke'
	unless $ENV{GMB_GTK4_SMOKE};

require 'gmusicbrowser_gtk4_binding.pm';
my ($initialized,$reason)=GMB::Gtk4::Binding::try_init();
plan skip_all => $reason unless $initialized;
my $backend=GMB::Gtk4::Binding::backend_probe();
die (($backend->{error} || 'GTK4 display is not Wayland')."\n") unless $backend->{wayland};

ok(!exists $INC{'Gtk3.pm'},'GTK4 list-model probe does not load Gtk3');

# The gate asks for 100,000 rows, which is a plausible large library. Kept
# overridable so a slow machine can still run the suite, but the default is the
# figure the gate names.
my $Rows= $ENV{GMB_GTK4_PROBE_ROWS} || 100_000;

# A song row is not a string, so the probe carries a Perl-defined GObject with
# properties beside the string case. Subclassing an *object* works, unlike the
# widget layout vfunc overrides D006 records as silently ignored.
package GMB::Probe::Song;
use Glib::Object::Subclass 'Glib::Object',
	properties =>
	[	Glib::ParamSpec->string('title','title','title','',[qw/readable writable/]),
		Glib::ParamSpec->uint('sid','sid','sid',0,0xffffffff,0,[qw/readable writable/]),
	];
package main;

# Construction. Probe by calling inside eval, never through ->can, which
# segfaults on an introspected class (D006).
for my $class (qw/Gtk4::StringList Gtk4::SingleSelection Gtk4::MultiSelection
	Gtk4::NoSelection Gtk4::SignalListItemFactory Gtk4::ListView Gtk4::ColumnView
	Gtk4::ColumnViewColumn Gtk4::SortListModel Gtk4::FilterListModel/)
{	ok(!!eval { $class->new },"$class constructs");
}

# CustomFilter and CustomSorter take their callback at construction. A bare
# ->new builds the object but makes GTK complain about the null function, so
# they are constructed with one; both are exercised properly further down.
ok(Gtk4::CustomFilter->new(sub {1}),'Gtk4::CustomFilter constructs with a callback');
ok(Gtk4::CustomSorter->new(sub {0}),'Gtk4::CustomSorter constructs with a callback');

# Gio::ListStore takes the item GType, given as a package name.
ok(!eval { Gio::ListStore->new },'Gio::ListStore->new needs an item type');
ok(Gio::ListStore->new('GMB::Probe::Song'),'Gio::ListStore takes a Perl-defined GObject as its item type');

my $song=GMB::Probe::Song->new(title=>'Song A',sid=>42);
ok($song->isa('Glib::Object'),'a Perl-defined GObject subclass registers');
is($song->get('title'),'Song A','a custom object keeps its string property');
is($song->get('sid'),42,'a custom object keeps its integer property');

# ---- a library-sized model ----------------------------------------------

my $t0=Time::HiRes::time();
my $strings=Gtk4::StringList->new([]);
$strings->append(sprintf 'Song %05d',($_*7919)%$Rows) for 1..$Rows;
my $build_strings=Time::HiRes::time()-$t0;
is($strings->get_n_items,$Rows,"a StringList holds $Rows rows");
diag(sprintf 'StringList: %d rows appended in %.2fs',$Rows,$build_strings);

$t0=Time::HiRes::time();
my $store=Gio::ListStore->new('GMB::Probe::Song');
$store->append(GMB::Probe::Song->new(title=>"Song $_",sid=>($_*7919)%$Rows)) for 1..$Rows;
my $build_store=Time::HiRes::time()-$t0;
is($store->get_n_items,$Rows,"a Gio::ListStore holds $Rows custom objects");
diag(sprintf 'Gio::ListStore: %d objects appended in %.2fs',$Rows,$build_store);

# Random access has to stay cheap; a song list reads by row constantly.
is($strings->get_item(0)->get_string,'Song 07919','row 0 reads back');
is($store->get_item(0)->get('sid'),7919,'a custom object reads back by index');
is($store->get_item($Rows-1)->get('sid'),0,'the last row reads back by index');
isa_ok($store->get_item(500),'GMB::Probe::Song','an item comes back blessed into its own package');

$t0=Time::HiRes::time();
my $hits=0;
for (1..1000) { $hits++ if $strings->get_item(int rand $Rows) }
my $random=Time::HiRes::time()-$t0;
is($hits,1000,'1000 random reads all resolve');
cmp_ok($random,'<',1,'1000 random reads stay well under a second');
diag(sprintf '1000 random get_item: %.4fs',$random);

# ---- selection models ----------------------------------------------------

my $single=Gtk4::SingleSelection->new($strings);
is($single->get_n_items,$Rows,"SingleSelection wraps $Rows rows");
$single->set_selected(90_000 % $Rows);
is($single->get_selected,90_000 % $Rows,'SingleSelection tracks the selected row');

my $multi=Gtk4::MultiSelection->new($strings);
$multi->select_range(0,50_000,0);
is($multi->get_selection->get_size,50_000,'MultiSelection carries a 50,000-row selection');
ok($multi->is_selected(0),'the first row of the range is selected');
ok(!$multi->is_selected(50_000),'the row past the range is not selected');

# ---- factory closures and recycling -------------------------------------

my %Count;
my $factory=Gtk4::SignalListItemFactory->new;
$factory->signal_connect(setup => sub
	{	my (undef,$item)=@_;
		$Count{setup}++;
		$item->set_child(Gtk4::Label->new(''));
	});
$factory->signal_connect(bind => sub
	{	my (undef,$item)=@_;
		$Count{bind}++;
		my ($child,$object)=($item->get_child,$item->get_item);
		$child->set_text($object->get_string) if $child && $object;
	});
$factory->signal_connect(unbind => sub { $Count{unbind}++ });
$factory->signal_connect(teardown => sub { $Count{teardown}++ });

my ($ScrolledUp,$ScrolledBind,$Upper,$AdjustmentOnly);
my $app=Gtk4::Application->new('org.gmusicbrowser.Gtk4ListModelProbe',['non-unique']);
$app->signal_connect(activate => sub
{	my $application=shift;
	my $window=Gtk4::ApplicationWindow->new($application);
	my $view=Gtk4::ListView->new(Gtk4::SingleSelection->new($strings),$factory);
	my $scrolled=Gtk4::ScrolledWindow->new;
	$scrolled->set_child($view);
	$window->set_default_size(400,600);
	$window->set_child($scrolled);
	$window->present;

	Glib::Idle->add(sub
	{	my $context=Glib::MainContext->default;
		$context->iteration(0) for 1..500;

		# The whole point of the factory: a viewport's worth of widgets, not one
		# per row. Recorded before scrolling so the recycling delta is honest.
		$ScrolledUp=$Count{setup};
		$ScrolledBind=$Count{bind};

		my $adjustment=$scrolled->get_vadjustment;
		$Upper=$adjustment->get_upper;

		# scroll_to is what actually moves a ListView. Driving the enclosing
		# ScrolledWindow's adjustment instead changes its value and nothing else:
		# the view stays where it was and never rebinds a row. That is worth an
		# assertion of its own, because the adjustment looks like it worked.
		$adjustment->set_value($adjustment->get_upper - $adjustment->get_page_size);
		$context->iteration(0) for 1..500;
		$AdjustmentOnly=$Count{bind};

		$view->scroll_to($Rows-1,'none',undef);
		$context->iteration(0) for 1..500;

		$application->quit;
		return 0;
	});
});
$app->run([]);

cmp_ok($ScrolledUp,'>',0,'the factory built at least one row widget');
cmp_ok($ScrolledUp,'<',1000,"the factory builds a viewport's worth of widgets, not $Rows");
is($ScrolledUp,$ScrolledBind,'every widget the factory sets up is also bound');
cmp_ok($Upper,'>',$Rows,"the scrolled height covers all $Rows rows");
diag(sprintf 'factory: %d widgets for %d rows, scroll height %.0f',$ScrolledUp,$Rows,$Upper);

is($AdjustmentOnly,$ScrolledBind,'moving the ScrolledWindow adjustment alone rebinds nothing');

# Scrolling to the far end must reuse those widgets rather than build more.
cmp_ok($Count{bind},'>',$ScrolledBind,'scroll_to rebinds row widgets');
cmp_ok($Count{setup}-$ScrolledUp,'<',$Count{bind}-$ScrolledBind,
	'scrolling rebinds far more rows than it builds new widgets');
cmp_ok($Count{unbind},'>',0,'a recycled row widget is unbound before it is rebound');
diag(sprintf 'after scroll_to row %d: setup=%d bind=%d unbind=%d',
	$Rows-1,$Count{setup},$Count{bind},$Count{unbind});

# ---- what is NOT reachable from Perl ------------------------------------

# GtkExpression is unmarshallable, in the same way as GdkEvent and the graphene
# types (D006). StringSorter, NumericSorter and StringFilter all select their
# value through an expression, so they construct but cannot be configured.
ok(!eval { Gtk4::PropertyExpression->new('Gtk4::StringObject',undef,'string') },
	'GtkExpression cannot be constructed through this binding');
like($@,qr/GtkExpression/,'the expression failure names the GtkExpression type');
ok(!eval { Gtk4::StringSorter->new->get_expression; 1 },
	'a sorter will not hand back its expression either');

# An expression-less StringSorter is not a fallback: it leaves the order alone.
my $unsorted=Gtk4::StringList->new([]);
$unsorted->append("Song $_") for (5,3,1,4,2);
my $sorted=Gtk4::SortListModel->new($unsorted,Gtk4::StringSorter->new);
Glib::MainContext->default->iteration(0) for 1..200;
is_deeply([map {$sorted->get_item($_)->get_string} 0..4],
	['Song 5','Song 3','Song 1','Song 4','Song 2'],
	'a StringSorter with no expression does not sort at all');

# CustomSorter is the documented escape hatch and it does not work: the two
# items to compare arrive as undef, so no Perl comparison is possible.
my @SorterArgs;
my $custom=Gtk4::CustomSorter->new(sub { push @SorterArgs,[@_]; 0 });
Gtk4::SortListModel->new($unsorted,$custom);
cmp_ok(scalar @SorterArgs,'>',0,'a CustomSorter callback is actually invoked');
is_deeply($SorterArgs[0],[undef,undef,undef],'a CustomSorter receives undef instead of the two items');

# CustomFilter, by contrast, does receive its item, so filtering in Perl works.
my @FilterArgs;
my $filter=Gtk4::CustomFilter->new(sub { push @FilterArgs,$_[0]; $_[0]->get_string=~m/[13]$/ });
my $filtered=Gtk4::FilterListModel->new($unsorted,$filter);
isa_ok($FilterArgs[0],'Gtk4::StringObject','a CustomFilter receives the item itself');
is($filtered->get_n_items,2,'a Perl CustomFilter selects rows');

# Gio::ListStore::splice does not marshal an array of custom GObjects: it passes
# nulls and GIO leaves the store in what it calls an undefined state. Nothing
# raises a Perl error, so a port would see only an empty model. The store is
# also unrecoverable -- in a process holding other GTK objects, freeing it
# segfaults, which is why this runs in a child: triggering it here takes the
# whole suite down several assertions after the call that caused it. Append in
# a loop instead; the cost is measured below.
{	my $script=File::Temp->new(SUFFIX=>'.pl');
	print $script <<'CHILD';
use lib '.';
require 'gmusicbrowser_gtk4_binding.pm';
GMB::Gtk4::Binding::try_init();
GMB::Gtk4::Binding::backend_probe();
package GMB::Probe::Child;
use Glib::Object::Subclass 'Glib::Object',
	properties => [Glib::ParamSpec->uint('sid','sid','sid',0,0xffffffff,0,[qw/readable writable/])];
package main;
my $store=Gio::ListStore->new('GMB::Probe::Child');
$store->splice(0,0,[map {GMB::Probe::Child->new(sid=>$_)} 1..8]);
print 'n=',$store->get_n_items,"\n";
CHILD
	close $script;
	my $output=`$^X -I. $script 2>&1`;
	like($output,qr/^n=0$/m,'Gio::ListStore::splice drops an array of custom objects');
	like($output,qr/GListStore is now in an undefined state/,
		'GIO reports the store undefined rather than raising a Perl error');
}

# The route that does work, and its cost: sort in Perl, rebuild the model.
my @objects=map {GMB::Probe::Song->new(sid=>($_*7919)%$Rows)} 1..$Rows;
$t0=Time::HiRes::time();
my @ordered=sort {$a->get('sid') <=> $b->get('sid')} @objects;
my $sort_time=Time::HiRes::time()-$t0;
$t0=Time::HiRes::time();
$store->remove_all;
$store->append($_) for @ordered;
my $reload=Time::HiRes::time()-$t0;
is($store->get_n_items,$Rows,'the model reloads at full size');
is($store->get_item(0)->get('sid'),0,'the reloaded model is in the sorted order');
is($store->get_item($Rows-1)->get('sid'),$Rows-1,'the last reloaded row is the largest key');
cmp_ok($sort_time+$reload,'<',10,'a Perl sort plus a full model reload stays interactive');
diag(sprintf 'perl sort %.2fs + remove_all/append %.2fs for %d rows',$sort_time,$reload,$Rows);

# items-changed is what a view listens to, so a port can drive updates from it.
my $changed=0;
$store->signal_connect('items-changed' => sub { $changed++ });
$store->remove(0);
$store->append(GMB::Probe::Song->new(sid=>7));
is($changed,2,'items-changed fires for each model mutation');

done_testing();
