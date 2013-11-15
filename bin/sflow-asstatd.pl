#!/usr/bin/perl -w
#
# $Id$
#
# written by Manuel Kasper <mk@neon1.net> for Monzoon Networks AG

use strict;
use Net::sFlow;
use IO::Socket;
use RRDs;
use Getopt::Std;

my %knownlinks;
my %link_samplingrates;

my $samplingrate = 512;

my $ascache = {};
my $ascache_lastflush = 0;
my $ascache_flush_interval = 25;
my $ascache_flush_number = 0;

my $server_port = 6343;
my $MAXREAD = 8192;
my $header_len = 28;
my $flowrec_len = 28;
my $childrunning = 0;

use vars qw/ %opt /;
getopts('r:p:k:a:s:', \%opt);

my $usage = "$0 [-rpkas]\n".
	"\t-r <path to RRD files>\n".
	"\t(-p <UDP listen port - default $server_port>)\n".
	"\t-k <path to known links file>\n".
	"\t-a <your own AS number>\n".
	"\t(-s <sampling rate - default $samplingrate>)\n";

my $rrdpath = $opt{'r'};
my $knownlinksfile = $opt{'k'};
my $myas = $opt{'a'};

die("$usage") if (!defined($rrdpath) || !defined($knownlinksfile) || !defined($myas));

die("$rrdpath does not exist or is not a directory\n") if ! -d $rrdpath;
die("$knownlinksfile does not exist or is not a file\n") if ! -f $knownlinksfile;
die("Your own AS number is non numeric\n") if ($myas !~ /^[0-9]+$/);

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

# prepare to listen for sFlow UDP packets
my $server = IO::Socket::INET->new(LocalPort => $server_port, Proto => "udp")
	  or die "Couldn't be a udp server on port $server_port : $@\n";

my ($him,$datagram,$flags);

# main sFlow datagram receive loop
while (1) {
	$him = $server->recv($datagram, $MAXREAD);
	next if (!$him);
	
	my ($port, $ipaddr) = sockaddr_in($server->peername);
	
	# decode the sFlow packet
	my ($sFlowDatagramRef, $sFlowSamplesRef, $errorsRef) = Net::sFlow::decode($datagram);
	
	if ($sFlowDatagramRef->{'sFlowVersion'} != 5) {
		print "Warning: non-v5 packet received - not supported\n";
		next;
	}

	# use agent IP if available (in case of proxy)
	if ($sFlowDatagramRef->{'AgentIp'}) {
		$ipaddr = inet_aton($sFlowDatagramRef->{'AgentIp'});
	}
	
	foreach my $sFlowSample (@{$sFlowSamplesRef}) {
		my $ipversion = 4;
		
		# only process standard structures
		next if ($sFlowSample->{'sampleTypeEnterprise'} != 0);
		
		# only process normal flow samples
		next if ($sFlowSample->{'sampleTypeFormat'} != 1);
		
		my $snmpin = $sFlowSample->{'inputInterface'};
		my $snmpout = $sFlowSample->{'outputInterface'};
		
		if ($snmpin >= 1073741823 || $snmpout >= 1073741823) {
			# invalid interface index - could be dropped packet or internal
			# (routing protocol, management etc.)
			#print "Invalid interface index $snmpin/$snmpout\n";
			next;
		}
		
		my $noctets;
		if ($sFlowSample->{'IPv4Packetlength'}) {
			$noctets = $sFlowSample->{'IPv4Packetlength'};
		} elsif ($sFlowSample->{'IPv6Packetlength'}) {
			$noctets = $sFlowSample->{'IPv6Packetlength'};
			$ipversion = 6;
		} else {
			$noctets = $sFlowSample->{'HeaderFrameLength'} - 14;
			
			# make one more attempt at figuring out the IP version
			if ((defined($sFlowSample->{'GatewayIpVersionNextHopRouter'}) &&
				$sFlowSample->{'GatewayIpVersionNextHopRouter'} == 2) ||
				(defined($sFlowSample->{'HeaderType'}) && $sFlowSample->{'HeaderType'} eq '86dd')) {
				$ipversion = 6;
			}
		}
		
		my $srcas = 0;
		my $dstas = 0;
		
		if ($sFlowSample->{'GatewayAsSource'}) {
			$srcas = $sFlowSample->{'GatewayAsSource'};
		}
		if ($sFlowSample->{'GatewayDestAsPaths'}) {
			$dstas = pop(@{$sFlowSample->{'GatewayDestAsPaths'}->[0]->{'AsPath'}});
			if (!$dstas) {
				$dstas = 0;
			}
		}
		
		# Outbound packets have our AS number as the source (GatewayAsSource),
		# while inbound packets have 0 as the destination (empty AsPath).
		# Transit packets have "foreign" AS numbers for both source and 
		# destination (handleflow() currently deals with those by counting
		# them twice; once for input and once for output)

		# substitute 0 for own AS number
		if ($srcas == $myas) {
			$srcas = 0;
		}
		if ($dstas == $myas) {
			$dstas = 0;
		}
		
		handleflow($ipaddr, $noctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion);
	}
}

