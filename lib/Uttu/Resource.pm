package Uttu::Resource;

use XML::XPath;
use XML::XPath::Parser;
use Uttu::Resource::resources;

sub parse {
    my($class, $u, $file) = @_;

    my $xp;
    if(ref $file) {
        if(UNIVERSAL::isa($file, 'SCALAR')) {
            $xp = XML::XPath -> new(xml => $$file);
        }
        else {
            die "Not sure what to do with this.";
        }
    }
    else {
        $xp = XML::XPath -> new(filename => $file);
    }
    my $resources = $xp -> find('/resources');

    $u -> {resource_ids} = [];

    foreach my $node ($resources -> get_nodelist) {
        my $id = $xp -> findvalue('@id', $node);
        next unless $id ne '';
        push @{$u -> {resource_ids}}, $id;
        Uttu::Resource::resources -> parse(undef, $xp, $node);
    }
}

1;

__END__

=head1 NAME

Uttu::Resource - parses resource configuration files

=head1 SYNOPSIS

In code:

 Uttu::Resource -> parse(Uttu -> retrieve, $filename);

In Uttu configuration file:

 [global]
 resources conf/resources.xml

In resource file:

 <resources id="site">
   <!-- resource definitions -->
 </resources>

Retrieve resource pool and get handle:

 my $pool = $u -> resource('ldap');
 my $ldap = $pool -> get();
 # do stuff with $ldap (Net::LDAP object)
 $pool -> free($ldap);

=head1 DESCRIPTION

=head1 SEE ALSO

The documentation for each element:
L<ldap|Uttu::Resource::ldap>,
L<pool|Uttu::Resource::pool>,
L<resources|Uttu::Resource::resources>.

=head1 AUTHOR

James Smith, <jsmith@cpan.org>

=head1 COPYRIGHT
