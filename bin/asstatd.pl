#!/usr/bin/perl -w
#
# $Id$
#
# written by Manuel Kasper <mk@neon1.net> for Monzoon Networks AG
# cli params/rrd storage/sampling mods Steve Colam <steve@colam.co.uk>

use strict;
use 5.010;
use IO::Select;
use IO::Socket;
use RRDs;
use Getopt::Std;
use Scalar::Util qw(looks_like_number);
use ip2as;

my %knownlinks;
my %link_samplingrates;

my $ascache = {};
my $ascache_lastflush = 0;
my $ascache_flush_interval = 25;
my $ascache_flush_number = 0;

my $MAXREAD = 8192;
my $childrunning = 0;

# NetFlow
my $server_port = 9000;
my $v5_header_len = 24;
my $v5_flowrec_len = 48;
my $v8_header_len = 28;
my $v8_flowrec_len = 28;
my $v9_header_len = 20;
my $v9_templates = {};
my $v10_header_len = 16;
my $v10_templates = {};

# sFlow
my $sflow_server_port = 6343;

use vars qw/ %opt /;
getopts('r:p:P:k:a:nm:', \%opt);

my $usage = "$0 [-rpPka]\n".
	"\t-r <path to RRD files>\n".
	"\t(-p <NetFlow UDP listen port - default $server_port, use 0 to disable NetFlow)\n".
	"\t(-P <sFlow UDP listen port - default $sflow_server_port, use 0 to disable sFlow)\n".
	"\t-k <path to known links file>\n".
	"\t-a <your own AS number> - only required for sFlow\n".
	"\t-n enable peer-as statistics\n".
	"\t-m IP<->ASN mapping\n";

my $rrdpath = $opt{'r'};
my $knownlinksfile = $opt{'k'};
my $myas_opt = $opt{'a'};
my $peerasstats = $opt{'n'};
my $mapping = $opt{'m'};

die("$usage") if (!defined($rrdpath) || !defined($knownlinksfile));

die("$rrdpath does not exist or is not a directory\n") if ! -d $rrdpath;
die("$knownlinksfile does not exist or is not a file\n") if ! -f $knownlinksfile;

if (defined($opt{'p'})) {
	$server_port = $opt{'p'};
	die("NetFlow server port is non numeric\n") if $server_port !~ /^[0-9]+$/;
}

if (defined($opt{'P'})) {
	$sflow_server_port = $opt{'P'};
	die("sFlow server port is non numeric\n") if $sflow_server_port !~ /^[0-9]+$/;
}

if ($sflow_server_port == $server_port) {
	die("sFlow server port can't be the same as NetFlow server port\n");
}

my %myas;
if($sflow_server_port > 0){
	die('No ASN found, please specify -a') if !defined($myas_opt);
	%myas = map {$_ => 1 } split(',', $myas_opt);
	for my $i (%myas){
		next if !defined($i);
		die("Your AS number is non numeric ($i)\n") if ($i !~ /^[0-9]+$/);
	}
}

if (!$sflow_server_port && $peerasstats) {
    die("peer-as statistics only work with sFlow\n");
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
	flush_cache(1);
	while (wait() != -1) {}
	exit 0;
}

# read known links file
read_knownlinks();

my ($lsn_nflow, $lsn_sflow);
my $sel = IO::Select->new();

# prepare to listen for NetFlow UDP packets
if ($server_port > 0) {
	$lsn_nflow = IO::Socket::INET->new(LocalPort => $server_port, Proto => "udp")
		or die "Couldn't be a NetFlow UDP server on port $server_port : $@\n";
	$sel->add($lsn_nflow);
}
# prepare to listen for sFlow UDP packets
if ($sflow_server_port > 0) {
	require Net::sFlow;
	$lsn_sflow = IO::Socket::INET->new(LocalPort => $sflow_server_port, Proto => "udp")
		or die "Couldn't be a sFlow UDP server on port $sflow_server_port : $@\n";
	$sel->add($lsn_sflow);
}

my ($him,$datagram,$flags);

if (defined($mapping)) {
	ip2as::init($mapping);
} else {
	#I don't use the mapping, to use an empty one
	ip2as::init('/dev/null');
}

