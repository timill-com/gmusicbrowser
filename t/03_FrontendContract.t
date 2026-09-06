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

BEGIN { use_ok('gmusicbrowser_frontend'); }

my $playing=0;
my @lifecycle;
my $frontend;
$frontend=GMB::Frontend->new
(	commands =>
	{	Echo =>
		{	code => sub { return (defined $_[0] ? $_[0] : '').':'.$_[1]{source}; },
		},
	},
	state =>
	{	Playing => sub {$playing},
		Name => 'gmusicbrowser',
	},
	lifecycle =>
	{	startup => sub { push @lifecycle,'startup:'.$_[0]{profile}; return 'started'; },
		activate => sub { push @lifecycle,'activate:'.$_[0]{reason}; },
		open => sub { push @lifecycle,'open:'.join(',',@{$_[0]{uris}}); },
		shutdown => sub
		{	push @lifecycle,'shutdown:prepare';
			my $result=$frontend->Emit(Quit=>{});
			die "$result->{error}\n" unless $result->{ok};
			push @lifecycle,'shutdown:finish';
			return 'stopped';
		},
	},
);

is($frontend->State('Playing'),0,'state provider is read');
$playing=1;
is($frontend->State('Playing'),1,'state provider remains live');
is($frontend->State('Name'),'gmusicbrowser','direct state is read');
is($frontend->State('Missing'),undef,'unknown state is undef');

my $parsed=$frontend->ParseCommand('SetSongRating(+10)');
is_deeply($parsed,
	{ok=>1,name=>'SetSongRating',argument=>'+10',command=>'SetSongRating(+10)'},
	'exact legacy command spelling is parsed');
is($frontend->ParseCommand('SetSongRating +10')->{command},'SetSongRating(+10)','historic space spelling is normalized');
is($frontend->ParseCommand('setsongrating(+10)')->{name},'setsongrating','command name case is preserved');
is($frontend->ParseCommand('bad-name()')->{ok},0,'invalid command spelling is rejected');

is_deeply($frontend->Dispatch('Echo','hello',{source=>'test'}),{ok=>1,value=>'hello:test'},'command is dispatched');
is_deeply($frontend->Dispatch('Echo(world)',undef,{source=>'test'}),{ok=>1,value=>'world:test'},'legacy command spelling is dispatched');
is_deeply($frontend->Dispatch('Missing',undef,{}),{ok=>0,error=>"Unknown command 'Missing'"},'unknown command has stable error');
is($frontend->Dispatch('Echo',undef,{source=>'test'})->{value},':test','undef argument is preserved');
is($frontend->Dispatch('Echo','hello',[])->{error},'Invalid context: must be a hash','context must be a hash');

$frontend->RegisterCommand(name=>'Failure',code=>sub {die "deliberate failure\n"});
like($frontend->Dispatch('Failure',undef,{})->{error},qr/^Command 'Failure' failed: deliberate failure$/,'command exceptions are returned');

{	package Local::Widget;
	sub new { bless {},shift }
}
my $widget=Local::Widget->new;
like($frontend->Dispatch('Echo','hello',{nested=>[{widget=>$widget}]})->{error},qr/^Invalid context: blessed value at context\.nested\[0\]\.widget$/,'blessed context value is rejected recursively');
like($frontend->Dispatch('Echo','hello',{callback=>sub {}})->{error},qr/^Invalid context: unsupported reference at context\.callback$/,'non-data context reference is rejected');
my $cycle={}; $cycle->{cycle}=$cycle;
like($frontend->Dispatch('Echo','hello',$cycle)->{error},qr/^Invalid context: cyclic value at context\.cycle$/,'cyclic context is rejected');

my @events;
my $first=$frontend->Subscribe(Playing => sub { push @events,$_[0].':first:'.$_[1]{playing}; });
my $second=$frontend->Subscribe(Playing => sub { push @events,$_[0].':second:'.$_[1]{playing}; });
is_deeply($frontend->Emit(Playing=>{playing=>1}),{ok=>1,value=>undef},'event is emitted synchronously');
is_deeply(\@events,['Playing:first:1','Playing:second:1'],'event callbacks use registration order and event-first arguments');
ok($frontend->Unsubscribe($first),'subscription is removed by opaque token');
ok(!$frontend->Unsubscribe($first),'removed token cannot be removed twice');
$frontend->Emit(Playing=>{playing=>0});
is_deeply(\@events,['Playing:first:1','Playing:second:1','Playing:second:0'],'unsubscribed callback is not called');
ok($frontend->Unsubscribe($second),'second subscription is removed');
like($frontend->Emit(Playing=>{widget=>$widget})->{error},qr/^Invalid event payload: blessed value/,'event payload must be data-only');

