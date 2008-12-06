<?php
/*
 * $Id$
 * 
 * (c) 2008 Monzoon Networks AG. All rights reserved.
 */

require_once('func.inc');

$ntop = 20;

if ($_GET['n'])
	$ntop = (int)$_GET['n'];
if ($ntop > 200)
	$ntop = 200;

$topas = getasstats_top($ntop);

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
Top AS | <a href="history.php">View an AS</a> | <a href="linkusage.php">Link usage</a></form>
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
			$flagfile = "flags/f0-" . strtolower($asinfo['country']) . ".gif";
			if (file_exists($flagfile)):
				$is = getimagesize($flagfile);
			?>
			<img src="<?php echo $flagfile; ?>" <?php echo $is[3]; ?>>
			<?php endif; ?>
			AS<?php echo $as; ?>: <?php echo $asinfo['descr']; ?>
		</div>
		<div class="small">~ <?php echo format_bytes($nbytes[0]); ?> in / 
			<?php echo format_bytes($nbytes[1]); ?> out in the last 24 hours</div>
		
		<div class="rank">
			#<?php echo ($i+1); ?>
		</div>
	</th>
	<td>
		<a href="history.php?as=<?php echo $as; ?>" target="_blank"><img alt="AS graph" src="gengraph.php?as=<?php echo $as; ?>&width=500&height=150&nolegend=1" width="581" height="204" border="0" /></a>
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
	echo "<td width=\"9\" height=\"18\" style=\"background-color: #{$link['color']}\">&nbsp;</td>";
	echo "<td width=\"9\" height=\"18\" style=\"opacity: 0.73; background-color: #{$link['color']}\">&nbsp;</td>";
	echo "</tr></table>";
	
	echo "</td><td>&nbsp;" . $link['descr'] . "</td></tr>\n";
}
?>
</table>
</div>

<div id="footer">
AS-Stats v1.2 written by Manuel Kasper, Monzoon Networks AG.<br/>
<?php if ($outispositive): ?>
Outbound traffic: positive / Inbound traffic: negative
<?php else: ?>
Inbound traffic: positive / Outbound traffic: negative
<?php endif; ?>
</div>

</body>
</html>
