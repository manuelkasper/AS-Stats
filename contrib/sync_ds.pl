#!/usr/bin/perl

# This script synchronizes data sources of RRD files
# with tags defined in knownlinks file.
# It checks DS existence and add missing, but doesn't delete any
# superfluous DS from RRD!

use strict;
use RRD::Simple;
use Getopt::Std;

my %klfdsnames;

use vars qw/ %opt /;
getopts('r:k:', \%opt);

my $usage = "$0 [-rk]\n".
	"\t-r <path to RRD files>\n".
	"\t-k <path to known links file>\n";

my $rrdpath = $opt{'r'};
my $knownlinksfile = $opt{'k'};

die("$usage") if (!defined($rrdpath) || !defined($knownlinksfile));

die("$rrdpath does not exist or is not a directory\n") if ! -d $rrdpath;
die("$knownlinksfile does not exist or is not a file\n") if ! -f $knownlinksfile;

my @rrd_files = <$rrdpath/*/*.rrd>;

read_knownlinks();
my $rrd = RRD::Simple->new();
my $changed;

for my $file (@rrd_files) {
    $changed = 0;
    print "Processing $file...";
    my @rrdsources = $rrd->sources($file);
    foreach my$ds (keys %klfdsnames) {
	if (!grep(/$ds/,@rrdsources)) {
	    print "\n adding missing ds \'$ds\'";
	    $rrd->add_source($file, $ds => 'ABSOLUTE');
	    $changed = 1;
	}
    }
    print ($changed ? "\ndone.\n":" ok.\n");
}

sub read_knownlinks {
    open(KLFILE, $knownlinksfile) or die("Cannot open $knownlinksfile!");
    while (<KLFILE>) {
	chomp;
	next if (/(^\s*#)|(^\s*$)/);	# empty line or comment
	my ($routerip,$ifindex,$tag,$descr,$color) = split(/\t+/);
	$klfdsnames{$tag."_in"}++;
	$klfdsnames{$tag."_out"}++;
	$klfdsnames{$tag."_v6_in"}++;
	$klfdsnames{$tag."_v6_out"}++;
    }
    close(KLFILE);
    return;
}
