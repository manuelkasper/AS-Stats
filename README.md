AS-Stats v1.6 (2014-09-12)
==========================

A simple tool to generate per-AS traffic graphs from NetFlow/sFlow records  
by Manuel Kasper <mk@neon1.net> for Monzoon Networks AG


Update 2017-02-15
-----------------
I currently don't have time to maintain AS-Stats. There have been some (merged) contributions since the last release, so you may want to download the latest repository version instead of the v1.6 release. Also, Nicolas Debrigode has released a more modern Web UI for AS-Stats: https://github.com/nidebr/as-stats-gui


How it works
------------

A Perl script (asstatd.pl) collects NetFlow v8/v9 AS aggregation records
or sFlow v5 samples from one or more routers. It caches them for about a
minute (to prevent excessive writes to RRD files), identifies the link that
each record refers to (by means of the SNMP in/out interface index), maps it
to a corresponding "known link" and RRD data source, and then runs RRDtool. To
avoid losing new records while the RRD files are updated, the update task is
run in a separate process.

For each AS, a separate RRD file is created as needed. It contains two data
sources for each link - one for inbound and one for outbound traffic.
In generated per-AS traffic graphs, inbound traffic is shown as positive,
while outbound traffic is shown as negative values.

Another Perl script, rrd-extractstats.pl, is meant to run about once per hour.
It sums up per-AS and link traffic during the last 24 hours, sorts the ASes
by total traffic (descending) and writes the results to a text file. This
is then used to display the "top N AS" and other stats by the provided PHP
scripts.


Prerequisites
-------------

- Perl 5.10 or newer
- RRDtool 1.3 or newer (with Perl "RRDs" library)
- File::Find::Rule module (CPAN)
- if using sFlow: the Net::sFlow module (CPAN)
- web server with PHP 5
- php-sqlite3
- libdbd-sqlite3-perl
- one or more routers than can generate NetFlow v8/v9 AS aggregation records
  or sFlow samples

Considerations
-------------

Thoughts on a location for RRD files:
RRD files are small in size, but there are a lot of them. You will see a performance gain on a filesystem like XFS over EXT3/4. Consider what filesystem you put the RRD files on if performance is a factor for your needs.


Installation
------------
- Copy the perl scripts asstatd.pl and rrd-extractstats.pl to the
  machine that will collect NetFlow/sFlow records

