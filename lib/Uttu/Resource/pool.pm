package Uttu::Resource::pool;

use ResourcePool::LoadBalancer;

sub parse {
    my($class, $prefix, $xp, $node) = @_;

    my %options;

    $options{Policy} = $xp -> findvalue('@policy', $node) || 'LeastUsage';
    $options{MaxTry} = $xp -> findvalue('@maxtry', $node);
    $options{MaxTry} = 6 unless defined $options{MaxTry} && $options{MaxTry} ne '';
    $options{SleepOnFail} = [ split(/\s*,\s*/, $xp -> findvalue('@SleepOnFail', $node)) ];
    delete $options{SleepOnFail} unless @{$options{SleepOnFail}};

    my $id = $xp -> findvalue('@id', $node);
    my $xref = $xp -> findvalue('@xref', $node);
    my $loadbalancer;
    if($id) {
        $id = "${prefix}.${id}" if defined $prefix;

        $loadbalancer = ResourcePool::LoadBalancer->new($id, %options);
    }
    elsif($xref) {
        $loadbalancer = ResourcePool::LoadBalancer->new($xref);
    }

    return unless $loadbalancer;

    my $resources = $xp -> find('./*', $node);
    foreach my $resource ($resources -> get_nodelist) {
        next unless $resource -> getNodeType == XML::XPath::Node::ELEMENT_NODE;
        my $class = "Uttu::Resource::" . $resource -> getLocalName;
        eval { eval "require $class;"; };
        warn "Unable to process <", $resource -> getLocalName, "/> element: $@\n" if $@;
        next if $@;
        my($inst, %options) = $class -> parse($id, $xp, $resource);
        next unless $inst;

        $loadbalancer -> add_pool($inst, %options);
    }

    %options = ( );
    $options{Weight} = $xp -> findvalue('@weight', $node);
    $options{SuspendTimeout} = $xp -> findvalue('@suspendtimeout', $node) || 5;

    if(wantarray) {
        return($loadbalancer, %options);
    }
    else {
        return $loadbalancer;
    }
}

1;

__END__

=head1 NAME

Uttu::Resource::pool - <pool/> handler for resource definitions

=head1 SYNOPSIS

In resource definition file:

 <resources id="gst">
   <pool id="ldap"
         policy="RoundRobin"
         maxtry="4"
         sleeponfail="1, 2, 3, 4"
         weight="1"
         suspendtimeout="5"
   >
     <!-- resources within pool -->
   </pool>
 </resources>

or

 <resources id="gst">
   <pool xref="gst.ldap"/>
 </resources>

In parser:

 my $xp = XML::XPath(filename => 'resources.xml');
 my $prefix = $xp -> findvalue('/resources/@id');
 my $pools = $xp -> find('/resources/pool');
 foreach my $node ($pools -> get_nodelist) {
     my $loadbalancer = 
         Uttu::Resource::pool -> parse($prefix, $xp, $node);
   # do something with ResourcePool::LoadBalancer object
 }

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 id

This required attribute identifies the resource pool.

=head2 maxtry

The maximum number of retries.

=head2 policy

=head2 sleeponfail

=head2 suspendtimeout

=head2 weight

=head2 xref

This refers to a resource pool defined elsewhere.  The reference 
string is the fully qualified id of the pool, beginning with the 
C<id> attribute of the <resources/> element.

Only C<suspendtimeout> and C<weight> are used in conjunction with 
C<xref>.

=head1 BUGS

Please report bugs to either the request tracker for CPAN 
(L<http://rt.cpan.org/|http://rt.cpan.org/>) or on the SourceForge project
(L<http://sourceforge.net/projects/gestinanna/|http://sourceforge.net/projects/gestinanna/>).

=head1 AUTHOR

James Smith, <jsmith@cpan.org>

=head1 COPYRIGHT