# main datagram receive loop
while (1) {
	while (my @ready = $sel->can_read) {
		foreach my $server (@ready) {
			$him = $server->recv($datagram, $MAXREAD);
			next if (!$him);
			
			my ($port, $ipaddr) = sockaddr_in($server->peername);
			
			if (defined($lsn_nflow) && $server == $lsn_nflow) {
				my ($version) = unpack("n", $datagram);
				
				if ($version == 5) {
					parse_netflow_v5($datagram, $ipaddr);
				} elsif ($version == 8) {
					parse_netflow_v8($datagram, $ipaddr);
				} elsif ($version == 9) {
					parse_netflow_v9($datagram, $ipaddr);
				} elsif ($version == 10) {
					parse_netflow_v10($datagram, $ipaddr);
				} else {
					print "unknown NetFlow version: $version\n";
				}
			}
			elsif (defined($lsn_sflow) && $server == $lsn_sflow) {
				parse_sflow($datagram, $ipaddr);
			}
		}
	}
}

sub replace_asn {
	my $ip = shift;
	my $asn = shift;

	my $new_asn = ip2as::getas4ip($ip);
	if (defined($new_asn)) {
		return $new_asn;
	} else {
		return $asn;
	}
}

sub parse_netflow_v5 {
	my $datagram = shift;
	my $ipaddr = shift;
	
	my ($version, $count, $sysuptime, $unix_secs, $unix_nsecs,
	  $flow_sequence, $engine_type, $engine_id, $aggregation,
	  $agg_version) = unpack("nnNNNNCCCC", $datagram);

	my $flowrecs = substr($datagram, $v5_header_len);
	
	for (my $i = 0; $i < $count; $i++) {
		my $flowrec = substr($datagram, $v5_header_len + ($i*$v5_flowrec_len), $v5_flowrec_len);
		my @flowdata = unpack("NNNnnNNNNnnccccnnccN", $flowrec);
		my $srcip = join '.', unpack 'C4', pack 'N', $flowdata[0];
		my $dstip = join '.', unpack 'C4', pack 'N', $flowdata[1];

		my $srcas = replace_asn($srcip, $flowdata[15]);
		my $dstas = replace_asn($dstip, $flowdata[16]);

		#print "ipaddr: " . inet_ntoa($ipaddr) . " octets: $flowdata[6] srcas: $srcas dstas: $dstas in: $flowdata[3] out: $flowdata[4] 4 \n";
		handleflow($ipaddr, $flowdata[6], $srcas, $dstas, $flowdata[3], $flowdata[4], 4, 'netflow');
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
		#print "ipaddr: " . inet_ntoa($ipaddr) . " octets: $flowdata[2] srcas: $flowdata[5] dstas: $flowdata[6] in: $flowdata[7] out: $flowdata[8] 4 \n";
		handleflow($ipaddr, $flowdata[2], $flowdata[5], $flowdata[6], $flowdata[7], $flowdata[8], 4, 'netflow');
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
		my ($inoctets, $outoctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion, $vlanin, $vlanout);

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
					$inoctets = unpack("Q>", $cur_fldval);
				}
			} elsif ($cur_fldtype == 23) {	# OUT_BYTES
				if ($cur_fldlen == 4) {
					$outoctets = unpack("N", $cur_fldval);
				} elsif ($cur_fldlen == 8) {
					$outoctets = unpack("Q>", $cur_fldval);
				}
			} elsif ($cur_fldtype == 60) {	# IP_PROTOCOL_VERSION
				$ipversion = unpack("C", $cur_fldval);
			} elsif ($cur_fldtype == 27 || $cur_fldtype == 28) {	# IPV6_SRC_ADDR/IPV6_DST_ADDR
				$ipversion = 6;
			} elsif ($cur_fldtype == 58) {  # SRC_VLAN
				$vlanin = unpack("n", $cur_fldval);
			} elsif ($cur_fldtype == 59) {  # SRC_VLAN
				$vlanout = unpack("n", $cur_fldval);
			}
		}
	
		if (defined($srcas) && defined($dstas) && defined($snmpin) && defined($snmpout)) {
			handleflow($ipaddr, $inoctets + $outoctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion, 'netflow', $vlanin, $vlanout);
		}
	}
}

