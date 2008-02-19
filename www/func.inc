<?php
/*
 * $Id$
 * 
 * written by Manuel Kasper, Monzoon Networks AG <mkasper@monzoon.net>
 */

$rrdpath = "/var/db/netflow/rrd";
$daystatsfile = "/var/db/netflow/asstats_day.txt";
$rrdtool = "/usr/local/bin/rrdtool";

$asinfofile = "asinfo.txt";
$knownlinksfile = "/etc/netflow-knownlinks";

/* note: you might want to put the data from asinfo.txt into an SQL
   database to avoid having to read the whole file all the time */
function getASInfo($asnum) {
	global $asinfodb;
	
	if (!isset($asinfodb))
		$asinfodb = readasinfodb();
	
	if ($asinfodb[$asnum])
		return $asinfodb[$asnum];
	else
		return array(name => "AS$asnum", descr => "AS $asnum");
	
	/*$row = mysql_fetch_array(mysql_query("select * from asnums where asn='" . addslashes($asnum) . "'"));
	
	if ($row) {
		return array(name => $row['asname'], descr => $row['descr'], country => $row['country']);
	} else {
		return array(name => "AS$asnum", descr => "AS $asnum");
	}*/
}

function readasinfodb() {
	global $asinfofile;
	
	if (!file_exists($asinfofile))
		return array();
	
	$fd = fopen($asinfofile, "r");
	$asinfodb = array();
	while (!feof($fd)) {
		$line = trim(fgets($fd));
		if (preg_match("/(^\\s*#)|(^\\s*$)/", $line))
			continue;	/* empty line or comment */
		
		list($asn,$asname,$descr,$country) = explode("\t", $line);
		
		$asinfodb[$asn] = array(
			name => $asname,
			descr => $descr,
			country => $country
		);
	}
	fclose($fd);
	
	return $asinfodb;
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
	global $daystatsfile;
	
	/* first step: walk the data for all ASes to determine the top 5 for the given link */
	$fd = fopen($daystatsfile, "r");
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
			if (strpos($cols[$i], "_in") !== false)
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
