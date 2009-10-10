#!/usr/bin/perl

# This script moves RRD files from the old (pre-v1.3) flat directory structure
# into subdirectories (where the name of each subdirectory is the lower
# byte of the AS number in hex).

use strict;

my $rrdpath = $ARGV[0];
die("Usage: $0 <path to RRD files>\n") if (! -d $rrdpath);

opendir(DIR, $rrdpath);
my @rrdfiles = readdir(DIR);
closedir(DIR);

my $i = 0;
foreach my $rrdfile (@rrdfiles) {
	if ($rrdfile =~ /^(\d+).rrd$/) {
		my $as = $1;
		
		# calculate new path
		my $dirname = "$rrdpath/" . sprintf("%02x", $as % 256);
		if (! -d $dirname) {
			# need to create directory
			mkdir($dirname);
		}

		my $new_rrdfile = "$dirname/$as.rrd";
		
		rename("$rrdpath/$rrdfile", $new_rrdfile);
		
		$i++;
		
		if ($i % 100 == 0) {
			print "$i...";
		}
	}
}
print "\n\n";
print "$i files moved.\n";
