package Uttu::Resource::resources;

use ResourcePool::LoadBalancer;
use Uttu::Resource::pool;

sub parse {
    my($class, $prefix, $xp, $node) = @_;

    my %options;

    my $id = $xp -> findvalue('@id', $node);

    my $pools = $xp -> find('pool', $node);
    foreach my $pool ($pools -> get_nodelist) {
        Uttu::Resource::pool -> parse($id, $xp, $pool);
    }
}

1;

__END__

=head1 NAME

Uttu::Resource::resources - <resources/> handler for resource definitions

=head1 SYNOPSIS

In resource definition file:

 <resources id="gst">
   <pool id="ldap"
   >
     <!-- resources within pool -->
   </pool>
 </resources>

In parser:

 my $xp = XML::XPath(filename => 'resources.xml');
 my $resources = $xp -> find('/resources');
 foreach my $node ($resources -> get_nodelist) {
     Uttu::Resource::resources -> parse($prefix, $xp, $node);
 }

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 id

This required attribute identifies the resource pools within this 
resource definition file.

=head1 BUGS

Please report bugs to either the request tracker for CPAN 
(L<http://rt.cpan.org/|http://rt.cpan.org/>) or on the SourceForge project
(L<http://sourceforge.net/projects/gestinanna/|http://sourceforge.net/projects/gestinanna/>).

=head1 AUTHOR

James Smith, <jsmith@cpan.org>

=head1 COPYRIGHT
