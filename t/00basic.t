print "1..1\n";

# make sure it loads in a non-mod_perl environment

eval {
    require Uttu;
};

if($@) {
    print "not ok 1\n";
} else {
    print "ok 1\n";
}

exit 0;
