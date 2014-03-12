<?php

/* changes these values to suit your local configuration */

$rrdpath = "/data/as-stats/rrd";
$daystatsfile = "/data/as-stats/asstats_day.txt";
$rrdtool = "/usr/bin/rrdtool";

$asinfofile = "asinfo.txt";
$knownlinksfile = "/data/as-stats/conf/knownlinks";
$outispositive = true;
$show95th = true;

$ntop = 20;
$showv6 = true;
$showtitledetail = true;
$hidelinkusagename  = true;	  # $showtitledetail will need to be true to allow this

$whois = "/usr/bin/whois";
$assetpath = "asset";
$asset_cache_life = "604800"; # 604800 seconds = 7 days

$compat_rrdtool12 = false;	# compatibility with RRDtool 1.2 (show95th will not work if this is set)

/* Custom links to be shown for each AS. You can use %as% as a
   placeholder for the ASN. */
$customlinks = array(
	'PeeringDB' => 'http://www.peeringdb.com/view.php?asn=%as%',
	'robtex' => 'http://www.robtex.com/as/as%as%.html',
	'HE' => 'http://bgp.he.net/AS%as%',
	'RIPEstat' => 'https://stat.ripe.net/AS%as%#tabId=at-a-glance',
	'euro-IX' => 'https://www.euro-ix.net/tools/asn_search?query=%as%'
);


/* END - no closing php tag needed here (prevents problems with stray whitespace) */