- Create a "known links" file with the following information about each
  link that you want to appear in your AS stats:
  	
  	- IP address of router (= source IP of NetFlow datagrams)
  	- SNMP interface index of interface (use "show snmp mib ifmib ifindex"
  	  to find out)
  	- a short "tag" (12 chars max., a-z A-Z 0-9 _ only) that will be used
  	  internally (e.g. for RRD DS names)
  	- a human-readable description (will appear in the generated graphs)
  	- a color code for the graphs (HTML style, 6 hex digits)
  	- the sampling rate (or 1 if you're not using sampling on the router)
  
  See the example file provided (knownlinks) for the format.  
  __Important: you must use tabs, not spaces, to separate fields!__

- Create a directory to hold per-AS RRD files. For each AS, about 128 KB of
  storage are required, and there could be (in theory) up to 64511 ASes.
  AS-Stats automatically creates 256 subdirectories in this directory for
  more efficient storage of RRD files (one directory per lower byte of
  AS number, in hex).

- Start asstatd.pl in the background (or, better yet, write a
  startup script for your operating system to automatically start
  asstatd.pl on boot):
  
  	`nohup asstatd.pl -r /path/to/rrd/dir -k /path/to/knownlinks &`

  By default, asstatd.pl will listen on port 9000 (UDP) for NetFlow
  datagrams, and on port 6343 (UDP) for sFlow datagrams. Use the -p/-P options
  if you want to change that (use 0 as the port number to disable either protocol).
  For sFlow, you also need to specify your own AS number with the -a
  option for accurate classification of inbound and outbound traffic.
  It's a good idea to make sure only UDP datagrams from your trusted routers
  will reach the machine running asstatd.pl (firewall etc.).

- NetFlow only:
  Have your router(s) send NetFlow v8 or v9 AS aggregation records to
  your machine. This is typically done with commands like the following
  (Cisco IOS):

		ip flow-cache timeout active 5

		int Gi0/x.y
		  ip flow ingress

		ip flow-export source <source interface>
		ip flow-export version 5 origin-as
		ip flow-aggregation cache as
		 cache timeout active 5
		 cache entries 16384
		 export destination <IP address of server running AS stats> 9000
		 enabled

  Adjust the number of cache entries if necessary (i.e. if you get messages
  like "Netflow as aggregation cache is almost full" in the logs).

  Note that the version has to be specified as 5, even though the AS
  aggregation records will actually be v8. Also, setting the global flow
  cache timeout to 5 minutes is necessary to get "smooth" traffic graphs
  (default is 30 minutes), as a flow is only counted when it expires from
  the cache. Decreasing the flow-cache timeout may result in a slight
  increase in CPU usage (and NetFlow AS aggregation takes its fair share of
  CPU as well, of course).

  Routers with MLS (Multi-Layer Switching, e.g. Cisco 7600 series) require
  additional commands like the following in order to enable NetFlow
  processing/aggregation for packets processed in hardware:

		mls aging fast time 4 threshold 2
		mls aging long 128
		mls aging normal 64
		mls flow ip interface-full

  For IOS XR, the configuration looks as follows:

		flow exporter-map FEM
		 version v9
		 !
		 transport udp 9000
		 source <source interface>
		 destination <IP address of server running AS stats> vrf default

		flow monitor-map IPV4-FMM
		 record ipv4
		 exporter FEM
		 cache entries 16384
		 cache timeout active 300
		!
		flow monitor-map IPV6-FMM
		 record ipv6
		 exporter FEM
		 cache entries 16384
		 cache timeout active 300
		!

		sampler-map SM
		 random 1 out-of 10000

		router bgp 100
		  address-family ipv4 unicast
		   bgp attribute-download
		  address-family ipv6 unicast
		   bgp attribute-download

  For JunOS, the configuration looks as follows:

		forwarding-options {
			sampling {
				input {
					rate 2048;
					max-packets-per-second 4096;
				}
				family inet {
					output {
						flow-active-timeout 60;
						flow-server x.x.x.x {
							port 9000;
							autonomous-system-type origin;
							aggregation {
								autonomous-system;
							}
							version 8;
						}
					}
				}
			}
		}

  JunOS IPFIX configuration:

		chassis {
			tfeb {
				slot 0 {
					sampling-instance as-stats;
				}
			}
		}
		interfaces {
			ge-1/0/0 {
				unit 0 {
					family inet {
						sampling {
							input;
							output;
						}
					}
				}
			}
		}
		forwarding-options {
			sampling {
				instance {
					as-stats {
						input {
							rate 2048;
						}
						family inet {
							output {
								flow-server 192.0.2.10 {
									port 9000;
									autonomous-system-type origin;
									no-local-dump;
									source-address 192.0.2.1;
									version-ipfix {
										template {
											ipv4;
										}
									}
								}
								inline-jflow {
									source-address 192.0.2.1;
								}
							}
						}
					}
				}
			}
		}
		services {
			flow-monitoring {
				version-ipfix {
					template ipv4 {
						flow-active-timeout 60;
						flow-inactive-timeout 60;
						template-refresh-rate {
							packets 1000;
							seconds 10;
						}
						option-refresh-rate {
							packets 1000;
							seconds 10;
						}
						ipv4-template;
					}
				}
			}
		}


- sFlow only:
  Have your router(s) send sFlow samples to your machine. Your routers
  may need a software upgrade to make them include AS path information for
  both inbound and outbound packets (this is a good thing to check if
  your graphs only show traffic on one direction).

- Wait 1-2 minutes. You should then see new RRD files popping up in the
  directory that you defined/created earlier on. If not, make sure that
  asstatd.pl is running, not spewing out any error messages, and that
  the NetFlow/sFlow datagrams are actually reaching your machine (tcpdump...).

- Add a cronjob to run the following command every hour:

	`rrd-extractstats.pl /path/to/rrd/dir /path/to/knownlinks /path/to/asstats_day.txt`

  That script will go through all RRD files and collect per-link summary
  stats for each AS in the last 24 hours, sort them by total traffic (descending), and write them
  to a text file. The "top N AS" page uses this to determine which ASes to
  show.
  
  If you want an additional interval for the top N AS (e.g. top N AS in the
  last 30 days), add another cronjob with the desired interval in hours as
  the last argument (and another output file of course). Example:
  
	`rrd-extractstats.pl /path/to/rrd/dir /path/to/knownlinks /path/to/asstats_month.txt 720`

  Add the interval to the top_intervals array in config.inc (see the example) so that
  it will appear in the web interface.

  Repeat for further intervals if necessary.
  
  It is not recommended to run more than one rrd-extractstats.pl cronjobs at the same
  time for disk I/O reasons – add some variation in the start minute setting
  so that the jobs can run separately.
  For longer intervals than one day, the cronjob frequency can be adjusted as
  well (e.g. for monthly output, it is sufficient to run the cronjob once a day).
  
- Copy the contents of the "www" directory to somewhere within your web
  server's document root and change file paths in config.inc as necessary.

- Make the directory "asset" within www writable by the web server (this
  is used to cache AS-SETs and avoid having to query whois for every request).

- Wait a few hours for data to accumulate. :)

