package Uttu::Handler::axkit;

#
# comments in this file assume you have read the documentation (Uttu.pod)
#

use Apache::Constants qw: SERVER_ERROR OK :;
use AppConfig qw- :argcount -;
use Data::Dumper;
use AxKit;
use Uttu::Handler::axkit::ConfigReader;
use Uttu::Handler::axkit::ContentProvider;
use Apache::AxKit::Provider::File;
use strict;
use warnings;

use vars qw{ $REVISION };

$REVISION = sprintf("%d.%d", q$Id: axkit.pm,v 1.2 2002/07/29 03:08:19 jgsmith Exp $ =~ m{(\d+).(\d+)});

###
### [axkit] config variables
###

{
my $doing_config = 0;

sub _setting_path {
    my($self, $variable, $value) = @_;
    return 1 if $doing_config;
    $doing_config = 1;
    $self -> set($variable, Apache -> server_root_relative($value));
    $doing_config = 0;
    return 1;
}
 
sub _expand_string {
    my($self, $variable, $value) = @_;
    return 1 if $doing_config;
    $doing_config = 1;

    $value =~ s{\|}{\\\|}g;
    $self -> set($variable, eval qq:qq|$value|:);
    $doing_config = 0;
    return 1;
}
}

sub _valid_secondary_handler {
    my($variable, $value) = @_;

    return 0 unless Uttu::_init_content_handler($variable, $value);

    return UNIVERSAL::can("Uttu::Handler::$value", "shandle_request");
}

sub init {
    my $self = shift;

    my $class = ref $self || $self;

    Uttu -> define(
        axkit_map_style => {
            ARGCOUNT => ARGCOUNT_HASH,
        },
        axkit_cache_dir => {
            ACTION => \&_setting_path,
        },
        axkit_content_provider => {
        },
        axkit_dependency_checks => {
            ARGCOUNT => ARGCOUNT_NONE,
        },
        axkit_style_provider => {
        },
        axkit_preferred_style => {
        },
        axkit_preferred_media => {
        },
        axkit_cache_provider => {
        },
        axkit_debug_level => {
        },
        axkit_debug_time => {
            ARGCOUNT => ARGCOUNT_NONE,
        },
        axkit_debug_stack_trace => {
            ARGCOUNT => ARGCOUNT_NONE,
        },
        axkit_debug_trace_intermediate => {
            ARGCOUNT => ARGCOUNT_NONE,
        },
        axkit_log_declines => {
            ARGCOUNT => ARGCOUNT_NONE,
        },
        axkit_handle_dirs => {
            ARGCOUNT => ARGCOUNT_NONE,
        },
        axkit_ignore_style_pi => {
            ARGCOUNT => ARGCOUNT_NONE,
        },
        axkit_translate_output => {
            ARGCOUNT => ARGCOUNT_NONE,
        },
        axkit_output_charset => {
        },
        axkit_error_stylesheet => {
        },
        axkit_gzip_output => {
            ARGCOUNT => ARGCOUNT_NONE,
        },
        axkit_xsp_taglib => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_output_transformer => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_plugin => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
#
# following axkit_process_* based on html4.0 media descriptors
#  (see http://www.w3.org/TR/REC-html40/types.html)
#
        axkit_process_screen => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_process_tty => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_process_tv => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_process_projection => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_process_handheld => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_process_print => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_process_braille => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_process_aural => {
            ARGCOUNT => ARGCOUNT_LIST,
        },
        axkit_process_all => {
            ARGCOUNT => ARGCOUNT_LIST,
        },

        # items for this handler (above are for AxKit)
        axkit_secondary_handler => {
            ARGCOUNT => ARGCOUNT_ONE,
            VALIDATE => \&_valid_secondary_handler,
        },
    );

    1;
}

sub file_to_path {
  my($self, $prefix, $path) = @_;

  my $secondary = $self -> secondary_handler;

  return $secondary -> file_to_path($prefix, $path) if $secondary;

  return undef;  # let Apache handle it, in other words
}

