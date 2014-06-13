#!/bin/sh

## YOU NEED TO EDIT add_ds_proc.pl BEFORE YOU RUN THIS!!
## You need to edit the line:
## my $newlinkname = 'NEWIDFROMKNOWNLINKSFILE';
## to reflect the ID in the known links file

A=`ls -1`

for i in $A ; do
	echo ""
	echo "dir: $i"
	echo ""
	cd $i

	for f in *.rrd; do
		echo "file: $f"
		mv $f $f.old
		rrdtool dump $f.old | /data/as-stats/tools/add_ds_proc.pl | rrdtool restore - $f.new
		mv $f.new $f
		rm -f $f.old
	done

	cd ../
done
