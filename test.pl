BEGIN
{ 
   use Test::More tests => 2;

   use lib qw(example);  # Be sure to include SampleConfig properly
   use_ok(CAM::App);
   use_ok(SampleConfig); # Just to make sure there aren't any syntax errors
}

use strict;

# TODO!!!
