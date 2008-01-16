<?php
/*
 * $Id$
 * 
 * (c) 2008 Monzoon Networks AG. All rights reserved.
 */

$dbpath = "/var/db/netflow";
$rrdpath = "$dbpath/rrd";
$rrdtool = "/usr/local/bin/rrdtool";

$knownlinksfile = "/monzoon/conf/netflow-knownlinks";
$topasdayfile = "$dbpath/top50_day.txt";

$link = mysql_connect("localhost", "netflow", "ycCeDm71ck");
mysql_select_db("netflow", $link);

function getASInfo($asnum) {
	$row = mysql_fetch_array(mysql_query("select * from asnums where asn='" . addslashes($asnum) . "'"));
	
	if ($row) {
		return array(name => $row['asname'], descr => $row['descr'], country => $row['country']);
	} else {
		/* not found */
		return array(name => "AS$asnum", descr => "AS $asnum");
	}
}

function getknownlinks() {
	global $knownlinksfile;
	
	$fd = fopen($knownlinksfile, "r");
	$knownlinks = array();
	while (!feof($fd)) {
		$line = trim(fgets($fd));
		if (preg_match("/(^\\s*#)|(^\\s*$)/", $line))
			continue;	/* empty line or comment */
		
		list($routerip,$ifindex,$tag,$descr,$color) = preg_split("/\\t+/", $line);
		
		$knownlinks[] = array(
			routerip => $routerip,
			ifindex => $ifindex,
			tag => $tag,
			descr => $descr,
			color => $color
		);
	}
	fclose($fd);
	
	return $knownlinks;
}

function getasstats_top($ntop) {
	global $dbpath;
	
	/* first step: walk the data for all ASes to determine the top 5 for the given link */
	$fd = fopen("$dbpath/asstats_day.txt", "r");
	if (!$fd)
		return array();
	$cols = explode("\t", trim(fgets($fd)));
	
	/* read in up to $ntop AS stats, sum up columns */
	while (!feof($fd)) {
		$line = trim(fgets($fd));
		if (!$line)
			continue;
		
		$els = explode("\t", $line);
		
		/* first element is the AS */
		$as = $els[0];
		$tot_in = 0;
		$tot_out = 0;
		
		for ($i = 1; $i < count($els); $i++) {
			if (strpos($cols[$i], "in") !== false)
				$tot_in += $els[$i];
			else
				$tot_out += $els[$i];
		}
		
		$asstats[$as] = array($tot_in, $tot_out);
		
		if (count($asstats) >= $ntop)
			break;
	}
	fclose($fd);
	
	return $asstats;
}

function format_bytes($bytes) {
	if ($bytes >= 1073741824)
		return sprintf("%.2f GB", $bytes / 1073741824);
	else if ($bytes >= 1048576)
		return sprintf("%.2f MB", $bytes / 1048576);
	else if ($bytes >= 1024)
		return sprintf("%d KB", $bytes / 1024);
	else
		return "$bytes bytes";
}


?>
