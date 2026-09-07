# Copyright (C) 2026 gmusicbrowser contributors
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

use strict;
use warnings;
use utf8;

package Layout::Parser;

my %Container= map {$_=>1} qw/HB VB HP VP TB NB MB SM BM EB FB FR SB AB WB/;
my %KnownProperty= map {$_=>1} qw/
	Author Category Default DefaultFocus DefaultFont DefaultFontColor
	Icon KeyBindings Name Skin SkinFile SkinPath Title Type VolumeScroll Window
/;

sub ParseFiles
{	my %args=@_;
	my $files=$args{files};
	my $translate=$args{translate} || sub {$_[0]};
	my $catalog=
	{ version=>1, order=>[], layouts=>{}, skins=>{}, diagnostics=>[], };
	unless (ref $files eq 'ARRAY')
	{	_diag($catalog,'error','invalid_files',"'files' must be an array reference",undef,undef);
		return $catalog;
	}
	for my $file (@$files)
	{	_read_file($catalog,$file,$translate);
	}
	return $catalog;
}

sub _read_file
{	my ($catalog,$file,$translate)=@_;
	unless (defined $file && !ref $file)
	{	_diag($catalog,'error','invalid_file','Invalid layout filename',undef,undef);
		return;
	}
	open my $fh,'<:encoding(UTF-8)',$file or do
	{	_diag($catalog,'error','open_failed',"Can't open layout file '$file': $!",$file,1);
		return;
	};
	my @lines;
	my ($continued,$continued_line);
	my $line=0;
	while (defined(my $text=<$fh>))
	{	$line++;
		$text=~s/^\s+//;
		next if $text=~m/^#/;
		$text=~s/[\r\n]+$//;
		next if $text eq '';
		if ($text=~s/\\$//)
		{	$continued_line=$line unless defined $continued_line;
			$continued.=$text;
			next;
		}
		if (defined $continued_line)
		{	$text=$continued.$text;
			push @lines,[$text,$continued_line] if length $text;
			undef $continued;
			undef $continued_line;
		}
		elsif (length $text) { push @lines,[$text,$line]; }
	}
	close $fh;
	if (defined $continued_line)
	{	push @lines,[$continued,$continued_line] if length $continued;
		_diag($catalog,'warning','unfinished_continuation','Line continuation reaches end of file',$file,$continued_line);
	}

	my ($header,@block);
	for my $entry (@lines)
	{	if ($entry->[0]=~m/^[{[]/)
		{	_parse_block($catalog,$file,$header,\@block,$translate) if $header;
			$header=$entry;
			@block=();
		}
		elsif ($header) { push @block,$entry; }
		else
		{	_diag($catalog,'warning','outside_block','Ignoring text outside a layout or skin block',$file,$entry->[1]);
		}
	}
	_parse_block($catalog,$file,$header,\@block,$translate) if $header;
}

sub _parse_block
{	my ($catalog,$file,$header,$lines,$translate)=@_;
	my ($text,$line)=@$header;
	if ($text=~m/^\[([^]=]+)\](?:\s*based on (.+))?$/)
	{	_parse_layout($catalog,$file,$line,$1,$2,$lines,$translate);
	}
	elsif ($text=~m/^\{(Column|Group) (.*)\}$/)
	{	_parse_skin($catalog,$file,$line,$1,$2,$lines,$translate);
	}
	else
	{	_diag($catalog,'error','invalid_header',"Invalid block header '$text'",$file,$line);
	}
}

sub _parse_layout
{	my ($catalog,$file,$line,$id,$based_on,$lines,$translate)=@_;
	my $base= defined $based_on ? $catalog->{layouts}{$based_on} : undef;
	_diag($catalog,'error','unknown_base',"Layout '$id' is based on unknown layout '$based_on'",$file,$line)
		if defined $based_on && !$base;
	_diag($catalog,'warning','duplicate_layout',"Layout '$id' is declared more than once",$file,$line)
		if exists $catalog->{layouts}{$id};

	my $layout=
	{	id=>$id, based_on=>$based_on, source=>{file=>$file,line=>$line},
		metadata=>{}, metadata_source=>{}, definitions=>{}, raw_definitions=>{},
		definition_order=>[],declarations=>[], empty_overrides=>[], nodes=>[], roots=>[], unknown=>[],
	};
	if ($base)
	{	$layout->{metadata}={%{$base->{metadata}}};
		$layout->{metadata_source}={%{$base->{metadata_source}}};
		delete $layout->{metadata}{Name};
		delete $layout->{metadata_source}{Name};
		$layout->{definitions}={%{$base->{definitions}}};
		$layout->{raw_definitions}={%{$base->{raw_definitions}}};
		$layout->{definition_order}=[@{$base->{definition_order}}];
	}

	my $current;
	for my $entry (@$lines)
	{	my ($text,$decl_line)=@$entry;
		if ($text=~m/^(\w+)\s*=\s*(.*)$/)
		{	my ($name,$raw)=($1,$2);
			$current={name=>$name,raw=>$raw,empty=>($raw eq '' ? 1 : 0),source=>{file=>$file,line=>$decl_line}};
			push @{$layout->{declarations}},$current;
		}
		elsif ($current)
		{	$current->{raw}.=' '.$text;
			$current->{empty}=0 if length $text;
		}
		else
		{	_diag($catalog,'warning','invalid_declaration',"Invalid layout declaration '$text'",$file,$decl_line);
			push @{$layout->{unknown}},{raw=>$text,source=>{file=>$file,line=>$decl_line}};
		}
	}

	for my $decl (@{$layout->{declarations}})
	{	my ($name,$raw)=@$decl{qw/name raw/};
		if ($decl->{empty})
		{	delete $layout->{metadata}{$name};
			delete $layout->{metadata_source}{$name};
			delete $layout->{definitions}{$name};
			delete $layout->{raw_definitions}{$name};
			@{$layout->{definition_order}}=grep $_ ne $name,@{$layout->{definition_order}};
			push @{$layout->{empty_overrides}},{%$decl};
			next;
		}
		if (_is_definition($name))
		{	my $definition={raw=>$raw,source=>{%{$decl->{source}}}};
			push @{$layout->{definition_order}},$name unless exists $layout->{definitions}{$name};
			$layout->{definitions}{$name}=$definition;
			$layout->{raw_definitions}{$name}=$raw;
		}
		else
		{	my $value=_translated($raw,$translate);
			$value=$1 if $name=~m/^(?:Name|Category|Title)$/ && $value=~m/^"(.*)"$/s;
			$layout->{metadata}{$name}=$value;
			$layout->{metadata_source}{$name}={%{$decl->{source}}};
			unless ($KnownProperty{$name})
			{	push @{$layout->{unknown}},{name=>$name,raw=>$raw,source=>{%{$decl->{source}}}};
				_diag($catalog,'warning','unknown_property',"Unknown layout property '$name'",$file,$decl->{source}{line});
			}
		}
	}
	_build_nodes($layout,$translate,$catalog);
	push @{$catalog->{order}},$id unless exists $catalog->{layouts}{$id};
	$catalog->{layouts}{$id}=$layout;
}

sub _is_definition
{	my $name=shift;
	return 1 if $Container{substr $name,0,2};
	return 1 if $name=~m/^[HV]Size\d*$/;
	return 0;
}

sub _build_nodes
{	my ($layout,$translate,$catalog)=@_;
	my (%containers,%referenced);
	for my $decl (@{$layout->{declarations}})
	{	my $name=$decl->{name};
		next unless exists $layout->{definitions}{$name};
		next unless $Container{substr $name,0,2};
		$containers{$name}=1;
	}
	for my $name (keys %{$layout->{definitions}})
	{	$containers{$name}=1 if $Container{substr $name,0,2};
	}
	my @names=grep $containers{$_},@{$layout->{definition_order}};
	for my $name (@names)
	{	my $definition=$layout->{definitions}{$name};
		my $type=substr $name,0,2;
		my ($raw_options,$children_raw)=_container_parts($definition->{raw});
		if ($definition->{raw}=~m/^\(/ && !defined $raw_options)
		{	_diag($catalog,'warning','invalid_container_options',"Unclosed options for container '$name'",$definition->{source}{file},$definition->{source}{line});
		}
		my $node=
		{	kind=>'container',name=>$name,element=>$type,raw=>$definition->{raw},
			raw_options=>$raw_options,options=>_parse_options($raw_options,$translate),
			packing=>undef,children=>[],source=>{%{$definition->{source}}},
		};
		for my $token (_extract_children($children_raw,$type))
		{	my ($raw,$packing)=@$token;
			my $child=_child_node($raw,$packing,$translate,$node->{source});
			_diag($catalog,'warning','invalid_widget_options',"Unclosed options for widget '$child->{name}'",$node->{source}{file},$node->{source}{line}) if $child->{invalid_options};
			@{$child}{qw/kind target/}=('container_ref',$child->{name}) if $containers{$child->{name}};
			push @{$node->{children}},$child;
			$referenced{$child->{name}}=1;
		}
		push @{$layout->{nodes}},$node;
	}
	$layout->{roots}=[grep !$referenced{$_},@names];
}

sub _container_parts
{	my $raw=shift;
	return (undef,$raw) unless $raw=~m/^\(/;
	my $end=_matching_paren($raw,0);
	return (undef,$raw) unless defined $end;
	my $options=substr $raw,1,$end-1;
	my $children=substr $raw,$end+1;
	$children=~s/^\s+//;
	return ($options,$children);
}

sub _child_node
{	my ($raw,$packing,$translate,$source)=@_;
	my ($name,$raw_options)=($raw,undef);
	if ($raw=~m/^(.*?)\(/)
	{	my $start=length $1;
		my $end=_matching_paren($raw,$start);
		if (defined $end && $end==length($raw)-1)
		{	$name=substr $raw,0,$start;
			$raw_options=substr $raw,$start+1,$end-$start-1;
		}
	}
	my $element=$name;
	$element=~s/\d+$//;
	my $node=
	{	kind=>'widget',name=>$name,element=>$element,raw=>$raw,
		raw_options=>$raw_options,options=>_parse_options($raw_options,$translate),
		packing=>{raw=>$packing},source=>{%$source},
	};
	$node->{invalid_options}=1 if $raw=~m/\(/ && !defined $raw_options;
	return $node;
}

sub _matching_paren
{	my ($text,$start)=@_;
	my $depth=0;
	for (my $i=$start;$i<length $text;$i++)
	{	my $c=substr $text,$i,1;
		next if $i && substr($text,$i-1,1) eq '\\';
		if ($c eq '(') { $depth++; }
		elsif ($c eq ')' && --$depth==0) { return $i; }
	}
	return undef;
}

sub _extract_children
{	my ($text,$type)=@_;
	my @tokens;
	while ($text ne '')
	{	$text=~s/^\s+//;
		last unless length $text;
		my $packing='';
		if ($type eq 'HB' || $type eq 'VB') { $text=~s/^([-_.0-9]*)//; $packing=$1; }
		elsif ($type eq 'HP' || $type eq 'VP') { $text=~s/^([_+]*)//; $packing=$1; }
		elsif ($type eq 'TB')
		{	if ($text=~s/^((?:_?"[^"]*[^\\]")|[^ ]*)\s+//) { $packing=$1; }
			else { last; }
		}
		elsif ($type eq 'FB')	# "5,4 " or "-5,.4,5,.2 ", position and optional size
		{	$text=~s/^(-?\.?\d+,-?\.?\d+(?:,\.?\d+,\.?\d+)?),?\s+// and $packing=$1;
		}
		my ($name)=$text=~m/^([^\s(]*)/;
		my $length=length($name||'');
		if (substr($text,$length,1) eq '(')
		{	my $end=_matching_paren($text,$length);
			$length=defined $end ? $end+1 : length $text;
		}
		elsif (!$length)
		{	($name)=$text=~m/^(\S+)/;
			$length=length($name||'');
		}
		last unless $length;
		my $raw=substr $text,0,$length,'';
		push @tokens,[$raw,$packing];
	}
	return @tokens;
}

sub _parse_options
{	my ($raw,$translate)=@_;
	return {raw=>undef,order=>[],values=>{}} unless defined $raw;
	my (@parts,$part,$quote,$depth,$escape);
	for my $c (split //,$raw)
	{	if ($escape) { $part.=$c; $escape=0; next; }
		if ($c eq '\\') { $part.=$c; $escape=1; next; }
		if ($quote)
		{	$part.=$c; $quote=undef if $c eq $quote; next;
		}
		if ($c eq '"' || $c eq "'") { $part.=$c; $quote=$c; next; }
		if ($c eq '(') { $depth++; $part.=$c; next; }
		if ($c eq ')') { $depth-- if $depth; $part.=$c; next; }
		if ($c eq ',' && !$depth) { push @parts,$part; $part=''; }
		else { $part.=$c; }
	}
	push @parts,$part if length $part;
	my (@order,%values,@unknown);
	for my $option (@parts)
	{	$option=~s/^\s+|\s+$//g;
		if ($option=~m/^([^=\s]+)\s*=\s*(.*)$/s)
		{	my ($name,$value)=($1,$2);
			$value=_translated($value,$translate);
			if ($value=~m/^(["'])(.*)\1$/s) { $value=$2; }
			push @order,$name;
			$values{$name}=$value;
		}
		elsif (length $option) { push @unknown,$option; }
	}
	return {raw=>$raw,order=>\@order,values=>\%values,unknown=>\@unknown};
}

sub _translated
{	my ($value,$translate)=@_;
	$value=~s#_"([^"]+)"#my $translated=$translate->($1); $translated=~y/"/'/; '"'.$translated.'"'#ge;
	return $value;
}

sub _parse_skin
{	my ($catalog,$file,$line,$kind,$id,$lines,$translate)=@_;
	my $skin=
	{	id=>$id,kind=>$kind,source=>{file=>$file,line=>$line},declarations=>[],
		definitions=>{},elements=>[],options=>{},unknown=>[],
	};
	for my $entry (@$lines)
	{	my ($text,$decl_line)=@$entry;
		unless ($text=~m/^(\w+)\s*([=:])\s*(.*)$/)
		{	push @{$skin->{unknown}},{raw=>$text,source=>{file=>$file,line=>$decl_line}};
			_diag($catalog,'warning','invalid_skin_declaration',"Invalid skin declaration '$text'",$file,$decl_line);
			next;
		}
		my ($name,$separator,$raw)=($1,$2,$3);
		my $decl={name=>$name,separator=>$separator,raw=>$raw,source=>{file=>$file,line=>$decl_line}};
		push @{$skin->{declarations}},$decl;
		if ($separator eq '=')
		{	$skin->{definitions}{$name}=_translated($raw,$translate);
		}
		elsif ($raw=~m/^Option(\w*)\((.*)\)$/s)
		{	$skin->{options}{$name}={type=>$1,%{_parse_options($2,$translate)}};
		}
		else { push @{$skin->{elements}},$name.'='.$raw; }
	}
	my $key=$kind.' '.$id;
	_diag($catalog,'warning','duplicate_skin',"Skin '$key' is declared more than once",$file,$line)
		if exists $catalog->{skins}{$key};
	$catalog->{skins}{$key}=$skin;
}

sub _diag
{	my ($catalog,$severity,$code,$message,$file,$line)=@_;
	my $diag={severity=>$severity,code=>$code,message=>$message};
	$diag->{source}={file=>$file,line=>$line} if defined $file;
	push @{$catalog->{diagnostics}},$diag;
}

1