sub handle_request {
    my($self, $u, $r) = @_;

    # following copied (and subsequently modified) from AxKit::handler
    #

    local $SIG{__DIE__} = sub { AxKit::prep_exception(@_)->throw };

    local $AxKit::Cfg;
    local $AxKit::DebugLevel;
    local $Error::Debug;

    $AxKit::Cfg = $self -> axkitconfig;

    $AxKit::Cfg -> {apache} = $r;

    $AxKit::DebugLevel = $AxKit::Cfg->DebugLevel();

    if ($AxKit::Cfg->DebugTime) {
        require Time::HiRes;
        $AxKit::T0 = [Time::HiRes::gettimeofday()] if $AxKit::Cfg->DebugTime;
    }

    $Error::Debug = 1 if (($AxKit::Cfg->DebugLevel() > 3) || $AxKit::Cfg->StackTrace);

    AxKit::Debug(1, "handler called for " . $r->uri);

    local $AxKit::FastHandler = 0;

    my $plugin_ret = AxKit::run_plugins($r);
    if ($plugin_ret != OK) {
        AxKit::Debug(2, "Plugin returned non-OK value");
        return $plugin_ret;
    }

    # depends on $AxKit::Cfg, so following is okay
    if($self -> secondary_handler) {
        $AxKit::Cfg->{cfg}{ContentProvider} = 'Uttu::Handler::axkit::ContentProvider';
        $AxKit::Cfg->{cfg}{StyleProvider} ||= 'Apache::AxKit::Provider::File';
    }
    my $provider = Apache::AxKit::Provider->new_content_provider($r);

    return AxKit::main_handler($r, $provider);
    #
    # end copy from AxKit::handler
}

sub fail {
    my($self, $r, $status, $message) = @_;

    $r -> log_reason($message, $r -> filename);
    return $status;
}

###
### Configuration support routines
###

sub set_axkitconfig { $_[0] ->{axkitconfig} = $_[1] }

sub axkitconfig { $_[0] -> {axkitconfig} }

sub set_secondary_handler { $_[0] -> {secondary_handler} = $_[1] }

sub secondary_handler { $_[0] -> {secondary_handler} }

sub config {
  my($class, $c, $param) = @_;
  $class = ref $class || $class;

  my $self = bless { } => $class;

  my $s = $param -> server();

  $self -> set_axkitconfig(Uttu::Handlers::axkit::ConfigReader->new($s));

  my $hostname = ($c -> global_hostname || [$s -> server_hostname]) -> [0];

  if($c -> get('axkit_secondary_handler')) {
      my $shclass = "Uttu::Handler::" . $c -> get('axkit_secondary_handler');
      $self -> set_secondary_handler($shclass -> config($c, $param));
  }

  return $self;
}

1;

__END__

=head1 NAME

Uttu::Handler::axkit

=head1 SYNOPSIS

 [global]
   content_handler = axkit
 
 [axkit]


=head1 DESCRIPTION

By setting the global content_handler configuration variable to axkit,
L<AxKit|AxKit> will be called to parse the web pages and create the
content.

You probably don't want to use Uttu if all you want is AxKit.  If 
you are wanting the uri-to-filename translations, consider 
configuring Uttu to handle the translation and not the content.  
By using Uttu, you are losing some of the flexibility AxKit offers 
in the Apache configuration process.

That said, the Uttu AxKit handler can make XML transformations of 
content trivial if you are also wanting to use a secondary handler 
such as HTML::Mason to provide the XML.

=head1 CONFIGURATION

These variables are used to configure the
L<AxKit|AxKit> object.  The variable names should be preceeded with
C<axkit_> or placed in an [axkit] section.

TODO: describe each of the configuration variables.

=over 4

=item cache_dir

=item cache_provider

=item content_provider

=item debug_level

=item debug_stack_trace

=item debug_time

=item debug_trace_intermediate

=item dependency_checks

=item error_stylesheet

=item gzip_output

=item handle_dirs

=item ignore_style_pi

=item log_declines

=item map_style

=item output_charset

=item output_transformer

=item plugin

=item preferred_media

=item preferred_style

=item process_E<lt>mediaE<gt>

E<lt>mediaE<gt> may be one of C<screen>, C<tty>, C<tv>, C<projection>, 
C<handheld>, C<print>, C<braille>, C<aural>, or C<all>.  These 
configuration variables are used to specify how certain styles 
are processed.

=item secondary_provider

This should be one of the other handlers supported by Uttu.  
Currently, this is only C<mason>.  The secondary handler is used 
to provide the content to AxKit and should be configured as if it 
were the primary Uttu handler.  When a secondary handler is 
specified, the axkit handler uses it to find files.  Otherwise, 
it allows Apache to find them.

=item style_provider

=item translate_output

=item xsp_taglib


=back 4

=head1 SEE ALSO

L<AxKit>.

=head1 AUTHOR

James G. Smith <jsmith@cpan.org>

=head1 COPYRIGHT

Copyright (C) 2002 Texas A&M University.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
