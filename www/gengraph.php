<?php
/*
 * $Id$
 * 
 * written by Manuel Kasper <mk@neon1.net> for Monzoon Networks AG
 */

require_once('func.inc');

$as = $_GET['as'];
if (!preg_match("/^[0-9a-zA-Z]+$/", $as))
	die("Invalid AS");

header("Content-Type: image/png");

$width = 500;
$height = 300;
if (isset($_GET['width']))
	$width = (int)$_GET['width'];
if (isset($_GET['height']))
	$height = (int)$_GET['height'];
$v6_el = "";
if (@$_GET['v'] == 6)
	$v6_el = "v6_";

$knownlinks = getknownlinks();
$rrdfile = getRRDFileForAS($as);

$cmd = "$rrdtool graph - " .
	"--slope-mode --alt-autoscale -u 0 -l 0 --imgformat=PNG --base=1000 --height=$height --width=$width " .
	"--color BACK#ffffff00 --color SHADEA#ffffff00 --color SHADEB#ffffff00 ";

if (@$_GET['v'])
	$cmd .= "--title IPv" . $_GET['v'] . " ";

if (isset($_GET['nolegend']))
	$cmd .= "--no-legend ";

if (isset($_GET['start']) && is_numeric($_GET['start']))
	$cmd .= "--start " . $_GET['start'] . " ";

if (isset($_GET['end']) && is_numeric($_GET['end']))
	$cmd .= "--end " . $_GET['end'] . " ";

/* geneate RRD DEFs */
foreach ($knownlinks as $link) {
	$cmd .= "DEF:{$link['tag']}_{$v6_el}in=\"$rrdfile\":{$link['tag']}_{$v6_el}in:AVERAGE ";
	$cmd .= "DEF:{$link['tag']}_{$v6_el}out=\"$rrdfile\":{$link['tag']}_{$v6_el}out:AVERAGE ";
}

/* generate a CDEF for each DEF to multiply by 8 (bytes to bits), and reverse for outbound */
foreach ($knownlinks as $link) {
	if ($outispositive) {
		$cmd .= "CDEF:{$link['tag']}_{$v6_el}in_bits={$link['tag']}_{$v6_el}in,-8,* ";
		$cmd .= "CDEF:{$link['tag']}_{$v6_el}out_bits={$link['tag']}_{$v6_el}out,8,* ";
	} else {
		$cmd .= "CDEF:{$link['tag']}_{$v6_el}in_bits={$link['tag']}_{$v6_el}in,8,* ";
		$cmd .= "CDEF:{$link['tag']}_{$v6_el}out_bits={$link['tag']}_{$v6_el}out,-8,* ";
	}
}

/* generate graph area/stack for inbound */
$i = 0;
foreach ($knownlinks as $link) {
	if ($outispositive)
		$col = $link['color'] . "BB";
	else
		$col = $link['color'];
	$cmd .= "AREA:{$link['tag']}_{$v6_el}in_bits#{$col}:\"{$link['descr']}\"";
	if ($i > 0)
		$cmd .= ":STACK";
	$cmd .= " ";
	$i++;
}

/* generate graph area/stack for outbound */
$i = 0;
foreach ($knownlinks as $link) {
	if ($outispositive)
		$col = $link['color'];
	else
		$col = $link['color'] . "BB";
	$cmd .= "AREA:{$link['tag']}_{$v6_el}out_bits#{$col}:";
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
