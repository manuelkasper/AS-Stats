#!/bin/sh

A=`ls -1`

for i in $A ; do
	echo ""
	echo "dir: $i"
	echo ""
	cd $i

	for f in *.rrd; do
		echo "file: $f"
		mv $f $f.old
		rrdtool dump $f.old | /path/to/add_ds_proc.pl | rrdtool restore - $f.new
		mv $f.new $f
	done

	cd ../
done
