package Uttu::Handlers::axkit::ConfigReader;

use base qw(Apache::AxKit::ConfigReader);

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

sub get_config {
    my($self) = shift;
    # we want to map between the AppConfig stuff and what AxKit expects

    my $u = Uttu -> retrieve or return;

    my $c = $u -> config or return;

    my %cfg;

    while(my($k, $v) = each %config_map) {
        $cfg{$k} = $c -> get($v);
    }

    $cfg{NoCache} = !$c -> get('axkit_cache'); # boolean

    $cfg{ConfigProvider} ||= 'Uttu::Handlers::axkit::ContentProvider'
        if $c -> get('axkit_secondary_handler');

    while(my($s, $c) = each %{$cfg{StyleMap}||{}}) {
        eval "require $c";
        delete $cfg{StyleMap}{$s} if $@;
    }

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
            
            $directives{$style} = \@directive;
        }
        $cfg{Processors} -> {$k} = \%directive if scalar keys %directives;
    }

    $self -> {cfg} = \%cfg;
}