sub parse_netflow_v10 {
	my $datagram = shift;
	my $ipaddr = shift;
	
	# Parse packet
	my ($version, $length, $sysuptime, $seqno, $source_id, @flowsets) = unpack("nnNNN(nnX4/a)*", $datagram);
	
	# Loop through FlowSets and take appropriate action
	for (my $i = 0; $i < scalar @flowsets; $i += 2) {
		my $flowsetid = $flowsets[$i];
		my $flowsetdata = substr($flowsets[$i+1], 4);	# chop off id/length

		if ($flowsetid == 2) {
			# 0 = Template FlowSet
			parse_netflow_v10_template_flowset($flowsetdata, $ipaddr, $source_id);
		} elsif ($flowsetid == 3) {
			# 1 - Options Template FlowSet
		} elsif ($flowsetid > 255) {
			# > 255: Data FlowSet
			parse_netflow_v10_data_flowset($flowsetid, $flowsetdata, $ipaddr, $source_id);
		} else {
			# reserved FlowSet
			print "Unknown FlowSet ID $flowsetid found\n";
		}
	}
}

sub parse_netflow_v10_template_flowset {
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

		$v10_templates->{$ipaddr}->{$source_id}->{$template_id}->{'template'} = $template;

		# Calculate total length of template data
		my $totallen = 0;
		for (my $j = 1; $j < scalar @$template; $j += 2) {
			$totallen += $template->[$j];
		}

		$v10_templates->{$ipaddr}->{$source_id}->{$template_id}->{'len'} = $totallen;

		$i += (2 + $fldcount*2);
	}
}

sub parse_netflow_v10_data_flowset {
	my $flowsetid = shift;
	my $flowsetdata = shift;
	my $ipaddr = shift;
	my $source_id = shift;

	my $template = $v10_templates->{$ipaddr}->{$source_id}->{$flowsetid}->{'template'};
	if (!defined($template)) {
		#print "Template ID $flowsetid from $source_id/" . inet_ntoa($ipaddr) . " does not (yet) exist\n";
		return;
	}
	
	my $len = $v10_templates->{$ipaddr}->{$source_id}->{$flowsetid}->{'len'};
	
	my $ofs = 0;
	my $datalen = length($flowsetdata);
	while (($ofs + $len) <= $datalen) {
		# Interpret values according to template
		my ($inoctets, $outoctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion, $vlanin, $vlanout);

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
					$inoctets = unpack("Q>", $cur_fldval);
				}
			} elsif ($cur_fldtype == 23) {	# OUT_BYTES
				if ($cur_fldlen == 4) {
					$outoctets = unpack("N", $cur_fldval);
				} elsif ($cur_fldlen == 8) {
					$outoctets = unpack("Q>", $cur_fldval);
				}
			} elsif ($cur_fldtype == 60) {	# IP_PROTOCOL_VERSION
				$ipversion = unpack("C", $cur_fldval);
			} elsif ($cur_fldtype == 27 || $cur_fldtype == 28) {	# IPV6_SRC_ADDR/IPV6_DST_ADDR
				$ipversion = 6;
			} elsif ($cur_fldtype == 58) {  # SRC_VLAN
				$vlanin = unpack("n", $cur_fldval);
			} elsif ($cur_fldtype == 59) {  # SRC_VLAN
				$vlanout = unpack("n", $cur_fldval);
			}
		}
	
		if (defined($srcas) && defined($dstas) && defined($snmpin) && defined($snmpout)) {
			handleflow($ipaddr, $inoctets + $outoctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion, 'netflow', $vlanin, $vlanout);
		}
	}
}

