#!/usr/bin/perl

use strict;

my $ds = 4;

# change the name(s) of the new data sources here
my $newlinkname = 'newlink';
my @dsnames = ($newlinkname.'_in', $newlinkname.'_out', $newlinkname.'_v6_in', $newlinkname.'_v6_out');

my $default_val = 'NaN';
my $type = 'ABSOLUTE';
my $heartbeat = '300';
my $rrdmin = 'NaN';
my $rrdmax = 'NaN';

my $cdp_prep_end = '</cdp_prep>';

my $row_end = '</row>';
my $name = '<name>';
my $name_end = '</name>';

my $field = '<v> ' . $default_val . ' </v>';

my $found_ds = 0;
my $num_sources = 0;
my $last;
my $fields = " ";
my $datasource;
my $x;

while (<STDIN>) {

  if (($_ =~ s/$row_end$/$fields$row_end/) && $found_ds) {
    # need to hit <ds> types first, if we don't, we're screwed
    print $_; 

  } elsif (/$cdp_prep_end/) {
    for (my $j = 0; $j < $ds; $j++) {
      print "\t\t\t<ds>\n" . 
            "\t\t\t<primary_value> 0.0000000000e+00 </primary_value>\n" .
            "\t\t\t<secondary_value> 0.0000000000e+00 </secondary_value>\n" .
            "\t\t\t<value> NaN </value>\n" .
            "\t\t\t<unknown_datapoints> 0 </unknown_datapoints>\n" .
            "\t\t\t</ds>\n";
    }
    print $_;

  } elsif (/$name_end$/) {
    ($datasource) = /$name (\w+)/;
    $found_ds++;
    print $_;

  } elsif (/Round Robin Archives/) {
    # print out additional datasource definitions

    ($num_sources) = ($datasource =~ /(\d+)/);
    
    for ($x = 0; $x < $ds; $x++) {

      $fields .= $field;
      
      print "\n\t<ds>\n";
      print "\t\t<name> " . $dsnames[$x] . " <\/name>\n";
      print "\t\t<type> $type <\/type>\n";
      print "\t\t<minimal_heartbeat> $heartbeat <\/minimal_heartbeat>\n";
      print "\t\t<min> $rrdmin <\/min>\n";
      print "\t\t<max> $rrdmax <\/max>\n\n";
      print "\t\t<!-- PDP Status-->\n";
      print "\t\t<last_ds> U <\/last_ds>\n";
      print "\t\t<value> NaN <\/value>\n";
      print "\t\t<unknown_sec> 0 <\/unknown_sec>\n"; 
      print "\t<\/ds>\n\n";

    }

    print $_;
  } else {
    print $_;
  }

  $last = $_;
}
