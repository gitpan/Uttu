package Uttu::Handler::axkit::ContentProvider;

use base qw(Apache::AxKit::Provider::File);

use Apache::AxKit::Exception;
use Apache::URI;

sub init {
    my($self, %p) = @_;

    # these three are empty when requesting the content associated 
    # with Apache->request->filename
    warn "$self : $p{file}; $p{uri}; $p{key}\n";
    unless($p{file} || $p{uri} || $p{key}) {
        my $c = $self -> get_strref;  # also loads content into cache

        if($c) {
            my $ret = $self -> SUPER::init(%p);
            $self -> {is_dir} = 0;
            $self -> {file_exists} = 1;
            $self -> {mtime} = time;
            $self -> {_secondary} = 1;
            return $ret;
        }
    }
    return $self -> SUPER::init(%p);
}

sub process {
    my $self = shift;

    if($self -> {_secondary}) {
        return 1;
    }

    return $self -> SUPER::process;
}

sub get_fh {
    throw Apache::AxKit::Exception::IO(
        -text => "Can't get fh for (Uttu::Handler::axkit) secondary handler content"
    );
}

sub get_strref {
    my $self = shift;

    return $self -> {_content} if defined $self -> {_content};

    my $u = Uttu -> retrieve or return \q<>;

    eval {
        local($SIG{__DIE__});

        $self -> {_content} = 
            $u -> {handler} 
               -> secondary_handler 
               -> shandle_request($u, Apache->request)
        ;
    };
    warn "$@\n" if $@;

    return $$self{_content};
}

1;
