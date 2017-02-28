#!/usr/bin/perl
#
# $Id$
#
# written by Manuel Kasper <mk@neon1.net> for Monzoon Networks AG
# mod for rrd path sjc

use strict;
use RRDs;
use File::Find;
use File::Find::Rule;

if ($#ARGV < 2) {
	die("Usage: $0 <path to RRD file directory> <path to known links file> outfile [interval-hours]\n");
}

my $rrdpath = $ARGV[0];
my $knownlinksfile = $ARGV[1];
my $statsfile = $ARGV[2];
my $interval = 86400;

if ($ARGV[3]) {
    $interval = $ARGV[3] * 3600;
}

my %knownlinks;

read_knownlinks();

my @links = values %knownlinks;

# walk through all RRD files in the given path and extract stats for all links
# from them; write the stats to an sqlite database

my @rrdfiles = File::Find::Rule->maxdepth(2)->file->in($rrdpath);

my $astraffic = {};

$|=1;
my $i = 0;
foreach my $rrdfile (@rrdfiles) {
	if ($rrdfile =~ /\/(\d+).rrd$/) {
		my $as = $1;
		
		$astraffic->{$as} = gettraffic($as, time - $interval, time);
		$i++;
		if ($i % 100 == 0) {
			print "$i... ";
		}
	}
}
print "\n";

my $query = 'create table stats(asn int';
foreach my $link (@links) {
	$query .= ", ${link}_in int, ${link}_out int, ${link}_v6_in int, ${link}_v6_out int";
}
$query .= ');';

use DBI;
my $db = DBI->connect("dbi:SQLite:dbname=$statsfile.tmp", '', '');
$db->do('PRAGMA synchronous = OFF');
$db->do('drop table if exists stats');
$db->do($query);

# print data
foreach my $as (keys %{ $astraffic }) {

	$query = "insert into stats values('$as'";
	
	foreach my $link (@links) {
		$query .= ", '" . undefaszero($astraffic->{$as}->{"${link}_in"}) . "'";
		$query .= ", '" . undefaszero($astraffic->{$as}->{"${link}_out"}) . "'";
		$query .= ", '" . undefaszero($astraffic->{$as}->{"${link}_v6_in"}) . "'";
		$query .= ", '" . undefaszero($astraffic->{$as}->{"${link}_v6_out"}) . "'";
	}
	$query .= ');';
	$db->do($query);
}

$db->disconnect();
rename("$statsfile.tmp", $statsfile);

sub undefaszero {
	my $val = shift;
	if (!defined($val)) {
		return 0;
	} else {
		return $val;
	}
}

sub gettraffic {

	my $as = shift;
	my $start = shift;
	my $end = shift;
	
	my @cmd = ("dummy", "--start", $start, "--end", $end);
	
	my $retdata = {};
	
	my $dirname = "$rrdpath/" . sprintf("%02x", $as % 256);
	my $rrdfile = "$dirname/$as.rrd";
	
	# get list of available DS
	my $have_v6 = 0;
	
	my $availableds = {};
	my $rrdinfo = RRDs::info($rrdfile);
	foreach my $ri (keys %$rrdinfo) {
		if ($ri =~ /^ds\[(.+)\]\.type$/) {
			$availableds->{$1} = 1;
			if ($1 =~ /_v6_/) {
				$have_v6 = 1;
			}
		}
	}
	
	foreach my $link (@links) {
		next if (!$availableds->{"${link}_in"} || !$availableds->{"${link}_out"});
		
		push(@cmd, "DEF:${link}_in=$rrdfile:${link}_in:AVERAGE");
		push(@cmd, "DEF:${link}_out=$rrdfile:${link}_out:AVERAGE");
		push(@cmd, "VDEF:${link}_in_v=${link}_in,TOTAL");
		push(@cmd, "VDEF:${link}_out_v=${link}_out,TOTAL");
		
		if ($have_v6) {
			push(@cmd, "DEF:${link}_v6_in=$rrdfile:${link}_v6_in:AVERAGE");
			push(@cmd, "DEF:${link}_v6_out=$rrdfile:${link}_v6_out:AVERAGE");
			push(@cmd, "VDEF:${link}_v6_in_v=${link}_v6_in,TOTAL");
			push(@cmd, "VDEF:${link}_v6_out_v=${link}_v6_out,TOTAL");
		}
		
		push(@cmd, "PRINT:${link}_in_v:%lf");
		push(@cmd, "PRINT:${link}_out_v:%lf");
		
		if ($have_v6) {
			push(@cmd, "PRINT:${link}_v6_in_v:%lf");
			push(@cmd, "PRINT:${link}_v6_out_v:%lf");
		}
	}
	
	my @res = RRDs::graph(@cmd);
	my $ERR = RRDs::error;
	if ($ERR) {
		die "Error while getting data for $as: $ERR\n";
	}
	
	my $lines = $res[0];
	
	for (my $i = 0; $i < scalar(@links); $i++) {
		my @vals;
		my $numds = ($have_v6 ? 4 : 2);
		
		for (my $j = 0; $j < $numds; $j++) {
			$vals[$j] = $lines->[$i*$numds+$j];
			chomp($vals[$j]);
			if (isnan($vals[$j])) {
				$vals[$j] = 0;
			}
		}
		
		$retdata->{$links[$i] . '_in'} = $vals[0];
		$retdata->{$links[$i] . '_out'} = $vals[1];
		
		if ($have_v6) {
			$retdata->{$links[$i] . '_v6_in'} = $vals[2];
			$retdata->{$links[$i] . '_v6_out'} = $vals[3];
		}
	}
	
	return $retdata;
}

sub read_knownlinks {
	open(KLFILE, $knownlinksfile) or die("Cannot open $knownlinksfile!");
	while (<KLFILE>) {
		chomp;
		next if (/(^\s*#)|(^\s*$)/);	# empty line or comment
		
		my ($routerip,$ifindex,$tag,$descr,$color) = split(/\t+/);
		my $known = 0;
		foreach my $link (values %knownlinks) {
			if ($tag eq $link) { $known=1; last; }
		}
		if ($known == 0) {
			$knownlinks{"${routerip}_${ifindex}"} = $tag;
		}
	}
	close(KLFILE);
}

sub isnan { ! defined( $_[0] <=> 9**9**9 ) }
