package Uttu::Build;

use base qw(Module::Build);

BEGIN {
    eval {
        require Apache::Test;
        $Uttu::Build::HAVE_APACHE_TEST = 1;
    };
}

sub new {
    my($class, %p) = @_;

#
# module_name:
#   application_name -> Uttu::Framework::<framework>::<application>
#   framework_name -> Uttu::Framework::<framework>
#
# module_version:
#   module_version_from -> ./<framework>.pm | ./<application>.pm
#
# 
    if(!defined $p{module_name}) {
        if(defined $p{application_name}) {
            $p{module_name} = "Uttu::Framework::$p{framework_name}::$p{application_name}";
        elsif(defined $p{framework_name}) {
            $p{module_name} = "Uttu::Framework::$p{framework_name}";
        }
    }

    if( !defined($p{framework_name}) 
       && $p{module_name} =~ m{^Uttu::Framework::([^:]+)(::)?}) 
    {
        $p{framework_name} = $1;
    }

    if( !defined($p{application_name})
       && $p{module_name} =~ m{^Uttu::Framework::.*?::([^:]+)(::)?})
    {
        $p{application_name} = $1;
    }

    $p{module_version_from} ||= "./" 
                              . ($p{application_name} || $p{framework_name}) 
                              . ".pm"
        unless defined $p{module_version};

    return $class -> SUPER::new(%p);
}

1;

__END__

=head1 NAME

Uttu::Build - easy installation of frameworks and applications

=head1 SYNOPSIS

 use Uttu::Build;

=head1 DESCRIPTION

=head1 DIRECTORY LAYOUT

=head2 Framework

=head2 Application
