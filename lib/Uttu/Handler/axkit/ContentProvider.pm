package Uttu::Handler::axkit::ContentProvider;

use base qw(Apache::AxKit::Provider::File);

use Apache::AxKit::Exception;

sub get_fh {
    throw Apache::AxKit::Exception::IO(
        -text => "Can't get fh for (Uttu::Handler::axkit) secondary handler content"
    );
}

sub get_strref {
    my $self = shift;

    return $self -> {_content} if defined $self -> {_content};

    my $u = Uttu -> retrieve or return \q<>;

    
        $self -> {_content} = 
            $u -> {handler} 
               -> secondary_handler 
               -> shandle_request($u, Apache->request)
    ;
    return $$self{_content};
}

1;
