<?php
/*
 * $Id$
 * 
 * (c) 2008 Monzoon Networks AG. All rights reserved.
 */

require_once('func.inc');

if(!isset($peerusage))
	$peerusage = 0;

if (isset($_GET['n']))
	$ntop = (int)$_GET['n'];
if ($ntop > 200)
	$ntop = 200;

$hours = 24;
if (@$_GET['numhours'])
	$hours = (int)$_GET['numhours'];

if ($peerusage)
	$statsfile = $daypeerstatsfile;
else {
	$statsfile = statsFileForHours($hours);
}
$label = statsLabelForHours($hours);

$knownlinks = getknownlinks();
$selected_links = array();
foreach($knownlinks as $link){
	if(isset($_GET["link_${link['tag']}"]))
		$selected_links[] = $link['tag'];
}

$topas = getasstats_top($ntop, $statsfile, $selected_links);

$start = time() - $hours*3600;
$end = time();

?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<meta http-equiv="Refresh" content="300" />
	<title>Top <?php echo $ntop; ?> AS<?php if($peerusage) echo " peer"; ?> (<?php echo $label?>)</title>
	<link rel="stylesheet" type="text/css" href="style.css" />
</head>

<body>

<div id="nav">
<form action="" method="get">
Number of AS: 
<input type="text" name="n" size="4" value="<?php echo $ntop; ?>" />
<input type="hidden" name="numhours" value="<?php echo $hours; ?>" />
<input type="submit" value="Go" style="margin-right: 2em" />
<?php include('headermenu.inc'); ?>
</form>
</div>
<div class="pgtitle">Top <?php echo $ntop; ?> AS<?php if($peerusage) echo " peer"; ?> (<?php echo $label?>)</div>

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
			<?php echo format_bytes($nbytes[1]); ?> out in the last <?php echo $label?></div>
		<?php if ($showv6): ?>
		<div class="small">IPv6: ~ <?php echo format_bytes($nbytes[2]); ?> in / 
			<?php echo format_bytes($nbytes[3]); ?> out in the last <?php echo $label?></div>
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
		<?php
		echo getHTMLUrl($as, 4, $asinfo['descr'], $start, $end, $peerusage, $selected_links);
		if ($showv6)
			echo getHTMLUrl($as, 6, $asinfo['descr'], $start, $end, $peerusage, $selected_links);
		?>
	</td>
</tr>
<?php $i++; endforeach; ?>

</table>

<div id="legend">
<form method='get'>
<input type='hidden' name='numhours' value='<?php echo $hours; ?>'/>
<input type='hidden' name='n' value='<?php echo $ntop; ?>'/>
<table>
<?php
$knownlinks = getknownlinks();
foreach ($knownlinks as $link) {
	$tag = "link_${link['tag']}";

	echo "<tr><td><input type='checkbox'";
	if(isset($_GET[$tag]) && $_GET[$tag] == 'on')
		echo " checked='checked'";

	echo "name=\"$tag\" id=\"$tag\"/></td><td style=\"border: 4px solid #fff;\">";
	
	echo "<table style=\"border-collapse: collapse; margin: 0; padding: 0\"><tr>";
        if ($brighten_negative) {
		echo "<td width=\"9\" height=\"18\" style=\"background-color: #{$link['color']}\">&nbsp;</td>";
		echo "<td width=\"9\" height=\"18\" style=\"opacity: 0.73; background-color: #{$link['color']}\">&nbsp;</td>";
	} else {
		echo "<td width=\"18\" height=\"18\" style=\"background-color: #{$link['color']}\">&nbsp;</td>";
	}
	echo "</tr></table>";
	
	echo "</td><td><label for=\"$tag\">&nbsp;${link['descr']}</label></td></tr>\n";
}
?>
</table>
<center><input type='submit' value='Filter'/></center>
</form>
</div>

<?php include('footer.inc'); ?>

</body>
</html>
