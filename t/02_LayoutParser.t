#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use Test::More;
use FindBin;
use File::Spec;

my $root=File::Spec->catdir($FindBin::Bin,File::Spec->updir);
require File::Spec->catfile($root,'gmusicbrowser_layout_parser.pm');

my $fixture=File::Spec->catfile($FindBin::Bin,'layouts','parser.layout');
my $proof=File::Spec->catfile($FindBin::Bin,'layouts','proof.layout');
my $catalog=Layout::Parser::ParseFiles
(
	files=>[$fixture,$proof],
	translate=>sub {'translated '.$_[0]},
);

is($catalog->{version},1,'catalog version');
is_deeply($catalog->{order},['parser base','parser fixed','parser child','parser unnamed','gtk4 proof'],'layout declaration order');
is($catalog->{layouts}{'parser base'}{metadata}{Name},'translated Parser base','metadata translation');
is($catalog->{layouts}{'parser base'}{source}{line},1,'layout source line');

my $base=$catalog->{layouts}{'parser base'};
my $child=$catalog->{layouts}{'parser child'};
is($child->{based_on},'parser base','base layout recorded');
ok(exists $child->{definitions}{VBmain},'shallow inherited definition');
is($child->{definitions}{VBmain}{source}{line},4,'inherited definition keeps source');
ok(!exists $child->{definitions}{HBbuttons},'empty override removes inherited definition');
is($child->{empty_overrides}[0]{name},'HBbuttons','empty override preserved');
is_deeply([map $_->{name},@{$child->{declarations}}],[qw/Name HBbuttons VBextra/],'declaration order preserved');
ok(!exists $catalog->{layouts}{'parser unnamed'}{metadata}{Name},'layout name is not inherited');

my ($vbmain)=grep $_->{name} eq 'VBmain',@{$base->{nodes}};
is($vbmain->{raw},'(border=2) 5_Play2(click1=PlayPause) _HBbuttons','raw definition preserved');
is($vbmain->{raw_options},'border=2','raw container options preserved');
is($vbmain->{options}{values}{border},2,'container option parsed');
is($vbmain->{children}[0]{name},'Play2','stable widget name preserved');
is($vbmain->{children}[0]{element},'Play','numeric suffix removed from base element');
is($vbmain->{children}[0]{packing}{raw},'5_','raw packing preserved');
is($vbmain->{children}[0]{raw_options},'click1=PlayPause','raw widget options preserved');
is_deeply($base->{roots},['VBmain'],'root detected');

my $fixed=$catalog->{layouts}{'parser fixed'};
my ($fbmain)=grep $_->{name} eq 'FBmain',@{$fixed->{nodes}};
is(scalar @{$fbmain->{children}},1,'FB position prefix is not a separate child');
is($fbmain->{children}[0]{name},'HBinner','FB child named after its prefix');
is($fbmain->{children}[0]{kind},'container_ref','FB child container reference identified');
is($fbmain->{children}[0]{packing}{raw},'.1,0,.8,0','FB fractional position and size kept as packing');
my ($fbplain)=grep $_->{name} eq 'FBplain',@{$fixed->{nodes}};
is_deeply([map $_->{name},@{$fbplain->{children}}],[qw/Play3 Quit3/],'adjacent FB children split on their prefixes');
is($fbplain->{children}[0]{packing}{raw},'5,4','FB integer position kept as packing');
is($fbplain->{children}[1]{packing}{raw},'-5,.4,5,.2','FB negative and fractional position kept as packing');
is($fbplain->{children}[1]{element},'Quit','FB child keeps its base element');

is($base->{unknown}[0]{name},'Mystery','unknown property preserved');
my ($unknown)=grep $_->{code} eq 'unknown_property',@{$catalog->{diagnostics}};
is($unknown->{source}{line},6,'unknown property diagnostic has source line');
my ($invalid)=grep $_->{code} eq 'invalid_header',@{$catalog->{diagnostics}};
is($invalid->{source}{line},29,'invalid header diagnostic has source line');

my $skin=$catalog->{skins}{'Column parser column'};
is($skin->{definitions}{width},120,'skin definition parsed');
is_deeply($skin->{elements},['value=Text(markup="%t")'],'skin element preserved');
is($skin->{options}{size}{type},'','skin option type preserved');
is($skin->{options}{size}{values}{max},9,'skin options parsed');

my $proof_layout=$catalog->{layouts}{'gtk4 proof'};
ok($proof_layout,'proof layout parsed');
is_deeply($proof_layout->{roots},['VBmain'],'proof root detected');
my ($proof_root)=grep $_->{name} eq 'VBmain',@{$proof_layout->{nodes}};
is($proof_root->{children}[1]{kind},'container_ref','child container reference identified');
my ($buttons)=grep $_->{name} eq 'HBbuttons',@{$proof_layout->{nodes}};
is_deeply([map $_->{name},@{$buttons->{children}}],['Play','Quit'],'proof uses established widgets');

my @bundled=sort glob File::Spec->catfile($root,'layouts','*.layout');
my $bundled=Layout::Parser::ParseFiles(files=>\@bundled);
is(scalar @bundled,13,'all bundled layout files selected');
is(scalar @{$bundled->{order}},76,'all bundled layout declarations parsed');
is(scalar keys %{$bundled->{skins}},19,'all bundled skin declarations parsed');
is(scalar(grep $_->{severity} eq 'error',@{$bundled->{diagnostics}}),0,'bundled layouts have no parse errors');
ok(!grep(!$_->{source} || !defined $_->{source}{line},@{$bundled->{diagnostics}}),'bundled diagnostics are source-located');
ok($bundled->{layouts}{minimal},'bundled minimal layout parsed');
ok($bundled->{layouts}{'Lists, Library & Context'},'bundled default layout parsed');
ok($bundled->{skins}{'Group pic'},'bundled SongTree skin parsed');

my ($contrib)=grep $_->{name} eq 'VBcenterdown',@{$bundled->{layouts}{'Conz Aishi (with Filter Panes)'}{nodes}};
is($contrib->{children}[0]{name},'SongTree','legacy malformed quoted option remains one widget');
like($contrib->{children}[0]{raw_options},qr/ cols="Spacer /,'legacy malformed quoted option raw data preserved');
my ($exaile)=grep $_->{name} eq 'VBSongInfo',@{$bundled->{layouts}{Exaile}{nodes}};
is_deeply([map $_->{name},@{$exaile->{children}}],[qw/Title Artist Album Filler2/],'adjacent widget split after options');
is($exaile->{children}[2]{raw_options},'yalign=1,ellipsize=end,markup="from %l"','adjacent widget options preserved');
is($exaile->{children}[3]{packing}{raw},100,'adjacent widget packing preserved');

my ($fslower)=grep $_->{name} eq 'FBLower',@{$bundled->{layouts}{'default fullscreen'}{nodes}};
is(scalar @{$fslower->{children}},1,'bundled FB declares one child, not a phantom widget');
is($fslower->{children}[0]{name},'HBLower','bundled FB child is the named container');
is($fslower->{children}[0]{packing}{raw},'.1,0,.8,0','bundled FB packing preserved');

ok(!grep(/^Gtk(?:3|4)(?:::|\.pm)/,keys %INC),'parser imports no GTK binding');
ok(!grep(/^(?:Gdk|Wnck)(?:::|\.pm)/,keys %INC),'parser imports no GDK or Wnck binding');

done_testing;
