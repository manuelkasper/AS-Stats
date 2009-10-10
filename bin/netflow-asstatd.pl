#!/usr/bin/perl -w
#
# $Id$
#
# written by Manuel Kasper, Monzoon Networks AG <mkasper@monzoon.net>
# cli params/rrd storage/sampling mods Steve Colam <steve@colam.co.uk>

use strict;
use IO::Socket;
use RRDs;
use Getopt::Std;

my %knownlinks;

my $samplingrate = 1;	# rate for sampled NetFlow (or = 1 for unsampled)

my $ascache = {};
my $ascache_lastflush = 0;
my $ascache_flush_interval = 60;

my $server_port = 9000;
my $MAXREAD = 8192;
my $header_len = 28;
my $flowrec_len = 28;
my $childrunning = 0;

use vars qw/ %opt /;
getopts('r:p:k:s:', \%opt);

my $usage = "$0 [-rpks]\n".
	"\t-r <path to RRD files>\n".
	"\t(-p <UDP listen port - default $server_port>)\n".
	"\t-k <path to known links file>\n".
	"\t(-s <sampling rate - default $samplingrate>)\n";

my $rrdpath = $opt{'r'};
my $knownlinksfile = $opt{'k'};

die("$usage") if (!defined($rrdpath) || !defined($knownlinksfile));

die("$rrdpath does not exist or is not a directory\n") if ! -d $rrdpath;
die("$knownlinksfile does not exist or is not a file\n") if ! -f $knownlinksfile;

if (defined($opt{'s'})) {
	$samplingrate = $opt{'s'};
	die("Sampling rate is non numeric\n") if $samplingrate !~ /^[0-9]+$/;
}

if (defined($opt{'p'})) {
	$server_port = $opt{'p'};
	die("Server port is non numeric\n") if $server_port !~ /^[0-9]+$/;
}

# reap dead children
$SIG{CHLD} = \&REAPER;
$SIG{TERM} = \&TERM;
$SIG{INT} = \&TERM;
$SIG{HUP} = \&read_knownlinks;

sub REAPER {
	wait;
	$childrunning = 0;
	$SIG{CHLD} = \&REAPER;
}

sub TERM {
	print "SIGTERM received\n";
	exit 0;
}

# read known links file
read_knownlinks();

# prepare to listen for NetFlow UDP packets
my $server = IO::Socket::INET->new(LocalPort => $server_port, Proto => "udp")
	  or die "Couldn't be a udp server on port $server_port : $@\n";

my ($him,$datagram,$flags);

# main NetFlow datagram receive loop
while (1) {
	$him = $server->recv($datagram, $MAXREAD);
	next if (!$him);
	
	my ($port, $ipaddr) = sockaddr_in($server->peername);

	my ($version, $count, $sysuptime, $unix_secs, $unix_nsecs,
	  $flow_sequence, $engine_type, $engine_id, $aggregation,
	  $agg_version) = unpack("nnNNNNCCCC", $datagram);

	if ($version != 8 || $aggregation != 1 || $agg_version != 2) {
		print "unknown version: $version/$aggregation/$agg_version\n";
		next;
	}

	my $flowrecs = substr($datagram, $header_len);
	
	for (my $i = 0; $i < $count; $i++) {
		my $flowrec = substr($datagram, $header_len + ($i*$flowrec_len), $flowrec_len);
		my @flowdata = unpack("NNNNNnnnn", $flowrec);
		handleflow($ipaddr, @flowdata);
	}
}

