package Uttu::Resource::dbi;

use ResourcePool::Factory::DBI;
use ResourcePool;

our %non_dbi_option = map { $_ => 1 } qw(weight suspendtimeout max maxtry sleeponfail);

sub parse {
    my($class, $prefix, $xp, $node) = @_;

    my %options;
    my %attr;
    my $t;

    foreach my $o (qw(
        datasource
        username
        password
    )) {
        next unless '' ne ($t = $xp -> findvalue('@'.lc $o, $node));
        $options{$o} = "".$t;
    }

    my %lb_options;
    $lb_options{Weight} = "".$xp -> findvalue('@weight', $node);
    $lb_options{SuspendTimeout} = "".$xp -> findvalue('@suspendtimeout', $node) || 5;
    my %rp_options;
    foreach my $o (qw(
        Max
        MaxTry
        SleepOnFail
    )) {
        next unless '' ne ($t = $xp -> findvalue('@'.lc $o, $node));
        $rp_options{$o} = "".$t;
    }

    # need all other attributes for %attr
    my $attributes = $xp -> findnodes('@*', $node);
    foreach my $a ($attributes -> get_nodelist) {
        my $ln = $a -> getLocalName;
        next if exists($options{$ln}) || $non_dbi_option{$ln};
        $attr{$a -> getLocalName} = "".$a -> getNodeValue;
    }

    my $inst = ResourcePool::Factory::DBI->new(@options{qw(datasource username password)}, \%attr);

    $inst = ResourcePool -> new($inst, %rp_options);

    if(wantarray) {
        return($inst, %lb_options);
    }
    else {
        return $inst;
    }
}

1;