sub parse_sflow {
	my $datagram = shift;
	my $ipaddr = shift;
	
	# decode the sFlow packet
	my ($sFlowDatagramRef, $sFlowSamplesRef, $errorsRef) = Net::sFlow::decode($datagram);
	
	if ($sFlowDatagramRef->{'sFlowVersion'} != 5) {
		print "Warning: non-v5 packet received - not supported\n";
		return;
	}
	
	# use agent IP if available (in case of proxy)
	if ($sFlowDatagramRef->{'AgentIp'}) {
		$ipaddr = inet_aton($sFlowDatagramRef->{'AgentIp'});
	}
	
	foreach my $sFlowSample (@{$sFlowSamplesRef}) {
		my $ipversion = 4;
		
		# only process standard structures
		next if ($sFlowSample->{'sampleTypeEnterprise'} != 0);
		
		my $snmpin;
		my $snmpout;
		if ($sFlowSample->{'sampleTypeFormat'} == 1) {
			$snmpin = $sFlowSample->{'inputInterface'};
			$snmpout = $sFlowSample->{'outputInterface'};
		} elsif ($sFlowSample->{'sampleTypeFormat'} == 3) {
			next if $sFlowSample->{'inputInterfaceFormat'} != 0;
			next if $sFlowSample->{'outputInterfaceFormat'} != 0;
			$snmpin = $sFlowSample->{inputInterfaceValue};
			$snmpout = $sFlowSample->{outputInterfaceValue};
		} else {
			next;
		}
		
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
				looks_like_number($sFlowSample->{'GatewayIpVersionNextHopRouter'}) &&
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
		
		# Extract src & dst IP from packet's header
		my $srcip = undef;
		my $dstip= undef;
		my (undef, $ethertype, $ipdata) = unpack('a12H4a*', $sFlowSample->{'HeaderBin'});
		if($ethertype eq '8100'){
			(undef, $ethertype, $ipdata) = unpack('nH4a*', $ipdata);
		}

		if($ethertype eq '0800'){
			(undef, undef, undef, $srcip, $dstip) = unpack('nnB64NN', $ipdata);
			$srcip = join '.', unpack 'C4', pack 'N', $srcip;
			$dstip = join '.', unpack 'C4', pack 'N', $dstip;
		}

		if($ethertype eq '86dd'){
			(undef, $sFlowSample->{HeaderDatalen}, undef, $srcip, $dstip) = unpack('NnnB128B128', $ipdata);
			my @array_src = ( $srcip =~ m/......../g );
			my @array_dst = ( $dstip =~ m/......../g );
			$srcip = '';
			$dstip = '';
			for(my $x = 0; $x < scalar @array_src; $x = $x + 2){
				$srcip .= sprintf("%02x%02x:", oct("0b$array_src[$x]"), oct("0b$array_src[$x + 1]"));
			}
			chop($srcip);

			for(my $x = 0; $x < scalar @array_dst; $x = $x + 2){
				$dstip .= sprintf("%02x%02x:", oct("0b$array_dst[$x]"), oct("0b$array_dst[$x + 1]"));
			}
			chop($dstip);
		}

		if (defined($srcip) && defined($dstip)){
			$srcas = replace_asn($srcip, $srcas);
			$dstas = replace_asn($dstip, $dstas);
		}

		# Outbound packets have our AS number as the source (GatewayAsSource),
		# while inbound packets have 0 as the destination (empty AsPath).
		# Transit packets have "foreign" AS numbers for both source and 
		# destination (handleflow() currently deals with those by counting
		# them twice; once for input and once for output)
		
		# substitute 0 for own AS number
		if ($myas{$srcas}) {
			$srcas = 0;
		}
		if ($myas{$dstas}) {
			$dstas = 0;
		}

		# Extract VLAN information
		my ($vlanin, $vlanout);
		if ($sFlowSample->{'SwitchSrcVlan'}) {
			$vlanin = $sFlowSample->{'SwitchSrcVlan'};
		}
		if ($sFlowSample->{'SwitchDestVlan'}) {
			$vlanout = $sFlowSample->{'SwitchDestVlan'};
		}

		handleflow($ipaddr, $noctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion, 'sflow', $vlanin, $vlanout);

		if ($peerasstats) {
    		# srcpeeras is the one who sent me data
    		# dstpeeras is the first one to which you'll send the data
    		# so, dstpeeras is the first entry in array
    		# if the array is now empty (poped before), then take $dstas
    		my $srcpeeras = ($sFlowSample->{'GatewayAsSourcePeer'}) ? $sFlowSample->{'GatewayAsSourcePeer'} : 0;
    		my $dstpeeras = 0;

    		if ($sFlowSample->{'GatewayDestAsPaths'}) {
    			$dstpeeras = @{$sFlowSample->{'GatewayDestAsPaths'}->[0]->{'AsPath'}}[0];
    			if (!$dstpeeras) {
    				$dstpeeras = 0;
    			}
    		}
    		if($dstpeeras == 0 && $dstas != 0){
    			$dstpeeras = $dstas;
    		}

		if ($myas{$srcpeeras}) {
    			$srcpeeras = 0;
    		}
		if ($myas{$dstpeeras}) {
    			$dstpeeras = 0;
    		}
		    
		    if ($srcpeeras != 0 || $dstpeeras != 0) {
			    handleflow($ipaddr, $noctets, $srcpeeras, $dstpeeras, $snmpin, $snmpout, $ipversion, 'sflow', $vlanin, $vlanout, 1);
			}
		}
	}
}