- Access the provided PHP scripts via your web server and marvel at the
  (hopefully) beautiful graphs.


Adding a new link
-----------------
Adding a new link involves adding two new data sources to all RRD files.
This is a bit of a PITA since RRDtool itself doesn't provide a command to do
that. A simple (but slow) Perl script that is meant to be used with RRDtool's
XML dump/restore feature is provided (add_ds_proc.pl, add_ds.sh). Note that
asstatd.pl should be stopped while modifying RRD files, to avoid
breaking them with concurrent modifications.

Before you follow the instructions below:

- Make sure you stop asstatd.pl.
- Take a backup of your whole RRD folder. That is the only way to roll back from this process.
- This will only add one data source at a time. If you are adding multiple new links, you will need to follow the instructions below once for each new link you add.

Instructions for adding a new link:

1.	Edit your known links file and add your new link (see above for syntax)  
	Example:

		10.1.17.10      33      router-newlink  Friendlyname     1F78B4  1

2.	Edit the script tools/add_ds_proc.pl

	Change this line:  
	`my $newlinkname = 'newlink';`

	To have the same ID in your knownlinks file:  
	`my $newlinkname = 'router-newlink';`

3.	Edit the script tools/add_ds.sh

	Make sure the path to add_ds_proc.pl is correct.

4.	cd into the rrd folder:  
	`cd rrd`

5.	Run the script  
	`/path/to/add_ds.sh`

	This will take a while (around 20 minutes), so go get a cup of coffee.

6.	Start the collector back up again, and watch for new graphs!

You can also read the RRD files with the command `rrdtool info file.rrd`, which will show you the data sourced in each one.


Changing the RRAs
-----------------
By default, the created RRDs keep data as follows:

	* 48 hours at 5 minute resolution
	* 1 week at 1 hour resolution
	* 1 month at 4 hour resolution
	* 1 year at 1 day resolution

If you want to change that, modify the getrrdfile() function in
asstatd.pl and delete any old RRD files.


Support
-------
A mailing list is available at https://groups.google.com/d/forum/as-stats-users. Please do not send requests for help/support directly to the author.


Donations
---------
- Immobilien Scout GmbH sponsored the work to add support for multiple configurable stats intervals


To do
-----

- rrd-extractstats.pl uses a lot of memory and could probably use some
  optimization.
- Consider adding a command line parameter to add_ds_proc.pl and add_ds.sh for ease of adding new links.
