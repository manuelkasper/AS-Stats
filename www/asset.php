<?php
/*
 * written by Nicolas Debrigode, Hexanet SAS
 */

error_reporting(0);

require_once('func.inc');

$asset = strtoupper($_GET['asset']);

$action = $_GET['action'];
if ( $action == "clearall" ) {
	clearCacheFileASSET("all");
	header("Location: asset.php");
} else if ( $action == "clear" and $asset ) {
	clearCacheFileASSET($asset);
	header("Location: asset.php?asset=".$asset."");
} else {

?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <meta http-equiv="Refresh" content="300" />

	<?php if ($asset): ?>
    <title>History for AS-SET: <?php echo $asset; ?></title>
	<?php else: ?>
    <title>History for AS-SET</title>
	<?php endif; ?>
    <link rel="stylesheet" type="text/css" href="style.css" />
</head>

<body  onload="document.forms[0].asset.focus(); document.forms[0].asset.select();">
<div id="nav"><a href="top.php">Top AS</a> | <a href="history.php">View an AS</a> | View an AS-SET | <a href="linkusage.php">Link usage</a></div>

<?php if ($asset): ?>
<div class="pgtitle">History for AS-SET: <?php echo $asset; ?></div>
<?php else: ?>
<div class="pgtitle">View history for an AS-SET</div>
<?php endif; ?>

<?php 
	if ($asset): ?>
		<div id="nav"><a href="asset.php?asset=<?php echo $asset ?>&amp;action=clear">Remove AS-SET cache file for <?php echo $asset ?>.</a></div>
<?php
		$aslist = getASSET($asset);

		if ($aslist[0]):
			foreach( $aslist as $as ):
				$as_tmp = substr($as, 2);
				if (is_numeric($as_tmp)):
					$as_num[]=$as_tmp;
				else:
					$as_other[]=$as;
				endif;
			endforeach;
		
		if ($as_other[0]) :
?>

<div class="title">Other AS-SETs:</div>

<ul style="margin-bottom: 2.5em">
	<?php
		foreach( $as_other as $as ):
	?>
		<li><a href="asset.php?asset=<?php echo $as; ?>"><?php echo $as; ?></a></li>
	<?php endforeach; ?>
</ul>

<div class="title" style="margin-bottom: 0.5em">This AS-SET:</div>

<?php
		endif;

		$i = 0;
?>

<table class="astable">
<?php
		foreach( $as_num as $as ): 
			$asinfo = getASInfo($as);$class = (($i % 2) == 0) ? "even" : "odd";
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

		<div class="rank">
			#<?php echo ($i+1); ?>
		 </div>
	</th>
	<td>
		<?php 
			$rrdfile = getRRDFileForAS($as);
			
			if (file_exists($rrdfile)): ?>
        		<a href="history.php?as=<?php echo $as; ?>" target="_blank"><img alt="AS graph" src="gengraph.php?as=<?php echo $as; ?>&amp;width=500&amp;height=150&amp;v=4&amp;nolegend=1" width="581" height="204" border="0" /></a>
			<?php else: ?>
				<p><center>No data found for AS<?php echo $as; ?></center></p>
			<?php endif; ?>
	</td>
</tr>

<?php 
		$i++; 
		endforeach; 
?>

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

<?php	
		else:
			echo "No data found for AS-SET: ".$asset;
		endif;
	else:
?>
<div id="nav"><a href="asset.php?action=clearall">Remove all AS-SET cache files.</a></div>
<form action="" method="get">
AS-SET: <input type="text" name="asset" size="20" />
<input type="submit" value="Go" />
</form>

<?php endif; ?>

<?php include('footer.inc'); ?>

</body>
</html>

<?php } ?>