sub handleflow {
	my ($routerip, $nflows, $npackets, $noctets, $firstts, $lastts,
			$srcas, $dstas, $snmpin, $snmpout) = @_;
	
	if ($srcas == 0 && $dstas == 0) {
		# don't care about internal traffic
		return;
	}
	
	#print "$srcas => $dstas ($noctets octets)\n";
	
	# determine direction and interface alias name (if known)
	my $direction;
	my $ifalias;
	my $as;
	
	if ($srcas == 0) {
		$as = $dstas;
		$direction = "out";
		$ifalias = $knownlinks{inet_ntoa($routerip) . '_' . $snmpout};
	} elsif ($dstas == 0) {
		$as = $srcas;
		$direction = "in";
		$ifalias = $knownlinks{inet_ntoa($routerip) . '_' . $snmpin};
	} else {
		handleflow($routerip, $nflows, $npackets, $noctets, $firstts, $lastts,
			$srcas, 0, $snmpin, $snmpout);
		handleflow($routerip, $nflows, $npackets, $noctets, $firstts, $lastts,
			0, $dstas, $snmpin, $snmpout);
		return;
	}
	
	if (!$ifalias) {
		# ignore this, as it's through an interface we don't monitor
		return;
	}
	
	my $dsname = "${ifalias}_${direction}";
	
	# put it into the cache
	if (!$ascache->{$as}) {
		$ascache->{$as} = {createts => time};
	}
	
	$ascache->{$as}->{$dsname} += $noctets;
	$ascache->{$as}->{updatets} = time;
	
	if ($ascache->{$as}->{updatets} == $ascache_lastflush) {
		# cheat a bit here
		$ascache->{$as}->{updatets}++;
	}
	
	# now flush the cache, if necessary
	flush_cache();
}

sub flush_cache {

	if ($childrunning || ((time - $ascache_lastflush) < $ascache_flush_interval)) {
		# can't/don't want to flush cache right now
		return;
	}

	$childrunning = 1;
	my $pid = fork();

	if (!defined $pid) {
		$childrunning = 0;
		print "cannot fork\n";
	} elsif ($pid != 0) {
		# in parent
		$ascache_lastflush = time;
		$ascache = {};
		return;
	}

	while (my ($as, $cacheent) = each(%$ascache)) {
		#print "$$: flushing data for AS $as ($cacheent->{updatets})\n";
		
		my $rrdfile = getrrdfile($as, $cacheent->{updatets});
		my @templatearg;
		my @args;
		
		while (my ($dsname, $value) = each(%$cacheent)) {
			next if ($dsname !~ /_(in|out)$/);
			
			push(@templatearg, $dsname);
			push(@args, $value * $samplingrate);
		}
		
	 	RRDs::update($rrdfile, "--template", join(':', @templatearg),
	 		$cacheent->{updatets} . ":" . join(':', @args));
	 	my $ERR = RRDs::error;
		if ($ERR) {
			print "Error updating RRD file $rrdfile: $ERR\n";
		}
	}
	
	exit 0;
}

# create an RRD file for the given AS, if it doesn't exist already, 
# and return its file name
sub getrrdfile {
	my $as = shift;
	my $startts = shift;
	$startts--;
	
	# we create 256 directories and store RRD files based on the lower
	# 8 bytes of the AS number
	my $dirname = "$rrdpath/" . sprintf("%02x", $as % 256);
	if (! -d $dirname) {
		# need to create directory
		mkdir($dirname);
	}
	
	my $rrdfile = "$dirname/$as.rrd";

	# let's see if there's already an RRD file for this AS - if not, create one
	if (! -r $rrdfile) {
		#print "$$: creating RRD file for AS $as\n";
		
		my @args;
		while (my ($key, $alias) = each(%knownlinks)) {
			push(@args, "DS:${alias}_in:ABSOLUTE:300:U:U");
			push(@args, "DS:${alias}_out:ABSOLUTE:300:U:U");
		}
		push(@args, "RRA:AVERAGE:0.99999:1:576");	# 48 hours at 5 minute resolution
		push(@args, "RRA:AVERAGE:0.99999:12:168");	# 1 week at 1 hour resolution
		push(@args, "RRA:AVERAGE:0.99999:288:366");	# 1 year at 1 day resolution
		RRDs::create($rrdfile, "--start", $startts, @args);
		
		my $ERR = RRDs::error;
		if ($ERR) {
			print "Error creating RRD file $rrdfile: $ERR\n";
			return;
		}
	}
	
	return $rrdfile;
}

sub read_knownlinks {
	my %knownlinks_tmp;
	open(KLFILE, $knownlinksfile) or die("Cannot open $knownlinksfile!");
	while (<KLFILE>) {
		chomp;
		next if (/(^\s*#)|(^\s*$)/);	# empty line or comment
		
		my ($routerip,$ifindex,$tag,$descr,$color) = split(/\t+/);
		$knownlinks_tmp{"${routerip}_${ifindex}"} = $tag;
	}
	close(KLFILE);
	
	%knownlinks = %knownlinks_tmp;
	return;
}