is_deeply($frontend->Activate({reason=>'early'}),{ok=>0,error=>"Lifecycle 'activate' requires Startup"},'activate requires startup');
is_deeply($frontend->Shutdown({reason=>'early'}),{ok=>0,error=>"Lifecycle 'shutdown' requires Activate"},'shutdown requires activation');
like($frontend->Startup({profile=>[],extra=>1})->{error},qr/^Invalid startup data: unknown key 'extra'$/,'unknown lifecycle keys are rejected before field values');
is($frontend->Startup({profile=>[]})->{error},'Invalid startup data: profile must be a scalar','startup profile must be a scalar');
is_deeply($frontend->Startup({profile=>'test'}),{ok=>1,value=>'started'},'startup hook runs');
is_deeply($frontend->Startup({profile=>'ignored'}),{ok=>1,value=>'started'},'successful startup is idempotent');
is($frontend->Activate({hidden=>2})->{error},'Invalid activate data: hidden must be 0 or 1','activate hidden state is validated');
is_deeply($frontend->Open({uris=>['file:///early']}),{ok=>0,error=>"Lifecycle 'open' requires Activate"},'open requires activation');
is_deeply($frontend->Shutdown({reason=>'not-active'}),{ok=>0,error=>"Lifecycle 'shutdown' requires Activate"},'shutdown still requires activation after startup');
like($frontend->Open({uris=>[$widget]})->{error},qr/^Invalid open data: blessed value/,'lifecycle arguments must be data-only');
is($frontend->Open({uris=>'file:///one'})->{error},'Invalid open data: uris must be an array','Open uris must be an array');
is($frontend->Open({uris=>['']})->{error},'Invalid open data: uris must contain non-empty scalars','Open uris must be non-empty scalars');
like($frontend->Open({disposition=>'replace'})->{error},qr/^Invalid open data: unknown disposition 'replace'$/,'Open disposition is validated');
like($frontend->Open({source=>'socket'})->{error},qr/^Invalid open data: unknown source 'socket'$/,'Open source is validated');
is($frontend->Activate({reason=>'user'})->{ok},1,'first activate hook runs');
is($frontend->Activate({reason=>'application'})->{ok},1,'activate hook may run again');
is($frontend->Open({uris=>['file:///one','sftp://host/two']})->{ok},1,'open hook runs with data');
is($frontend->Open({uris=>['file:///three']})->{ok},1,'open hook may run again');
my $quit=$frontend->Subscribe(Quit => sub { push @lifecycle,'quit'; });
is_deeply($frontend->Shutdown({reason=>'test'}),{ok=>1,value=>'stopped'},'shutdown hook runs');
is_deeply($frontend->Shutdown({reason=>'again'}),{ok=>1,value=>'stopped'},'successful shutdown is idempotent');
is_deeply(\@lifecycle,
	['startup:test','activate:user','activate:application','open:file:///one,sftp://host/two','open:file:///three','shutdown:prepare','quit','shutdown:finish'],
	'shutdown callback owns the single Quit event and exact hook order');
is(scalar(grep $_ eq 'quit',@lifecycle),1,'shutdown callback emits Quit exactly once');
is($frontend->Shutdown({late=>1})->{error},"Invalid shutdown data: unknown key 'late'",'shutdown validates data before idempotence');
is_deeply($frontend->Startup({profile=>'late'}),{ok=>0,error=>"Lifecycle 'startup' called after Shutdown"},'startup is rejected after shutdown');
is_deeply($frontend->Activate({reason=>'late'}),{ok=>0,error=>"Lifecycle 'activate' called after Shutdown"},'activate is rejected after shutdown');
is_deeply($frontend->Open({uris=>['file:///late']}),{ok=>0,error=>"Lifecycle 'open' called after Shutdown"},'open is rejected after shutdown');
$frontend->Unsubscribe($quit);

my ($startup_attempts,$shutdown_attempts);
my $retry=GMB::Frontend->new
(	lifecycle =>
	{	startup => sub { die "startup failed\n" if ++$startup_attempts==1; return 'ready'; },
		shutdown => sub { die "shutdown failed\n" if ++$shutdown_attempts==1; return 'done'; },
	},
);
like($retry->Startup({})->{error},qr/^Lifecycle 'startup' failed: startup failed$/,'failed startup does not advance phase');
is_deeply($retry->Startup({}),{ok=>1,value=>'ready'},'failed startup may be retried');
is_deeply($retry->Startup({}),{ok=>1,value=>'ready'},'retried successful startup becomes idempotent');
$retry->Activate({});
like($retry->Shutdown({})->{error},qr/^Lifecycle 'shutdown' failed: shutdown failed$/,'failed shutdown does not advance phase');
is_deeply($retry->Shutdown({}),{ok=>1,value=>'done'},'failed shutdown may be retried');
is_deeply($retry->Shutdown({}),{ok=>1,value=>'done'},'retried successful shutdown becomes idempotent');
is($startup_attempts,2,'successful startup hook is not run again');
is($shutdown_attempts,2,'successful shutdown hook is not run again');

my @gtk=grep m#^(?:Gtk3|Gtk4|Gdk|Wnck)(?:/|\.pm)#, keys %INC;
is_deeply(\@gtk,[],'frontend contract does not load GTK, GDK, or Wnck');

done_testing;
