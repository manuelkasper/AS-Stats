<?php

/* changes these values to suit your local configuration */

$rrdpath = "/data/rrd";
$daystatsfile = "/data/asstats_day.txt";
$rrdtool = "/usr/local/bin/rrdtool";

$asinfofile = "asinfo.txt";
$knownlinksfile = "/data/knownlinks";
$outispositive = true;
$show95th = true;

$ntop = 20;
$showv6 = true;

$whois = "/usr/bin/whois";
$assetpath = "asset";
$asset_cache_life ="604800"; # 604800 seconds = 7 days

/* Custom links to be shown for each AS. You can use %as% as a
   placeholder for the ASN. */
$customlinks = array(
	'PeeringDB' => 'http://www.peeringdb.com/view.php?asn=%as%',
	'robtex' => 'http://www.robtex.com/as/as%as%.html',
	'HE' => 'http://bgp.he.net/AS%as%',
	'RIPEstat' => 'https://stat.ripe.net/AS%as%#tabId=at-a-glance'
);


/* END - no closing php tag needed here (prevents problems with stray whitespace) */
