package Uttu::Tools;

use Exporter;
use AppConfig qw- :argcount -;

use vars qw: @EXPORT_OK $VERSION @ISA :;

$VERSION = "0.01";

@ISA = qw: Exporter :;

@EXPORT_OK = qw: call_other define_db define_cache :;

sub call_other {
    my($class_regex, $method, @args) = @_;

    foreach my $m (grep { m{$class_regex} } keys %INC) {
        my $c = $m;
        $c =~ s{/}{::}g;
        $c =~ s{.pm$}{};
        $c =~ s{^::}{};
        eval { $c -> $method(@args); };
        if($@) {
            delete $INC{$m};
            eval qq{require $c};
            eval { $c -> $method(@args); };
        }
    }
}

sub _set_from_file {
    my($self, $variable, $value) = @_;
    my $file = Apache -> server_root_relative($value);
    open my $fh, "<", $file or warn "Unable to read $file\n";
    my $p = <$fh>;
    close $fh;
    return unless defined $p;
    chomp($p);
    $variable =~ s{_file$}{};
    $self -> set($variable, $p);
    return 1;
}

sub define_db {
    my($prefix) = @_;

    return (
        $prefix."_database", {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        $prefix."_username", {
        },
        $prefix."_password_file", {
            ACTION => \&_set_from_file,
        },
        $prefix."_password", {
        },
        $prefix."_option", {
            ARGCOUNT => ARGCOUNT_HASH,
        },
        $prefix."_driver", {
            VALIDATE => sub {
                eval "require DBD::$_[1]";
            },
        },
    
        $prefix."_const_database", {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        $prefix."_const_username", {
        },
        $prefix."_const_password_file", {
            ACTION => \&_set_from_file,
        },
        $prefix."_const_password", {
        },
        $prefix."_const_option", {
            ARGCOUNT => ARGCOUNT_HASH,
        },
        $prefix."_const_driver",  {
            VALIDATE => sub {
                eval "require DBD::$_[1]";
            },
        },
    );
}

sub _convert_bytes {
    my($self, $variable, $value) = @_;
    return 1 if $doing_config;
    $doing_config = 1;
    $value =~ m{^(\S+)\s*(\S)?$};
    my $s = lc $2;
    $value = eval "$1";
    for($s) {
      /g/ && ($value *= 1024*1024*1024);
      /m/ && ($value *= 1024*1024);
      /k/ && ($value *= 1024);
    }

    $self -> set($variable, $value);
    $doing_config = 0;
    return 1;
}

sub define_cache {
    my($prefix) = @_;

    return (
	$prefix."_namespace", {
	    VALIDATE => q:^\S+$:,
        },
	$prefix."_expiration", {
	    VALIDATE => q:^\d+(m(in(untes?)?)?|s(ec(onds?)?)?|h(ours?)?|w(eeks?)?|M|months?|y(ears?)?|n(ow|ever))$:,
        },
	$prefix."_auto_purge_interval", {
	    VALIDATE => q:^\d+(m(in(untes?)?)?|s(ec(onds?)?)?|h(ours?)?|w(eeks?)?|M|months?|y(ears?)?|n(ow|ever))$:,
        },
	$prefix."_size_limit", {
            VALIDATE => q:^\d+([kmgKMG]?)$:,
            ACTION => \&_convert_bytes,
        },
	$prefix."_sharedmemory", {
	    ARGCOUNT => ARGCOUNT_NONE,
	    VALIDATE => sub { eval { require Cache::SizeAwareSharedMemoryCache }; return !$@; },
        },
    );
}

1;
