package Uttu::Resource::ldap;

use ResourcePool::Factory::Net::LDAP;
use ResourcePool;

sub parse {
    my($class, $prefix, $xp, $node) = @_;

    my %new_options;
    my %bind_options;
    my $t;

    foreach my $o (qw(
        port
        timeout
        debug
        async
        onerror
        version
    )) {
        next unless '' ne ($t = $xp -> findvalue('@'.lc $o, $node));
        $new_options{$o} = $t;
    }

    foreach my $o (qw(
        password
    )) {
        next unless '' ne ($t = $xp -> findvalue('@'.lc $o, $node));
        $bind_options{$o} = $t;
    }

    my $host = $xp -> findvalue('@host', $node);

    my $inst = ResourcePool::Factory::Net::LDAP->new($host, %new_options);

    my $dn = $xp -> findvalue('@dn', $node);
    $inst -> bind($dn, %bind_options);

    my %lb_options;
    $lb_options{Weight} = $xp -> findvalue('@weight', $node);
    $lb_options{SuspendTimeout} = $xp -> findvalue('@suspendtimeout', $node) || 5;
    my %rp_options;
    foreach my $o (qw(
        Max
        MaxTry
        SleepOnFail
    )) {
        next unless '' ne ($t = $xp -> findvalue('@'.lc $o, $node));
        $rp_options{$o} = $t;
    }

    $inst = ResourcePool -> new($inst, %rp_options);

    if(wantarray) {
        return($inst, %lb_options);
    }
    else {
        return $inst;
    }

}

1;
