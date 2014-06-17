<?php
/*
 * $Id$
 * 
 * (c) 2008 Monzoon Networks AG. All rights reserved.
 */

require_once('func.inc');

if (isset($_GET['n']))
	$ntop = (int)$_GET['n'];
if ($ntop > 200)
	$ntop = 200;

$topas = getasstats_top($ntop);

if (@$_GET['numhours']) {
	$start = time() - $_GET['numhours']*3600;
	$end = time();
} else {
	$start = "";
	$end = "";
}

?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<meta http-equiv="Refresh" content="300" />
	<title>Top <?php echo $ntop; ?> AS</title>
	<link rel="stylesheet" type="text/css" href="style.css" />
</head>

<body>

<div id="nav">
<form action="" method="get">
Number of AS: 
<input type="text" name="n" size="4" value="<?php echo $ntop; ?>" />
<input type="submit" value="Go" style="margin-right: 2em" />
<?php include('headermenu.inc'); ?>
</form>
</div>
<div class="pgtitle">Top <?php echo $ntop; ?> AS</div>

<table class="astable">

<?php $i = 0; foreach ($topas as $as => $nbytes):
$asinfo = getASInfo($as);
$class = (($i % 2) == 0) ? "even" : "odd";
?>
<tr class="<?php echo $class; ?>">
	<th>
		<div class="title">
			<?php
			$flagfile = "flags/" . strtolower($asinfo['country']) . ".gif";
			if (file_exists($flagfile)):
				$is = getimagesize($flagfile);
			?>
			<img src="<?php echo $flagfile; ?>" <?php echo $is[3]; ?>>
			<?php endif; ?>
			AS<?php echo $as; ?>: <?php echo $asinfo['descr']; ?>
		</div>
		<div class="small">IPv4: ~ <?php echo format_bytes($nbytes[0]); ?> in / 
			<?php echo format_bytes($nbytes[1]); ?> out in the last 24 hours</div>
		<?php if ($showv6): ?>
		<div class="small">IPv6: ~ <?php echo format_bytes($nbytes[2]); ?> in / 
			<?php echo format_bytes($nbytes[3]); ?> out in the last 24 hours</div>
		<?php endif; ?>

<?php if (!empty($customlinks)): ?>
		<div class="customlinks">
<?php 
$htmllinks = array();
foreach ($customlinks as $linkname => $url) {
	$url = str_replace("%as%", $as, $url);
	$htmllinks[] = "<a href=\"$url\" target=\"_blank\">" . htmlspecialchars($linkname) . "</a>\n";
}
echo join(" | ", $htmllinks);
?>
		</div>
<?php endif; ?>
		
		<div class="rank">
			#<?php echo ($i+1); ?>
		</div>
	</th>
	<td>
		<?php if ($showv6): ?>
		<a href="history.php?v=4&amp;as=<?php echo $as; ?>" target="_blank"><img alt="AS graph" src="gengraph.php?as=<?php echo $as; ?>&amp;width=<?php echo $top_graph_width ?>&amp;height=<?php echo $top_graph_height ?>&amp;v=4&amp;nolegend=1&amp;dname=<?php echo rawurlencode("AS" . $as . " - " . $asinfo['descr'] . " - IPV4"); ?>&amp;start=<?php echo $start; ?>&amp;end=<?php echo $end; ?>" width="<?php echo $top_graph_width ?>" height="<?php echo $top_graph_height ?>" border="0" /></a>
		<a href="history.php?v=6&amp;as=<?php echo $as; ?>" target="_blank"><img alt="AS graph" src="gengraph.php?as=<?php echo $as; ?>&amp;width=<?php echo $top_graph_width ?>&amp;height=<?php echo $top_graph_height ?>&amp;v=6&amp;nolegend=1&amp;dname=<?php echo rawurlencode("AS" . $as . " - " . $asinfo['descr'] . " - IPV6"); ?>&amp;start=<?php echo $start; ?>&amp;end=<?php echo $end; ?>" width="<?php echo $top_graph_width ?>" height="<?php echo $top_graph_height ?>" border="0" /></a>
		<?php else: ?>
		<a href="history.php?as=<?php echo $as; ?>" target="_blank"><img alt="AS graph" src="gengraph.php?as=<?php echo $as; ?>&amp;width=<?php echo $top_graph_width ?>&amp;height=<?php echo $top_graph_height ?>&amp;nolegend=1&amp;dname=<?php echo rawurlencode("AS" . $as . " - " . $asinfo['descr'] . ""); ?>&amp;start=<?php echo $start; ?>&amp;end=<?php echo $end; ?>" width="<?php echo $top_graph_width ?>" height="<?php echo $top_graph_height ?>" border="0" /></a>
		<?php endif; ?>
	</td>
</tr>
<?php $i++; endforeach; ?>

</table>

<div id="legend">
<table>
<?php
$knownlinks = getknownlinks();
foreach ($knownlinks as $link) {
	echo "<tr><td style=\"border: 4px solid #fff;\">";
	
	echo "<table style=\"border-collapse: collapse; margin: 0; padding: 0\"><tr>";
        if ($brighten_negative) {
		echo "<td width=\"9\" height=\"18\" style=\"background-color: #{$link['color']}\">&nbsp;</td>";
		echo "<td width=\"9\" height=\"18\" style=\"opacity: 0.73; background-color: #{$link['color']}\">&nbsp;</td>";
	} else {
		echo "<td width=\"18\" height=\"18\" style=\"background-color: #{$link['color']}\">&nbsp;</td>";
	}
	echo "</tr></table>";
	
	echo "</td><td>&nbsp;" . $link['descr'] . "</td></tr>\n";
}
?>
</table>
</div>

<?php include('footer.inc'); ?>

</body>
</html>
