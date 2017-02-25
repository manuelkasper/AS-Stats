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
	
	if (@$asinfodb[$asnum])
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

function getasstats_top($ntop, $statfile, $selected_links) {
	try{
		$db = new SQLite3($statfile);
	}catch(Exception $e){
		return array();
	}

	if(sizeof($selected_links) == 0){
		$selected_links = array();
		foreach(getknownlinks() as $link)
			$selected_links[] = $link['tag'];
	}

	$nlinks = 0;
	$query_total = '0';
	$query_links = '';
	foreach($selected_links as $tag){
		$query_links .= "${tag}_in, ${tag}_out, ${tag}_v6_in, ${tag}_v6_out, ";
		$nlinks += 4;
		$query_total .= " + ${tag}_in + ${tag}_out + ${tag}_v6_in + ${tag}_v6_out";
	}
	$query = "select asn, $query_links $query_total as total from stats order by total desc limit $ntop";

	$asn = $db->query($query);
	$asstats = array();
	while($row = $asn->fetchArray()){
		$tot_in = 0;
		$tot_out = 0;
		$tot_v6_in = 0;
		$tot_v6_out = 0;
		foreach($row as $key => $value){
			if (strpos($key, '_in') !== false) {
				if (strpos($key, '_v6_') !== false)
					$tot_v6_in += $value;
				else
					$tot_in += $value;
			} else if (strpos($key, '_out') !== false) {
				if (strpos($key, '_v6_') !== false)
					$tot_v6_out += $value;
				else
					$tot_out += $value;
			}
		}

		$asstats[$row['asn']] = array($tot_in, $tot_out, $tot_v6_in, $tot_v6_out);
	}
	return $asstats;
}

function format_bytes($bytes) {
	if ($bytes >= 1099511627776)
		return sprintf("%.2f TB", $bytes / 1099511627776);
	else if ($bytes >= 1073741824)
		return sprintf("%.2f GB", $bytes / 1073741824);
	else if ($bytes >= 1048576)
		return sprintf("%.2f MB", $bytes / 1048576);
	else if ($bytes >= 1024)
		return sprintf("%d KB", $bytes / 1024);
	else
		return "$bytes bytes";
}

function getRRDFileForAS($as, $peer = 0) {
	global $rrdpath;
	$prefix = ($peer == 1) ? "$rrdpath/peeras" : "$rrdpath";
	return "$prefix/" . sprintf("%02x", $as % 256) . "/$as.rrd";
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

# return the html used in top.php : <a href=blabla><img src=blabla/></url>
function getHTMLUrl($as, $ipversion, $desc, $start, $end, $peerusage, $selected_links = array()){
	$img = getHTMLImg($as, $ipversion, $desc, $start, $end, $peerusage, '', '', false, $selected_links);
	$result = "<a href='history.php?as=$as&peerusage=$peerusage&v=$ipversion' target='_blank'>$img</a>";
	return($result);
}

# return the html used in history.php (for example) : <img src=blabla/>
function getHTMLImg($as, $ipversion, $desc, $start, $end, $peerusage, $alt, $class, $history = false, $selected_links=array()){
	global $top_graph_width;
	global $top_graph_height;

	$dname = rawurlencode("AS$as - $desc - IPV$ipversion");

	$result = "<img alt='$alt' class='$class' src='gengraph.php?v=$ipversion&as=$as&peerusage=$peerusage&dname=$dname&start=$start&end=$end";
	if(!$history)
		$result .= "&width=$top_graph_width&height=$top_graph_height&nolegend=1";

	if(sizeof($selected_links) != 0){
		$result .= "&selected_links=";
		foreach($selected_links as $link)
			$result .= "$link,";
		$result = rtrim($result, ',');
	}

	$result .= "'";

	if(!$history)
		$result .= " width='$top_graph_width' height='$top_graph_height' border='0'";
	$result .= "/>";
	return($result);
}

function statsFileForHours($hours) {
	global $top_intervals, $daystatsfile;
	foreach ($top_intervals as $interval) {
		if ($interval['hours'] == $hours && @$interval['statsfile']) {
			return $interval['statsfile'];
		}
	}
	return $daystatsfile;
}

function statsLabelForHours($hours) {
	global $top_intervals;
	foreach ($top_intervals as $interval) {
		if ($interval['hours'] == $hours && @$interval['label']) {
			return $interval['label'];
		}
	}
	return (int)$hours . " hours";
}
