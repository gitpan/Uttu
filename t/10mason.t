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
        require HTML::Mason;
    };

    if($@ || $HTML::Mason::VERSION < 1.04) {
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
# actual file should be t/pages/mason/sets/page1.html
#
if($have_csv) {
    my $res = GET "/mason/test1.html";
    ok $res->content eq '[This is a Mason Page]
';
} else {
    skip 1, "No DBD::CSV";
}

exit 0;
