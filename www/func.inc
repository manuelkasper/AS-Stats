<?php
/*
 * $Id$
 * 
 * written by Manuel Kasper <mk@neon1.net> for Monzoon Networks AG
 */

require_once("config_defaults.inc");
require_once('config.inc');

/* make sure we have enough memory, as some pages can be quite memory intensive */
ini_set("memory_limit", "256M");

/* note: you might want to put the data from asinfo.txt into an SQL
   database to avoid having to read the whole file all the time */
function getASInfo($asnum) {
	global $asinfodb;
	
	if (!isset($asinfodb))
		$asinfodb = readasinfodb();
	
	if ($asinfodb[$asnum])
		return $asinfodb[$asnum];
	else
		return array('name' => "AS$asnum", 'descr' => "AS $asnum");
	
	/*$row = mysql_fetch_array(mysql_query("select * from asnums where asn='" . addslashes($asnum) . "'"));
	
	if ($row) {
		return array('name' => $row['asname'], 'descr' => $row['descr'], 'country' => $row['country']);
	} else {
		return array('name' => "AS$asnum", 'descr' => "AS $asnum");
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
		
		$asnarr = explode("\t", $line);
		$asn = $asnarr[0];
		$asname = $asnarr[1];
		$descr = $asnarr[2];
		if (isset($asnarr[3])) $country = $asnarr[3];
		
		$asinfodb[$asn] = array(
			'name' => $asname,
			'descr' => $descr,
			'country' => $country
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

		$known = false;
		foreach ($knownlinks as $link) {
		    if (in_array($tag,$link)) {$known=true;}
		}

		if (!$known) {
		    $knownlinks[] = array(
			'routerip' => $routerip,
			'ifindex' => $ifindex,
			'tag' => $tag,
			'descr' => $descr,
			'color' => $color
		    );
		}
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
		$tot_v6_in = 0;
		$tot_v6_out = 0;
		
		for ($i = 1; $i < count($els); $i++) {
			if (strpos($cols[$i], "_in") !== false) {
				$tot_in += $els[$i];
				if (strpos($cols[$i], "_v6_") !== false)
					$tot_v6_in += $els[$i];
			} else {
				$tot_out += $els[$i];
				if (strpos($cols[$i], "_v6_") !== false)
					$tot_v6_out += $els[$i];
			}
		}
		
		$asstats[$as] = array($tot_in, $tot_out, $tot_v6_in, $tot_v6_out);
		
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

function getRRDFileForAS($as) {
	global $rrdpath;
	return "$rrdpath/" . sprintf("%02x", $as % 256) . "/$as.rrd";
}

function getASSET($asset) {
	global $whois, $assetpath, $asset_cache_life;
	
	/* sanity check */
	if (!preg_match("/^[a-zA-Z0-9:_-]+$/", $asset))
		return null;

	$assetfile = $assetpath."/".$asset.".txt";

	# check if file exist and cache
	$filemtime = @filemtime($assetfile);	
	if (!$filemtime or (time() - $filemtime >= $asset_cache_life)) {
        $cmd = $whois ." -h whois.radb.net '!i".$asset."'";

        $return_aslist = explode("\n",shell_exec($cmd));
		
		/* find the line that contains the AS-SET members */
		$aslist = array();
		foreach ($return_aslist as $asline) {
			if (preg_match("/^AS/", $asline)) {
				$aslist = explode(" ", $asline);
				break;
			}
		}
    
        $f = fopen($assetfile,"w");
        foreach ($aslist as $as) {
            fputs($f,$as."\n");
        }
        fclose($f);
	# else read cache file
	} else {
		$f = fopen($assetfile, "r");
    	$aslist = array();

		while (!feof($f)) {
			$line = trim(fgets($f));
			if (!empty($line))
				$aslist[] = $line;
		}
	}

	return $aslist;
}

function clearCacheFileASSET($asset) {
	global $assetpath;
	
	/* sanity check */
	if (!preg_match("/^[a-zA-Z0-9:_-]+$/", $asset))
		return;

	if ( $asset == "all" ) {
		$files = glob($assetpath."/*.txt");
		foreach($files as $file) {
			unlink($file);
		}
	} else {
		$file = $assetpath."/".$asset.".txt";
		unlink($file);
	}
}
