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

$width = $default_graph_width;
$height = $default_graph_height;
if (isset($_GET['width']))
	$width = (int)$_GET['width'];
if (isset($_GET['height']))
	$height = (int)$_GET['height'];
$v6_el = "";
if (@$_GET['v'] == 6)
	$v6_el = "v6_";

$knownlinks = getknownlinks();
$rrdfile = getRRDFileForAS($as);

if ($compat_rrdtool12) {
	/* cannot use full-size-mode - must estimate height/width */
	$height -= 65;
	$width -= 81;
	if ($vertical_label)
		$width -= 16;
}

$cmd = "$rrdtool graph - " .
	"--slope-mode --alt-autoscale -u 0 -l 0 --imgformat=PNG --base=1000 --height=$height --width=$width " .
	"--color BACK#ffffff00 --color SHADEA#ffffff00 --color SHADEB#ffffff00 ";

if (!$compat_rrdtool12)
	$cmd .= "--full-size-mode ";

if ($vertical_label) {
	if($outispositive)
		$cmd .= "--vertical-label '<- IN | OUT ->' ";
	else
		$cmd .= "--vertical-label '<- OUT | IN ->' ";
}

if($showtitledetail && $_GET['dname'] != "")
	$cmd .= "--title " . escapeshellarg($_GET['dname']) . " ";
else
	if (isset($_GET['v']) && is_numeric($_GET['v']))
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

if ($compat_rrdtool12) {
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
} else {
	$tot_in_bits = "CDEF:tot_in_bits=0";
	$tot_out_bits = "CDEF:tot_out_bits=0";

	/* generate a CDEF for each DEF to multiply by 8 (bytes to bits), and reverse for outbound */
	foreach ($knownlinks as $link) {
		$cmd .= "CDEF:{$link['tag']}_{$v6_el}in_bits_pos={$link['tag']}_{$v6_el}in,8,* ";
		$cmd .= "CDEF:{$link['tag']}_{$v6_el}out_bits_pos={$link['tag']}_{$v6_el}out,8,* ";
		$tot_in_bits .= ",{$link['tag']}_{$v6_el}in_bits_pos,ADDNAN";
		$tot_out_bits .= ",{$link['tag']}_{$v6_el}out_bits_pos,ADDNAN";
	}

	$cmd .= "$tot_in_bits ";
	$cmd .= "$tot_out_bits ";

	$cmd .= "VDEF:tot_in_bits_95th_pos=tot_in_bits,95,PERCENT ";
	$cmd .= "VDEF:tot_out_bits_95th_pos=tot_out_bits,95,PERCENT ";

	if ($outispositive) {
		$cmd .= "CDEF:tot_in_bits_95th=tot_in_bits,POP,tot_in_bits_95th_pos,-1,* ";
		$cmd .= "CDEF:tot_out_bits_95th=tot_out_bits,POP,tot_out_bits_95th_pos,1,* ";
	} else {
		$cmd .= "CDEF:tot_in_bits_95th=tot_in_bits,POP,tot_in_bits_95th_pos,1,* ";
		$cmd .= "CDEF:tot_out_bits_95th=tot_out_bits,POP,tot_out_bits_95th_pos,-1,* ";
	}

	foreach ($knownlinks as $link) {
		if ($outispositive) {
			$cmd .= "CDEF:{$link['tag']}_{$v6_el}in_bits={$link['tag']}_{$v6_el}in_bits_pos,-1,* ";
			$cmd .= "CDEF:{$link['tag']}_{$v6_el}out_bits={$link['tag']}_{$v6_el}out_bits_pos,1,* ";
		} else {
			$cmd .= "CDEF:{$link['tag']}_{$v6_el}out_bits={$link['tag']}_{$v6_el}out_bits_pos,-1,* ";
			$cmd .= "CDEF:{$link['tag']}_{$v6_el}in_bits={$link['tag']}_{$v6_el}in_bits_pos,1,* ";
		}
	}
}

/* generate graph area/stack for inbound */
$i = 0;
foreach ($knownlinks as $link) {
	if ($outispositive && $brighten_negative)
		$col = $link['color'] . "BB";
	else
		$col = $link['color'];
	$descr = str_replace(':', '\:', $link['descr']); # Escaping colons in description
	$cmd .= "AREA:{$link['tag']}_{$v6_el}in_bits#{$col}:\"{$descr}\"";
	if ($i > 0)
		$cmd .= ":STACK";
	$cmd .= " ";
	$i++;
}

/* generate graph area/stack for outbound */
$i = 0;
foreach ($knownlinks as $link) {
	if ($outispositive || !$brighten_negative)
		$col = $link['color'];
	else
		$col = $link['color'] . "BB";
	$cmd .= "AREA:{$link['tag']}_{$v6_el}out_bits#{$col}:";
	if ($i > 0)
		$cmd .= ":STACK";
	$cmd .= " ";
	$i++;
}

if ($show95th && !$compat_rrdtool12) {
	$cmd .= "LINE1:tot_in_bits_95th#FF0000 ";
	$cmd .= "LINE1:tot_out_bits_95th#FF0000 ";
	$cmd .= "GPRINT:tot_in_bits_95th_pos:'95th in %6.2lf%s' ";
	$cmd .= "GPRINT:tot_out_bits_95th_pos:'95th out %6.2lf%s' ";
}

# zero line
$cmd .= "HRULE:0#00000080";

passthru($cmd);

exit;

?>
