#!/bin/sh

for f in *.rrd; do
	echo "file: $f"
	mv $f $f.old
	rrdtool dump $f.old | /path/to/add_ds_proc.pl | rrdtool restore - $f.new
	mv $f.new $f
done
