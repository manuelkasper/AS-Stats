#!/usr/bin/perl -w
#
# $Id$
#
# (c) 2008 Monzoon Networks AG. All rights reserved.

use strict;
use IO::Socket;
use RRDs;

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

my $ascache = {};
my $ascache_lastflush = 0;
my $ascache_flush_interval = 60;

my $rrdpath = "/var/db/netflow/rrd";

my $server_port = 9000;
my $MAXREAD = 8192;
my $header_len = 28;
my $flowrec_len = 28;
my $childrunning = 0;

# reap dead children
$SIG{CHLD} = \&REAPER;
$SIG{TERM} = \&TERM;
$SIG{INT} = \&TERM;

sub REAPER {
	wait;
	$childrunning = 0;
	$SIG{CHLD} = \&REAPER;
}

sub TERM {
	print "SIGTERM received\n";
	exit 0;
}

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

	my $pid = fork();

	if (!defined $pid) {
		print "cannot fork\n";
	} elsif ($pid != 0) {
		# in parent
		$childrunning = 1;
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
			push(@args, $value);
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

	# let's see if there's already an RRD file for this AS - if not, create one
	my $rrdfile = "$rrdpath/$as.rrd";
	if (! -r $rrdfile) {
		#print "$$: creating RRD file for AS $as\n";
		
		my @args;
		while (my ($key, $alias) = each(%knownlinks)) {
			push(@args, "DS:${alias}_in:ABSOLUTE:300:U:U");
			push(@args, "DS:${alias}_out:ABSOLUTE:300:U:U");
		}
		push(@args, "RRA:AVERAGE:0:1:576");		# 48 hours at 5 minute resolution
		push(@args, "RRA:AVERAGE:0:12:168");	# 1 week at 1 hour resolution
		push(@args, "RRA:AVERAGE:0:288:366");	# 1 year at 1 day resolution
		RRDs::create($rrdfile, "--start", $startts, @args);
		
		my $ERR = RRDs::error;
		if ($ERR) {
			print "Error creating RRD file $rrdfile: $ERR\n";
			return;
		}
	}
	
	return $rrdfile;
}
