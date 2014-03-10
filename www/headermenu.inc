<?php 
$dpagename = basename($_SERVER['PHP_SELF'], ".php");

if ($dpagename == "top"): 
	?><a href="top.php" class="selected">Top AS</a> | <?php
else:
	?><a href="top.php">Top AS</a> | <?php 
endif;


if ($dpagename == "top4"): 
	?><a href="top4.php" class="selected">4 Hour</a> | <?php
else:
	?><a href="top4.php">4 Hour</a> | <?php 
endif;


if ($dpagename == "top12"): 
	?><a href="top12.php" class="selected">12 Hour</a> | <?php
else:
	?><a href="top12.php">12 Hour</a> | <?php 
endif;


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
