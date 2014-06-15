## post 1.5

* Added support for multiple links on one ifIndex, based on VLANs. Only
  sFlow, Netflow v9 and v10 (IPFIX) support this. Obviously your router
  needs to provide the information. Just add "/<vlan>" to the ifIndex in
  your knownlinks file.

## 1.5

* Merged netflow-asstatd.pl and sflow-asstatd.pl into one script so
  that it can handle NetFlow and sFlow sources concurrently
  (contributed by Wouter de Jong). Please note the following changes:
	* The sampling rate command line parameter (-s) has been removed. Instead, the sampling rate must now be specified for each link in the knownlinks file to avoid confusion with prior defaults. **If you're using NetFlow without sampling, you need to add the sampling rate 1 to each link.**
	* The command line parameter to set the sFlow listen port has been changed to -P to avoid a clash with the NetFlow port parameter (-p).

## 1.43
	
* Add v6 data sources to add_ds_proc.pl
* Remove closing tag from config.inc to prevent whitespace problems in gengraph.php
* Fix security issue in gengraph.php/linkgraph.php
* Updated asinfo.txt with data from whois.cymru.com.

## 1.42
	
* Try harder to determine IP version for sFlow samples.
*	Add IPFIX support (contributed by Daniel Piekacz)
*	Add experimental NetFlow v5 support	(contributed by Charlie Allom)
*	Fix handling of 64-bit counters for NetFlow v9

## v1.41	

* Generate v6 RRD DS in contrib/sync_ds.pl too (spotted by Peter Hansen)
* sFlow: fix creation of new RRDs when multiple entries with the same
		tag are present in the known links file	(spotted by Michal Buchtik)
* Add startup scripts for FreeBSD (contrib/freebsd)
		(contributed by Michal Buchtik)
* Add support for setting the sampling rate per link in the	knownlinks file.

## v1.40	

*	Add support for NetFlow v9 to netflow-asstatd.pl
		(sponsored by Xplornet Communications Inc.)
*	Add support for IPv6 (for NetFlow v9 and sFlow). Note: existing
	RRDs need to be upgraded (new data sources added for v6) for
	this to work. Enable $showv6 in www/config.inc to see separate
		graphs for IPv6.
*	Add support for 4-byte ASNs (NetFlow v9 and sFlow). Needs testing.
*	Add RRA for 1 month at 4 hour resolution to newly created RRD files.
*	Add links to PeeringDB and robtex	(suggested by Steve Glendinning)
*	Fix AS-SET lookup on systems where the whois command returns additional lines.

## v1.36	

*	Fix creation of new RRDs when multiple entries with the same
		tag are present in the known links file
		(spotted by Michel Moriniaux)
*	Add feature to inspect all ASes in an AS-SET (automatic whois	lookup).
		(contributed by Nicolas Debrigode)
*	Updated asinfo.txt with data from whois.cymru.com.

## v1.35	
	
*	Allow hyphens in link names.	(contributed by Gareth Campling)
*	Smooth I/O burstiness and reduce overall IOPS requirements
		by flushing only 10% of the cache every 25 seconds (instead
		of the entire cache at once every 60 seconds).
		(contributed by James A. T. Rice)

## v1.34	
	
*	Fix for NaN detection in rrd-extractstats.pl for
		64-bit Perl versions
		(contributed by Benjamin Schlageter)
*	Skip missing data sources in rrd-extractstats.pl to avoid
		abort if new data sources are added but the RRDs are not
		updated.

## v1.33	
	
*	Fix for multiple entries with the same tag in the
		knownlinks file (e.g. for LACP)	(contributed by Michal Buchtik)
*	Added sync_ds.pl script to contrib directory, which can
		synchronize the data sources of RRD files with the tags
		defined in the knownlinks file
		(contributed by Michal Buchtik)
*	sflow-asstatd.pl now uses the agent IP instead of the
		UDP source address - this makes it behave properly when
		a proxy is being used	(contributed by Michel Moriniaux)

## v1.32   
	
*	Fix add_ds.sh to support new directory structure
		(contributed by Sergei Veltistov)
*	Fix PHP warnings and move $ntop to config.inc
		(contributed by Michal Buchtik)

## v1.31	
	
*	Set memory_limit to 256 MB in PHP pages (suggested by Steve Colam
		<steve@colam.co.uk>).
*	Allow NetFlow aggregation version 0 as well as 2 to make NetFlow 
	exports from Juniper routers work (suggested by Thomas Mangin
     	<thomas.mangin@exa-networks.co.uk>).
*	Updated asinfo.txt with data from whois.cymru.com.

## v1.3	
	
**Change your start script accordingly...**

*	Changes by Steve Colam <steve@colam.co.uk>:
	- ...-asstatd.pl now accepts parameters (UDP listen port,
			  sampling rate etc.) on the command line;
**Mind the new command line syntax when upgrading!**
	- hierarchical RRD structure for more efficient storage
			  (one directory per low byte of AS number);
**Use `tools/migraterrdfiles.pl` to move your RRD files when upgrading!**
	- ...-asstatd.pl now re-reads known links file upon SIGHUP
*	Added contrib/generate-asinfo.py script to generate AS list from WHOIS
        data (contributed by Thomas Mangin <thomas.mangin@exa-networks.co.uk>).
*	Moved site-specific parameters of www frontend to config.inc.
*	New flag images from famfamfam.com.
*	Updated asinfo.txt.

## v1.2	

*	Support for sFlow (through sflow-asstatd.pl); fix for link names
		with upper-case characters
*	Allow inbound/outbound in graphs to be swapped (via option
		in www/config.inc)

## v1.1	
	
*	Fix for a potential race condition surrounding $childrunning
		(reported by Yann Gauteron; experienced on a Linux system)

## v1		
* Initial release
