#!/usr/bin/perl
#
# $Id$
#
# (c) 2008 Monzoon Networks AG. All rights reserved.

use RRDs;

if ($#ARGV != 0) {
	die("Usage: $0 outfile\n");
}

my %knownlinks = (
	# key format is "<router IP>_<SNMP ifindex>"
	# max. alias length is 16 characters; only [a-zA-Z0-9] allowed
	'80.254.79.250_44' => 'tix',
	'80.254.79.250_45' => 'sunrise',
	'80.254.79.250_47' => 'swissixzrh',
	'80.254.79.250_65' => 'dtag',
	'80.254.79.251_7' => 'colt',
	'80.254.79.251_8' => 'swissixglb'
);
my @links = values %knownlinks;

my $rrdpath = "/var/db/netflow/rrd";
my $statsfile = $ARGV[0];

# walk through all RRD files in the given path and extract stats for all links
# from them; write the stats to a text file, sorted by total traffic

opendir(DIR, $rrdpath);
my @rrdfiles = readdir(DIR);
closedir(DIR);

my $astraffic = {};

$|=1;
my $i = 0;
foreach my $rrdfile (@rrdfiles) {
	if ($rrdfile =~ /^(\d+).rrd$/) {
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

open(STATSFILE, ">$statsfile");

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

sub gettraffic {

	my $as = shift;
	my $start = shift;
	my $end = shift;
	
	my @cmd = ("dummy", "--start", $start, "--end", $end);
	
	my $retdata = {};
	
	foreach my $link (@links) {
		push(@cmd, "DEF:${link}_in=$rrdpath/$as.rrd:${link}_in:AVERAGE");
		push(@cmd, "DEF:${link}_out=$rrdpath/$as.rrd:${link}_out:AVERAGE");
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
