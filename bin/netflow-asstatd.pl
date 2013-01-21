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
my $ascache_flush_interval = 25;
my $ascache_flush_number = 0;

my $server_port = 9000;
my $MAXREAD = 8192;
my $v8_header_len = 28;
my $v8_flowrec_len = 28;
my $v9_header_len = 20;
my $childrunning = 0;
my $v9_templates = {};

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

	my ($version) = unpack("n", $datagram);
	
	if ($version == 8) {
		parse_netflow_v8($datagram, $ipaddr);
	} elsif ($version == 9) {
		parse_netflow_v9($datagram, $ipaddr);
	} else {
		print "unknown NetFlow version: $version\n";
	}
}

sub parse_netflow_v8 {
	my $datagram = shift;
	my $ipaddr = shift;
	
	my ($version, $count, $sysuptime, $unix_secs, $unix_nsecs,
	  $flow_sequence, $engine_type, $engine_id, $aggregation,
	  $agg_version) = unpack("nnNNNNCCCC", $datagram);

	if ($aggregation != 1 || ($agg_version != 0 && $agg_version != 2)) {
		print "unknown version: $version/$aggregation/$agg_version\n";
		return;
	}

	my $flowrecs = substr($datagram, $v8_header_len);
	
	for (my $i = 0; $i < $count; $i++) {
		my $flowrec = substr($datagram, $v8_header_len + ($i*$v8_flowrec_len), $v8_flowrec_len);
		my @flowdata = unpack("NNNNNnnnn", $flowrec);
		handleflow($ipaddr, $flowdata[2], $flowdata[5], $flowdata[6], $flowdata[7], $flowdata[8], 4);
	}
}

sub parse_netflow_v9 {
	my $datagram = shift;
	my $ipaddr = shift;
	
	# Parse packet
	my ($version, $count, $sysuptime, $unix_secs, $seqno, $source_id, @flowsets) = unpack("nnNNNN(nnX4/a)*", $datagram);
	
	# Loop through FlowSets and take appropriate action
	for (my $i = 0; $i < scalar @flowsets; $i += 2) {
		my $flowsetid = $flowsets[$i];
		my $flowsetdata = substr($flowsets[$i+1], 4);	# chop off id/length
		if ($flowsetid == 0) {
			# 0 = Template FlowSet
			parse_netflow_v9_template_flowset($flowsetdata, $ipaddr, $source_id);
		} elsif ($flowsetid == 1) {
			# 1 - Options Template FlowSet
		} elsif ($flowsetid > 255) {
			# > 255: Data FlowSet
			parse_netflow_v9_data_flowset($flowsetid, $flowsetdata, $ipaddr, $source_id);
		} else {
			# reserved FlowSet
			print "Unknown FlowSet ID $flowsetid found\n";
		}
	}
}

sub parse_netflow_v9_template_flowset {
	my $templatedata = shift;
	my $ipaddr = shift;
	my $source_id = shift;
	
	# Note: there may be multiple templates in a Template FlowSet
	
	my @template_ints = unpack("n*", $templatedata);

	my $i = 0;
	while ($i < scalar @template_ints) {
		my $template_id = $template_ints[$i];
		my $fldcount = $template_ints[$i+1];

		last if (!defined($template_id) || !defined($fldcount));

		#print "Updated template ID $template_id (source ID $source_id, from " . inet_ntoa($ipaddr) . ")\n";
		my $template = [@template_ints[($i+2) .. ($i+2+$fldcount*2-1)]];
		$v9_templates->{$ipaddr}->{$source_id}->{$template_id}->{'template'} = $template;
		
		# Calculate total length of template data
		my $totallen = 0;
		for (my $j = 1; $j < scalar @$template; $j += 2) {
			$totallen += $template->[$j];
		}
		
		$v9_templates->{$ipaddr}->{$source_id}->{$template_id}->{'len'} = $totallen;
		
		$i += (2 + $fldcount*2);
	}
}

sub parse_netflow_v9_data_flowset {
	my $flowsetid = shift;
	my $flowsetdata = shift;
	my $ipaddr = shift;
	my $source_id = shift;
	
	my $template = $v9_templates->{$ipaddr}->{$source_id}->{$flowsetid}->{'template'};
	if (!defined($template)) {
		#print "Template ID $flowsetid from $source_id/" . inet_ntoa($ipaddr) . " does not (yet) exist\n";
		return;
	}
	
	my $len = $v9_templates->{$ipaddr}->{$source_id}->{$flowsetid}->{'len'};
	
	my $ofs = 0;
	my $datalen = length($flowsetdata);
	while (($ofs + $len) <= $datalen) {
		# Interpret values according to template
		my ($inoctets, $outoctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion);
	
		$inoctets = 0;
		$outoctets = 0;
		$ipversion = 4;
		
		for (my $i = 0; $i < scalar @$template; $i += 2) {
			my $cur_fldtype = $template->[$i];
			my $cur_fldlen = $template->[$i+1];
		
			my $cur_fldval = substr($flowsetdata, $ofs, $cur_fldlen);
			$ofs += $cur_fldlen;
		
			if ($cur_fldtype == 16) {	# SRC_AS
				if ($cur_fldlen == 2) {
					$srcas = unpack("n", $cur_fldval);
				} elsif ($cur_fldlen == 4) {
					$srcas = unpack("N", $cur_fldval);
				}
			} elsif ($cur_fldtype == 17) {	# DST_AS
				if ($cur_fldlen == 2) {
					$dstas = unpack("n", $cur_fldval);
				} elsif ($cur_fldlen == 4) {
					$dstas = unpack("N", $cur_fldval);
				}
			} elsif ($cur_fldtype == 10) {	# INPUT_SNMP
				if ($cur_fldlen == 2) {
					$snmpin = unpack("n", $cur_fldval);
				} elsif ($cur_fldlen == 4) {
					$snmpin = unpack("N", $cur_fldval);
				}
			} elsif ($cur_fldtype == 14) {	# OUTPUT_SNMP
				if ($cur_fldlen == 2) {
					$snmpout = unpack("n", $cur_fldval);
				} elsif ($cur_fldlen == 4) {
					$snmpout = unpack("N", $cur_fldval);
				}
			} elsif ($cur_fldtype == 1) {	# IN_BYTES
				if ($cur_fldlen == 4) {
					$inoctets = unpack("N", $cur_fldval);
				} elsif ($cur_fldlen == 8) {
					$inoctets = unpack("Q", $cur_fldval);
				}
			} elsif ($cur_fldtype == 23) {	# OUT_BYTES
				if ($cur_fldlen == 4) {
					$outoctets = unpack("N", $cur_fldval);
				} elsif ($cur_fldlen == 8) {
					$outoctets = unpack("Q", $cur_fldval);
				}
			} elsif ($cur_fldtype == 60) {	# IP_PROTOCOL_VERSION
				$ipversion = unpack("C", $cur_fldval);
			} elsif ($cur_fldtype == 27 || $cur_fldtype == 28) {	# IPV6_SRC_ADDR/IPV6_DST_ADDR
				$ipversion = 6;
			}
		}
	
		if (defined($srcas) && defined($dstas) && defined($snmpin) && defined($snmpout)) {
			handleflow($ipaddr, $inoctets + $outoctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion);
		}
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
