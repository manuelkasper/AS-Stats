<?php
/*
 * $Id$
 * 
 * written by Manuel Kasper <mk@neon1.net> for Monzoon Networks AG
 */

error_reporting(0);

require_once('func.inc');

$as = str_replace('as','',str_replace(' ','',strtolower($_GET['as'])));
if ($as)
	$asinfo = getASInfo($as);

if(isset($_GET['peerusage']) && $_GET['peerusage'] == '1')
	$peerusage = 1;
else
	$peerusage = 0;

$rrdfile = getRRDFileForAS($as, $peerusage);

?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<meta http-equiv="Refresh" content="300" />
	<title>History for AS<?php echo $as; ?>: <?php echo $asinfo['descr']; ?></title>
	<link rel="stylesheet" type="text/css" href="style.css" />
</head>

<body  onload="document.forms[0].as.focus(); document.forms[0].as.select();">

<div id="nav"><?php include('headermenu.inc'); ?></div>

<?php if ($as): ?>
<div class="pgtitle">History for <?php if($peerusage == 1) echo "peer "; ?>AS<?php echo $as; ?>: <?php echo $asinfo['descr']; ?>
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
</div>

<?php if (!file_exists($rrdfile)): ?>
<p>No data found for AS <?php echo $as; ?></p>
<?php else: ?>
<div class="title">Daily</div>
<?php
echo getHTMLImg($as, 4, $asinfo['descr'], time() - 24 * 3600, time(), $peerusage, 'daily graph', 'detailgraph', true);
if ($showv6)
	echo getHTMLImg($as, 6, $asinfo['descr'], time() - 24 * 3600, time(), $peerusage, 'daily graph', 'detailgraph2', true);
?>

<div class="title">Weekly</div>
<?php
echo getHTMLImg($as, 4, $asinfo['descr'], time() - 7 * 86400, time(), $peerusage, 'weekly graph', 'detailgraph', true);
if ($showv6)
	echo getHTMLImg($as, 6, $asinfo['descr'], time() - 7 * 86400, time(), $peerusage, 'weekly graph', 'detailgraph2', true);
?>

<div class="title">Monthly</div>
<?php
echo getHTMLImg($as, 4, $asinfo['descr'], time() - 30 * 86400, time(), $peerusage, 'monthly graph', 'detailgraph', true);
if ($showv6)
	echo getHTMLImg($as, 6, $asinfo['descr'], time() - 30 * 86400, time(), $peerusage, 'monthly graph', 'detailgraph2', true);
?>

<div class="title">Yearly</div>
<?php
echo getHTMLImg($as, 4, $asinfo['descr'], time() - 365 * 86400, time(), $peerusage, 'yearly graph', 'detailgraph', true);
if ($showv6)
	echo getHTMLImg($as, 6, $asinfo['descr'], time() - 365 * 86400, time(), $peerusage, 'yearly graph', 'detailgraph2', true);
?>

<?php endif; ?>
<?php else: ?>

<div class="pgtitle">View history for an AS</div>

<form action="" method="get">
AS: <input type="text" name="as" size="6" />
<input type="submit" value="Go" />
</form>
<?php endif; ?>

<?php include('footer.inc'); ?>

</body>
</html>