sub handleflow {
	my ($routerip, $noctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion) = @_;
	
	if ($srcas == 0 && $dstas == 0) {
		# don't care about internal traffic
		return;
	}
	
	#print "$srcas => $dstas ($noctets octets, version $ipversion, snmpin $snmpin, snmpout $snmpout)\n";
	
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
		handleflow($routerip, $noctets, $srcas, 0, $snmpin, $snmpout, $ipversion);
		handleflow($routerip, $noctets, 0, $dstas, $snmpin, $snmpout, $ipversion);
		return;
	}
	
	if (!$ifalias) {
		# ignore this, as it's through an interface we don't monitor
		return;
	}
	
	my $dsname;
	if ($ipversion == 6) {
	 	$dsname = "${ifalias}_v6_${direction}";
	} else {
	 	$dsname = "${ifalias}_${direction}";
	}
	
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
		for (keys %$ascache) {
			if ($_ % 10 == $ascache_flush_number % 10) {
				delete $ascache->{$_};
			}
		}
		$ascache_flush_number++;
		return;
	}

	while (my ($as, $cacheent) = each(%$ascache)) {
		if ($as % 10 == $ascache_flush_number % 10) {
			#print "$$: flushing data for AS $as ($cacheent->{updatets})\n";
		
			my $rrdfile = getrrdfile($as, $cacheent->{updatets});
			my @templatearg;
			my @args;
		
			while (my ($dsname, $value) = each(%$cacheent)) {
				next if ($dsname !~ /_(in|out)$/);
				
				my $tag = $dsname;
				$tag =~ s/(_v6)?_(in|out)$//;
				my $cursamplingrate = $samplingrate;
				
				if ($link_samplingrates{$tag}) {
					$cursamplingrate = $link_samplingrates{$tag};
				}
			
				push(@templatearg, $dsname);
				push(@args, $value * $cursamplingrate);
			}
		
		 	RRDs::update($rrdfile, "--template", join(':', @templatearg),
		 		$cacheent->{updatets} . ":" . join(':', @args));
		 	my $ERR = RRDs::error;
			if ($ERR) {
				print "Error updating RRD file $rrdfile: $ERR\n";
			}
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
		
		my %links = map { $_, 1 } values %knownlinks;
		
		my @args;
		foreach my $alias (keys %links) {
			push(@args, "DS:${alias}_in:ABSOLUTE:300:U:U");
			push(@args, "DS:${alias}_out:ABSOLUTE:300:U:U");
			push(@args, "DS:${alias}_v6_in:ABSOLUTE:300:U:U");
			push(@args, "DS:${alias}_v6_out:ABSOLUTE:300:U:U");
		}
		push(@args, "RRA:AVERAGE:0.99999:1:576");	# 48 hours at 5 minute resolution
		push(@args, "RRA:AVERAGE:0.99999:12:168");	# 1 week at 1 hour resolution
		push(@args, "RRA:AVERAGE:0.99999:48:180");	# 1 month at 4 hour resolution
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
	my %link_samplingrates_tmp;
	open(KLFILE, $knownlinksfile) or die("Cannot open $knownlinksfile!");
	while (<KLFILE>) {
		chomp;
		next if (/(^\s*#)|(^\s*$)/);	# empty line or comment
		
		my ($routerip,$ifindex,$tag,$descr,$color,$samplingrate) = split(/\t+/);
		$knownlinks_tmp{"${routerip}_${ifindex}"} = $tag;
		
		if ($samplingrate) {
			$link_samplingrates_tmp{$tag} = $samplingrate;
		}
	}
	close(KLFILE);
	
	%knownlinks = %knownlinks_tmp;
	%link_samplingrates = %link_samplingrates_tmp;
	return;
}
