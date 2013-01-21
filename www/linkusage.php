<?php
/*
 * $Id$
 * 
 * written by Manuel Kasper, Monzoon Networks AG <mkasper@monzoon.net>
 */

require_once('func.inc');

$knownlinks = getknownlinks();

?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<meta http-equiv="Refresh" content="300" />
	<title>Link usage</title>
	<link rel="stylesheet" type="text/css" href="style.css" />
</head>

<body>

<div id="nav"><a href="top.php">Top AS</a> | <a href="history.php">View an AS</a> | <a href="asset.php">View an AS-SET</a> | Link usage</div>
<div class="pgtitle">Link usage - top 10 AS per link</div>

<table class="astable">

<?php $i = 0; foreach ($knownlinks as $link):
$class = (($i % 2) == 0) ? "even" : "odd";
?>
<tr class="<?php echo $class; ?>">
	<th style="width: 15em">
		<div class="title">
			<?php echo $link['descr']; ?>
		</div>
	</th>
	<td>
		<?php if ($showv6): ?>
		<img alt="link graph" src="linkgraph.php?link=<?php echo $link['tag']; ?>&amp;width=500&amp;height=300&amp;v=4" width="581" height="505" border="0" />
		<img alt="link graph" src="linkgraph.php?link=<?php echo $link['tag']; ?>&amp;width=500&amp;height=300&amp;v=6" width="581" height="505" border="0" />
		<?php else: ?>
		<img alt="link graph" src="linkgraph.php?link=<?php echo $link['tag']; ?>&amp;width=500&amp;height=300" width="581" height="494" border="0" />
		<?php endif; ?>
	</td>
</tr>
<?php $i++; endforeach; ?>

</table>

<?php include('footer.inc'); ?>

</body>
</html>
