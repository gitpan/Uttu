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

$REVISION = sprintf("%d.%d", q$Id: axkit.pm,v 1.7 2003/03/12 06:33:48 jgsmith Exp $ =~ m{(\d+).(\d+)});

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
        axkit_document_root => {
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

  return $self ->{_lookup_cache} -> {$path}
      if $self ->{_lookup_cache} -> {$path};
      
  my $roots = $self -> axkitconfig -> _DocumentRoots();

  foreach my $r (@{$roots}) {
      my $f = $r->[1] ."/". ($r->[0] eq 'function_sets' ? "" : $prefix . "/") . $path;
      return $self ->{_lookup_cache} -> {$path} = $f if -f $f or -d _;
  }
  return undef;  # let Apache handle it, in other words
}

sub handle_request {
    my($self, $u, $r) = @_;

    return AxKit::handler($r);
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

  require Uttu::Handler::axkit::ConfigReader;
  $self -> set_axkitconfig(Uttu::Handler::axkit::ConfigReader -> new($s));

  $s -> dir_config(AxConfigReader => 'Uttu::Handler::axkit::ConfigReader');

  my $hostname = ($c -> global_hostname || [$s -> server_hostname]) -> [0];

  if($c -> get('axkit_secondary_handler')) {
      my $shclass = "Uttu::Handler::" . $c -> get('axkit_secondary_handler');
      #warn "secondary handler class: $shclass\n";
      $self -> set_secondary_handler($shclass -> config($c, $param));
      $s -> dir_config(AxContentProvider => 'Uttu::Handler::axkit::ContentProvider');
      $s -> dir_config(AxStyleProvider => 'Apache::AxKit::Provider::File');
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

This option takes a single argument and sets the directory that the 
cache module stores its files in.  No caching will take place if 
this is not set.  To disable caching, unset this option.

=item cache_provider

=item content_provider

=item debug_level

If present, this makes AxKit send output to Apche's error log.  
The valid range is 0-10, with 10 producing more output.

=item debug_stack_trace

This flag option says whether to maintain a stack trace with every 
exception.

=item debug_time

=item debug_trace_intermediate

With this option, you advise AxKit to store the result of each 
transformation request in a special directory for debugging.

=item dependency_checks

=item document_root

=item error_stylesheet

If an error occurs during processing that throws an exception, the 
exception handler will try and find an ErrorStylesheet to use to 
process an XML-formatted error page.

=item gzip_output

This option allows you to use the L<Compress::Zlib|Compress::Zlib> 
module to gzip output to browsers that support gzip compressed pages.

=item handle_dirs

This option allows AxKit to process directories.

=item ignore_style_pi

Turn off parsing and overriding stylesheet selection for XML files 
containing an "xml-stylesheet" processing instruction at the start 
of the file.

=item log_declines

This option is a flag (default off).  When AxKit declines to 
process a URI, it gives a reason.  Normally this reason is not 
sent to the log.  However, if this option is set, the reason is 
logged.

=item map_style

This option maps module stylesheet MIME types to stylesheet 
processor modules.

=item output_charset

Fixes the output character set, rather than using either UTF-8 or 
the user's preference from the Accept-Charset HTTP header.

=item output_transformer

This option may be used to list output transformers that are 
applied just before output is sent to the browser.

=item plugin

This option may be used to list multiple modules whose C<handler> 
method is called before any AxKit processing is done.

=item preferred_media

This specifies a default meda type to use.

=item preferred_style

This specifies a  default stylesheet title to use.

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

This option enables output character set translation.

=item xsp_taglib

XSP supports two types of tag libraries.  The simplest type to 
understand is merely an XSLT or XPathScript (or other transformation 
language) stylesheet that transforms custom tags into the "raw" XSP 
tag form.  However thre is another kind that is faster, and these 
taglibs transform the custom tags into pure code which then gets 
compiled.  These taglibs must be loaded into the server using this 
option.

=back 4

=head1 SEE ALSO

L<AxKit>.

=head1 AUTHOR

James G. Smith <jsmith@cpan.org>

Much of the configuration option documentation is based on the 
documentation in the AxKit module.

=head1 COPYRIGHT

Copyright (C) 2002-2003 Texas A&M University.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
