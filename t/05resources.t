use Uttu;

BEGIN {
    eval {
        require Apache::Test;
        Apache::Test -> import(qw(plan have ok skip));
        require Apache::TestRequest;
        Apache::TestRequest -> import(qw(GET));
    };

    if($@) {
        warn "$@\n";
        print "1..0\n";
        exit 0;
    }

    eval {
        require XML::XPath;
        require XML::XPath::Parser;
        require Uttu::Resource;
        require Uttu::Resource::resources;
        require Uttu::Resource::pool;
    };

    if($@) {
        warn "$@\n";
        print "1..0\n";
        exit 0;
    }
}

our @tests = (
    q{
<resources id="test">
</resources>
     },
    q{
<resources id="test">
  <pool id="pool">
  </pool>
</resources>
    },
);

eval { require Uttu::Resource::ldap; };

warn "$@\n" if $@;

unless($@) {
    push @tests, q{
<resources id="test">
  <pool id="ldap">
    <ldap host="localhost"/>
  </pool>
</resources>
};

    push @tests, sub {
my $u = bless { } => 'Uttu';
Uttu::Resource -> parse($u, \'<resources id="test"><pool id="ldap"><ldap host="localhost"/></pool></resources>');
my $ldap = $u -> resource('ldap');
return UNIVERSAL::isa($ldap, 'ResourcePool::LoadBalancer');
};

}

eval { require Uttu::Resource::dbi; };

warn "$@\n" if $@;

unless($@) {
    push @tests, q{
<resources id="test">
  <pool id="dbi">
    <dbi />
  </pool>
</resources>
};

    push @tests, sub {
my $u = bless { } => 'Uttu';
Uttu::Resource -> parse($u, \'<resources id="test"><pool id="dbi"><dbi/></pool></resources>');
my $dbi = $u -> resource('dbi');
return UNIVERSAL::isa($dbi, 'ResourcePool::LoadBalancer');
};

}


plan tests => scalar(@tests);

# read in sample resources string


foreach my $t (@tests) {
    if(UNIVERSAL::isa($t, 'CODE')) {
        eval { $t -> (); };
        warn "$@\n" if $@;
        ok !$@;
    }
    else {
        eval { Uttu::Resource -> parse({ }, \$t); };
        warn "$@\n" if $@;
        ok !$@;
    }
}

exit 0;
