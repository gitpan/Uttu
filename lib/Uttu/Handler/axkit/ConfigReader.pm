package Uttu::Handler::axkit::ConfigReader;

use Apache::AxKit::ConfigReader;
use Uttu::Handler::axkit::ContentProvider;

our @ISA = qw(Apache::AxKit::ConfigReader);

our %config_map = qw(
    StyleMap        axkit_map_style
    CacheDir        axkit_cache_dir
    ContentProvider axkit_content_provider
    DependencyChecks axkit_dependency_checks
    StyleProvider   axkit_style_provider
    Style           axkit_preferred_style
    Media           axkit_preferred_media
    CacheModule     axkit_cache_provider
    DebugLevel      axkit_debug_level
    DebugTime       axkit_debug_time
    StackTrace      axkit_debug_stack_trace
    TraceIntermediate axkit_debug_trace_intermediate
    LogDeclines     axkit_log_declines
    HandleDirs      axkit_handle_dirs
    IgnoreStylePI   axkit_ignore_style_pi
    TranslateOutput axkit_translate_output
    OutputCharset   axkit_output_charset
    ErrorStylesheet axkit_error_stylesheet
    GzipOutput      axkit_gzip_output
    XSPTaglibs      axkit_xsp_taglib
    OutputTransformers axkit_output_transformer
    Plugins         axkit_plugin
);

# axkit_process_* -> hash
# axkit_map_style -> hash
# axkit_xsp_taglib -> hash ?

#sub new {
#    my $class = shift;
#    my  $self = $class -> SUPER::new(@_);
#
#    warn "new $self\n";
#
#    bless $self => __PACKAGE__;
#}

#*new = \&Apache::AxKit::ConfigReader::new;

sub get_config {
    my($self) = shift;
    # we want to map between the AppConfig stuff and what AxKit expects

#    warn "$self -> get_config\n";

    my $u = Uttu -> retrieve or return;

    my $config;

    if($u -> {handler} && defined($config = $u -> {handler} -> axkitconfig)) {
        delete $config -> {apache};
        @{$self}{keys %$config} = values %$config;
        return $self;
    }

    #return $u -> {handler} -> axkitconfig
    #    if $u -> {handler} && defined $u -> {handler} -> axkitconfig;

    my $c = $u -> config or return;

    my %cfg;

    while(my($k, $v) = each %config_map) {
        $cfg{$k} = $c -> get($v);
    }

    $cfg{NoCache} = !$c -> get('axkit_cache_dir'); # boolean

    $cfg{ConfigProvider} ||= 'Uttu::Handler::axkit::ContentProvider'
        if $c -> get('axkit_secondary_handler');

    $cfg{StyleProvider} ||= 'Apache::AxKit::Provider::File';

    while(my($s, $c) = each %{$cfg{StyleMap}||{}}) {
        eval "require $c";
        warn "Unable to load $c: $@\n" if $@;
        delete $cfg{StyleMap}{$s} if $@;
    }

    my $doc_root = [ ];
    my %pathnames = ( );
    if($c -> axkit_document_root) {
        my $paths = [];
        my $can_get_by_without_a_name = scalar(@{$c -> axkit_document_root || []}) == 1;
        if($can_get_by_without_a_name && $c->axkit_document_root->[0] !~ /=/) {
            $doc_root = [ [ 'local', Uttu::Tools::server_root_relative($c->axkit_document_root->[0]) ] ];
            $pathnames{local} = ( );
        } else {
            foreach my $p (@{$c -> axkit_document_root || []}) {
                my($n, $d) = split(/\s*=>?\s*/, $p, 2);
                push @{$paths}, [ $n, Uttu::Tools::server_root_relative($d) ];
                $pathnames{$n} = ( );
            }
            $doc_root = $paths;
        }
    }
    if(defined $c -> global_framework) {
        push @{$doc_root},
             [ 'function_sets', $Uttu::Config::PREFIX . "/functionsets/" . $c -> global_framework . "/" ]
                 unless exists $pathnames{function_sets};
        unless(exists $pathnames{framework}) {
            my $p = $INC{'Uttu/Framework/' . $c -> global_framework . ".pm"};
            $p =~ s{lib/Uttu/Framework/.*$}{};
            $p ||= $Uttu::Config::PREFIX . "/framework/" . $c -> global_framework;
            push @{$doc_root}, [ 'framework', $p ];
        }
    }

    $cfg{_DocumentRoots} = $doc_root;

    my %processors = $c -> varlist("^axkit_process_");
    $cfg{Processors} = { };
    while(my($k, $v) = each %processors) {
        $k =~ s{^axkit_process_}{};
        # need to take $v to @directive
        my %directives;
        next unless $v;
        foreach my $d (@{$v || []}) {
            my(@directive);
            my($style, $v) = split(/(?:\s*=>\s*|\s+)/, $d, 2);
            push @directive, $1 ? $1 : $2
                while $v =~ m{\G
                              \s*
                              (?:
                                 (?:
                                    (?!")
                                    (
                                       (?:[^[:space:]]+|\\\s)+
                                    )
                                 )
                                 |
                                 (?:
                                    (?=")
                                    "
                                    (
                                       (?:[^"]+|\\")+
                                    )
                                    "
                                 )
                              )
                              \s*
                             }gx;

            s{\\(["[:space:]])}{$1}g for @directive; # unescape escaped characters

# $k -> media
# $style -> style
# type: NORMAL, DocType, DTD, Root, URI
# NORMAL mime/type href
# DocType mime/type href doctype
# DTD mime/type href dtd
# Root mime/type href root_element
# URI mime/type href uri
            
            push @{$directives{$style}||=[]}, \@directive;
        }
        $cfg{Processors} -> {$k} = \%directives if scalar keys %directives;
    }

    delete $cfg{apache};

    $self -> {cfg} = \%cfg;
}

sub _DocumentRoots {
    my $self = shift;

    return $self -> {cfg} -> {_DocumentRoots} if defined $self -> {cfg} -> {_DocumentRoots};

    return [];
}
