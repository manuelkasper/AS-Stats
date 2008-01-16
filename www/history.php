<?php
/*
 * $Id$
 * 
 * (c) 2008 Monzoon Networks AG. All rights reserved.
 */

require_once('func.inc');

$as = $_GET['as'];
if ($as)
	$asinfo = getASInfo($as);

?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<title>History for AS<?php echo $as; ?>: <?php echo $asinfo['descr']; ?></title>
	<link rel="stylesheet" type="text/css" href="style.css" />
</head>

<body>

<div id="nav"><a href="top.php">Top AS</a> | View an AS | <a href="linkusage.php">Link usage</a></div>

<?php if ($as): ?>
<div class="pgtitle">History for AS<?php echo $as; ?>: <?php echo $asinfo['descr']; ?></div>

<?php if (!file_exists("$rrdpath/$as.rrd")): ?>
No data found for AS <?php echo $as; ?>
<?php else: ?>
<div class="title">Daily</div>
<img class="detailgraph" src="gengraph.php?as=<?php echo $as; ?>" alt="daily graph" />

<div class="title">Weekly</div>
<img class="detailgraph" src="gengraph.php?as=<?php echo $as; ?>&start=<?php echo (time() - 7*86400);?>&end=<?php echo time(); ?>" alt="weekly graph" />

<div class="title">Monthly</div>
<img class="detailgraph" src="gengraph.php?as=<?php echo $as; ?>&start=<?php echo (time() - 30*86400);?>&end=<?php echo time(); ?>" alt="monthly graph" />

<div class="title">Yearly</div>
<img class="detailgraph" src="gengraph.php?as=<?php echo $as; ?>&start=<?php echo (time() - 365*86400);?>&end=<?php echo time(); ?>" alt="yearly graph" />
<?php endif; ?>
<?php else: ?>

<div class="pgtitle">View history for an AS</div>

<form action="" method="GET">
AS: <input type="text" name="as" size="6">
<input type="submit" value="Go">
</form>
<?php endif; ?>

<div id="footer">
&copy; 2008 Monzoon Networks AG. All rights reserved.
</div>

</body>
</html>