sub handleflow {
	my ($routerip, $noctets, $srcas, $dstas, $snmpin, $snmpout, $ipversion, $type, $vlanin, $vlanout, $peeras) = @_;
	
	if ($srcas == 0 && $dstas == 0) {
		# don't care about internal traffic
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
		$ifalias = $knownlinks{inet_ntoa($routerip) . '_' . $snmpout . '/' . $vlanout} if defined($vlanout);
		$ifalias //= $knownlinks{inet_ntoa($routerip) . '_' . $snmpout};
	} elsif ($dstas == 0) {
		$as = $srcas;
		$direction = "in";
		$ifalias = $knownlinks{inet_ntoa($routerip) . '_' . $snmpin . '/' . $vlanin} if defined($vlanin);
		$ifalias //= $knownlinks{inet_ntoa($routerip) . '_' . $snmpin};
	} else {
		handleflow($routerip, $noctets, $srcas, 0, $snmpin, $snmpout, $ipversion, $type, $vlanin, $vlanout, $peeras);
		handleflow($routerip, $noctets,	0, $dstas, $snmpin, $snmpout, $ipversion, $type, $vlanin, $vlanout, $peeras);
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
	my $name = ($peeras) ? "${as}_peer" : $as;
	if (!$ascache->{$name}) {
		$ascache->{$name} = {createts => time};
	}
	
	$ascache->{$name}->{$dsname} += $noctets;
	$ascache->{$name}->{updatets} = time;
	
	if ($ascache->{$name}->{updatets} == $ascache_lastflush) {
		# cheat a bit here
		$ascache->{$name}->{updatets}++;
	}
	
	# now flush the cache, if necessary
	flush_cache();
}

sub flush_cache {
	my $force = shift;
	if (!defined($force) && ($childrunning || ((time - $ascache_lastflush) < $ascache_flush_interval))) {
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
		if(!defined($force)){
			for (keys %$ascache) {
				my $as= $_;
				$as =~ s/_peer//;
				if ($as % 10 == $ascache_flush_number % 10) {
					delete $ascache->{$as};
					delete $ascache->{"${as}_peer"};
				}
			}
		}else{
			$ascache = ();
		}
		$ascache_flush_number++;
		return;
	}

	while (my ($entry, $cacheent) = each(%$ascache)) {
		my $as = $entry;
		$as =~ s/_peer//;

		if (defined($force) || $as % 10 == $ascache_flush_number % 10) {
			#print "$$: flushing data for AS $as ($cacheent->{updatets})\n";
		
			my $peeras = ($entry eq $as) ? 0 : 1;
			my $rrdfile = getrrdfile($as, $cacheent->{updatets}, $peeras);
			my @templatearg;
			my @args;
		
			while (my ($dsname, $value) = each(%$cacheent)) {
				next if ($dsname !~ /_(in|out)$/);
				
				my $tag = $dsname;
				$tag =~ s/(_v6)?_(in|out)$//;
				if ($dsname =~ /_(in|out)$/) {
					$tag = "${1}_${tag}";
				}
				my $cursamplingrate = $link_samplingrates{$tag};
				
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
	my $peeras = shift;
	$startts--;

	if(! -d "$rrdpath/peeras"){
		mkdir("$rrdpath/peeras");
	}

	my $prefix = ($peeras) ? "$rrdpath/peeras" : $rrdpath;
	# we create 256 directories and store RRD files based on the lower
	# 8 bytes of the AS number
	my $dirname = "$prefix/" . sprintf("%02x", $as % 256);
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
	open(KLFILE, $knownlinksfile) or die("Cannot open $knownlinksfile: $!");
	while (<KLFILE>) {
		chomp;
		next if (/(^\s*#)|(^\s*$)/);	# empty line or comment
		
		my ($routerip,$ifindex,$tag,$descr,$color,$linksamplingrate) = split(/\t+/);
		$knownlinks_tmp{"${routerip}_${ifindex}"} = $tag;

		my ($samplein,$sampleout) = split('/', $linksamplingrate);
		unless(defined($sampleout) && $sampleout =~ /^\d+$/) {
			$sampleout = $samplein;
		}

		unless(defined($samplein) && $samplein =~ /^\d+$/) {
			die("ERROR: No samplingrate for ".$routerip."\n");
		}
		
		$link_samplingrates_tmp{"in_$tag"} = $samplein;
		$link_samplingrates_tmp{"out_$tag"} = $sampleout;
		#print "DEBUG Sampling Rate for ${routerip}_${ifindex} is IN: $samplein | OUT: $sampleout\n";
	}
	close(KLFILE);
	
	%knownlinks = %knownlinks_tmp;
	%link_samplingrates = %link_samplingrates_tmp;
	return;
}

