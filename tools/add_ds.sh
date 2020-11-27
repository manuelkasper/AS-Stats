#!/bin/sh

## YOU NEED TO EDIT add_ds_proc.pl BEFORE YOU RUN THIS!!
## You need to edit the line:
## my $newlinkname = 'NEWIDFROMKNOWNLINKSFILE';
## to reflect the ID in the known links file

A=`find . -type f -name '*.rrd' | sed -r 's|/[^/]+$||' |sort |uniq`
W=`pwd`

for i in $A ; do
	cd $i

	for f in *.rrd; do
		echo "file: $i/$f"
		mv $f $f.old
		rrdtool dump $f.old | $W/add_ds_proc.pl | rrdtool restore - $f.new
		mv $f.new $f
		rm -f $f.old
	done

	cd ../
done
