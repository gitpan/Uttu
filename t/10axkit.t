BEGIN {
    eval {
        require Apache::Test;
        Apache::Test -> import(qw(plan have ok skip));
        require Apache::TestRequest;
        Apache::TestRequest -> import(qw(GET));
    };

    if($@) {
        print "1..0\n";
        exit 0;
    }

    eval {
        require AxKit;
    };

    if($@ || $AxKit::VERSION < 1.6) {
        print "1..0\n";
        exit 0;
    }

    $have_csv = 0;
    eval {
        require DBD::CSV;
        $have_csv = 1;
    };
}

plan tests => 1, have 'LWP';

#
# tests if uri mapping is working and if we have a working
# HTML::Mason handler object
#
# actual file should be t/pages/axkit/sets/page1.xml
#
if($have_csv) {
    my $res = GET "/axkit/test1.xml";
#    warn "Content: [",$res->content,"]\n";
    ok $res->content eq q[<?xml version="1.0"?>

This is an AxKit Page!
  
];
} else {
   skip 1, "No DBD::CSV";
}

exit 0;

