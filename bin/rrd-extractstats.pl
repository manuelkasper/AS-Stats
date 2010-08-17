#!/usr/bin/perl
#
# $Id$
#
# written by Manuel Kasper, Monzoon Networks AG <mkasper@monzoon.net>
# mod for rrd path sjc

use strict;
use RRDs;
use File::Find;

if ($#ARGV != 2) {
	die("Usage: $0 <path to RRD file directory> <path to known links file> outfile\n");
}

my $rrdpath = $ARGV[0];
my $knownlinksfile = $ARGV[1];
my $statsfile = $ARGV[2];

my %knownlinks;

read_knownlinks();

my @links = values %knownlinks;

# walk through all RRD files in the given path and extract stats for all links
# from them; write the stats to a text file, sorted by total traffic

my @rrdfiles;
find(sub {
	if (-f $_) {
		push(@rrdfiles, $File::Find::name);
	}
}, $rrdpath);

my $astraffic = {};

$|=1;
my $i = 0;
foreach my $rrdfile (@rrdfiles) {
	if ($rrdfile =~ /\/(\d+).rrd$/) {
		my $as = $1;
		
		$astraffic->{$as} = gettraffic($as, time - 86400, time);
		$i++;
		if ($i % 100 == 0) {
			print "$i... ";
		}
	}
}
print "\n";

# now sort the keys in order of descending total traffic
my @asorder = sort {
	my $total_a = 0;
	
	foreach my $t (values %{$astraffic->{$a}}) {
		$total_a += $t;
	}
	my $total_b = 0;
	foreach my $t (values %{$astraffic->{$b}}) {
		$total_b += $t;
	}
	return $total_b <=> $total_a;
} keys %$astraffic;

open(STATSFILE, ">$statsfile.tmp");

# print header line
print STATSFILE "as";
foreach my $link (@links) {
	print STATSFILE "\t${link}_in\t${link}_out";
}
print STATSFILE "\n";

# print data
foreach my $as (@asorder) {
	print STATSFILE "$as";
	
	foreach my $link (@links) {
		print STATSFILE "\t" . $astraffic->{$as}->{"${link}_in"};
		print STATSFILE "\t" . $astraffic->{$as}->{"${link}_out"};
	}
	
	print STATSFILE "\n";
}

close(STATSFILE);

rename("$statsfile.tmp", $statsfile);

sub gettraffic {

	my $as = shift;
	my $start = shift;
	my $end = shift;
	
	my @cmd = ("dummy", "--start", $start, "--end", $end);
	
	my $retdata = {};
	
	my $dirname = "$rrdpath/" . sprintf("%02x", $as % 256);
	my $rrdfile = "$dirname/$as.rrd";
	
	foreach my $link (@links) {
		push(@cmd, "DEF:${link}_in=$rrdfile:${link}_in:AVERAGE");
		push(@cmd, "DEF:${link}_out=$rrdfile:${link}_out:AVERAGE");
		push(@cmd, "VDEF:${link}_in_v=${link}_in,TOTAL");
		push(@cmd, "VDEF:${link}_out_v=${link}_out,TOTAL");
		push(@cmd, "PRINT:${link}_in_v:%lf");
		push(@cmd, "PRINT:${link}_out_v:%lf");
	}
	
	my @res = RRDs::graph(@cmd);
	my $ERR = RRDs::error;
	if ($ERR) {
		die "Error while getting data for $as: $ERR\n";
	}
	
	my $lines = $res[0];
	
	for (my $i = 0; $i < scalar(@links); $i++) {
		my $in = $lines->[$i*2];
		chomp($in);
		if ($in eq "nan") {
			$in = 0;
		}
		
		my $out = $lines->[$i*2+1];
		chomp($out);
		if ($out eq "nan") {
			$out = 0;
		}
		
		$retdata->{$links[$i] . '_in'} = $in;
		$retdata->{$links[$i] . '_out'} = $out;
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
			if ($tag =~ $link) { $known=1; last; }
		}
		if ($known == 0) {
			$knownlinks{"${routerip}_${ifindex}"} = $tag;
		}
	}
	close(KLFILE);
}

