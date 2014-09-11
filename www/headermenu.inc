<?php 
$dpagename = basename($_SERVER['PHP_SELF'], ".php");

echo "<span>Top AS:</span> ";
foreach ($top_intervals as $interval) {
	echo '<a href="top.php?numhours=' . $interval['hours'] . '"';
	if ($dpagename == "top" && @$_GET['numhours'] == $interval['hours'])
		echo ' class="selected"';
	echo '>' . $interval['label'] . '</a> | ';
}

if($showpeeras == true){
	if ($dpagename == "peerusage"):
		?><a href="peerusage.php" class="selected">Peer 24 hours</a> | <?php
	else:
		?><a href="peerusage.php">Peer 24 hours<a> | <?php
	endif;
}

if ($dpagename == "history"): 
	?><a href="history.php" class="selected">View an AS</a> | <?php
else:
	?><a href="history.php">View an AS</a> | <?php 
endif;


if ($dpagename == "asset"): 
	?><a href="asset.php" class="selected">View an AS-SET</a> | <?php
else:
	?><a href="asset.php">View an AS-SET</a> | <?php 
endif;

if ($dpagename == "linkusage"): 
	?><a href="linkusage.php" class="selected">Link usage</a><?php
else:
	?><a href="linkusage.php">Link usage</a><?php 
endif;

?>
