#!perl

use strict;
use warnings FATAL => 'all';

use FindBin;
use lib map "$FindBin::Bin/$_",
        qw(../Apache-Test/lib ../lib ../../lib);


use Apache::TestSmokePerl ();
Apache::TestSmokePerl->new(@ARGV)->run;
