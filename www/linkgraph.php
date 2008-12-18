<?php
/*
 * $Id$
 * 
 * written by Manuel Kasper, Monzoon Networks AG <mkasper@monzoon.net>
 */

require_once('func.inc');

$numtop = 10;
if ($_GET['numtop'] && $_GET['numtop'] <= 50)
	$numtop = $_GET['numtop'];

$ascolors = array("D41C0E", "E45605", "FECF12", "2FA11C", "19BB7C", "0A4484", "0A7484", "4CB4C4", "971928", "1f348c");

$link = $_GET['link'];
if (!preg_match("/^[0-9a-zA-Z]+$/", $link))
	die("Invalid link");

/* first step: walk the data for all ASes to determine the top 5 for the given link */
$fd = fopen($daystatsfile, "r");
$cols = explode("\t", trim(fgets($fd)));
$asstats = array();

/* figure out which columns contain data for the links were's interested in */
$incol = array_search("{$link}_in", $cols);
$outcol = array_search("{$link}_out", $cols);
if (!$incol || !$outcol)
	die("Couldn't find columns");

/* read in all AS stats */
while (!feof($fd)) {
	$line = trim(fgets($fd));
	if (!$line)
		continue;
	
	$els = explode("\t", $line);
	
	/* first element is the AS */
	$asstats[$els[0]] = $els[$incol] + $els[$outcol];
}
fclose($fd);

/* now sort the AS stats to find the top $numtop */
arsort($asstats, SORT_NUMERIC);

/* extract first $numtop and consolidate the rest */
$topas = array_slice($asstats, 0, $numtop, true);

for ($i = 0; $i < $numtop; $i++)
	array_shift($asstats);

$restdata = 0;
foreach ($asstats as $as => $totaldata) {
	$restdata += $totaldata;
}

/* now make a beautiful graph :) */
header("Content-Type: image/png");

$width = 500;
$height = 300;
if ($_GET['width'])
	$width = (int)$_GET['width'];
if ($_GET['height'])
	$height = (int)$_GET['height'];

$knownlinks = getknownlinks();

$cmd = "$rrdtool graph - " .
	"--slope-mode --alt-autoscale -u 0 -l 0 --imgformat=PNG --base=1000 --height=$height --width=$width " .
	"--color BACK#ffffff00 --color SHADEA#ffffff00 --color SHADEB#ffffff00 ";

/* geneate RRD DEFs */
foreach ($topas as $as => $traffic) {
	$cmd .= "DEF:as{$as}_in=\"$rrdpath/$as.rrd\":{$link}_in:AVERAGE ";
	$cmd .= "DEF:as{$as}_out=\"$rrdpath/$as.rrd\":{$link}_out:AVERAGE ";
}

/* generate a CDEF for each DEF to multiply by 8 (bytes to bits), and reverse for outbound */
foreach ($topas as $as => $traffic) {
	if ($outispositive) {
		$cmd .= "CDEF:as{$as}_in_bits=as{$as}_in,-8,* ";
		$cmd .= "CDEF:as{$as}_out_bits=as{$as}_out,8,* ";
	} else {
		$cmd .= "CDEF:as{$as}_in_bits=as{$as}_in,8,* ";
		$cmd .= "CDEF:as{$as}_out_bits=as{$as}_out,-8,* ";	
	}
}

/* generate graph area/stack for inbound */
$i = 0;
foreach ($topas as $as => $traffic) {
	$asinfo = getASInfo($as);
	$descr = str_replace(":", "\\:", utf8_decode($asinfo['descr']));

	$cmd .= "AREA:as{$as}_in_bits#{$ascolors[$i]}:\"AS{$as} ({$descr})\\n\"";
	if ($i > 0)
		$cmd .= ":STACK";
	$cmd .= " ";
	$i++;
}

/* generate graph area/stack for outbound */
$i = 0;
foreach ($topas as $as => $traffic) {
	$cmd .= "AREA:as{$as}_out_bits#{$ascolors[$i]}:";
	if ($i > 0)
		$cmd .= ":STACK";
	$cmd .= " ";
	$i++;
}

# zero line
$cmd .= "HRULE:0#00000080";

passthru($cmd);

exit;

?>
