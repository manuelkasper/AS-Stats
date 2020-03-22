#!/usr/bin/perl
#
# $Id$
#
# written by Manuel Kasper <mk@neon1.net> for Monzoon Networks AG
# mod for rrd path sjc

use strict;
use warnings;
use RRDs;
use File::Find;
use File::Find::Rule;
use DBI;
use TryCatch;
use File::Copy qw(copy);
use File::stat;

use threads       ;#qw( async );
use threads::shared;
use Thread::Queue qw( );

use Time::HiRes qw(time);

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

# If the DB has it, get latest check timestamp for every ASN we are aware of
my $db_version = 1;
my $as_list;
my $db;
try {
	if (-r $statsfile) { 
		copy($statsfile, "$statsfile.tmp");
	}
	$db = DBI->connect("dbi:SQLite:dbname=$statsfile.tmp", '', '');

	# Get last check timestamps
	my $sth = $db->prepare("SELECT asn, checked_at FROM stats") or die('field missing');
	$sth->execute();
	while(my($item, $data) = $sth->fetchrow_array()) {
		as_list->{$item} = $data;
	}

	$db_version = 2;
} catch ($e) {
	print("Previously generated database not found or checked_at field is missing, proceed with all RRD files. ($e)\n");
}

# walk through all RRD files in the given path and extract stats for all links
# from them; write the stats to an sqlite database

my @rrdfiles = File::Find::Rule->maxdepth(2)->file()->name('*.rrd')->in($rrdpath);

$|=1;

my $num_workers	= 1;
if (($ENV{'THREADS'} =~ /^\d+$/) and ($ENV{'THREADS'} > 0)) { 
    $num_workers = $ENV{'THREADS'};
}

my $num_work_units = scalar @rrdfiles;

print("Using " . $num_workers . " threads to process " . $num_work_units . " RRD files.\n");

my $q = Thread::Queue->new();
my $rq = Thread::Queue->new();

# Create work
foreach my $rrdfile (@rrdfiles) {
	if ($rrdfile =~ /\/(\d+).rrd$/) {
		my $task->{as} = $1;
		$task->{filename} = $rrdfile;
		$q->enqueue($task);
	}
}

my $i :shared = 0;
my $skipped :shared = 0;
my $t :shared = scalar time;
my $t0 :shared = scalar time;

# Create workers
my @workers;
for (1..$num_workers) {
	push @workers, async {
		while (defined(my $task = $q->dequeue())) {
			if ($as_list->{$task->{as}} and (!(stat($task->{filename})->mtime > $as_list->{$task->{as}}))) {
				$skipped += 1;
			} else {
				my $result->{as} = $task->{as};
				$result->{checked_at} = int time;
				$result->{result} = gettraffic($task->{as}, int time - $interval, int time);

				# Put result to result queue
				$rq->enqueue($result);
			}

			$i++;
			if ($i % 100 == 0) {
				my $average_speed = int(($i / (scalar time - $t0)) * 100) / 100;
				my $current_speed = int((100 / (scalar time - $t)) * 100) / 100;
				my $seconds_left = ($num_work_units - $i) / $average_speed;
				printf("%.2f%% (files per sec cur/avg %.2f/%.2f, proc/skip/total %d/%d/%d, %02d:%02d:%02d left)\n", int($i / $num_work_units * 100 * 100) / 100, $current_speed, $average_speed, ($i - $skipped), $skipped, $num_work_units, $seconds_left / 3600, $seconds_left / 60 % 60, $seconds_left % 60);
				$t = scalar time;
			}
		}
	};
}

# Tell workers they are no longer needed.
$q->enqueue(undef) for @workers;

# Wait for workers to end
$_->join() for @workers;

printf("100%% (processed %d RRD files, skipped %d because those files didn't change since last run)\n", $num_work_units - $skipped, $skipped);

$rq->end();


$db->do('PRAGMA synchronous = OFF');
my $query;
# Recreate the table if we didn't have the checked_at column above
if ($db_version < 2) {
	$db->do('DROP TABLE IF EXISTS stats;');
	
	$query = 'CREATE TABLE stats("asn" INT PRIMARY KEY, "checked_at" INT';
	foreach my $link (@links) {
		$query .= ", \"${link}_in\" INT, \"${link}_out\" INT, \"${link}_v6_in\" INT, \"${link}_v6_out\" INT";
	}
	$query .= ');';
	$db->do($query);
}

# read resultqueue and print data
while (my $result = $rq->dequeue) {
	$query = "INSERT OR REPLACE INTO stats VALUES ($result->{as}, $result->{checked_at}";

	foreach my $link (@links) {
		$query .= ", '" . undefaszero($result->{result}->{"${link}_in"}) . "'";
		$query .= ", '" . undefaszero($result->{result}->{"${link}_out"}) . "'";
		$query .= ", '" . undefaszero($result->{result}->{"${link}_v6_in"}) . "'";
		$query .= ", '" . undefaszero($result->{result}->{"${link}_v6_out"}) . "'";
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
