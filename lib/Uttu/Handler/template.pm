package Uttu::Handler::template;

#
# comments in this file assume you have read the documentation (Uttu.pod)
#

use Apache::Constants qw: SERVER_ERROR OK :;
use AppConfig qw- :argcount -;
use Data::Dumper;
use Template;
use strict;
use warnings;

use vars qw{ $REVISION };

$REVISION = sprintf("%d.%d", q$Id: template.pm,v 1.2 2002/04/15 22:27:05 jgsmith Exp $ =~ m{(\d+).(\d+)});

###
### [template] config variables
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

sub init {
  my $self = shift;

  my $class = ref $self || $self;

  Uttu -> define(
    template_include_path => {
      ARGCOUNT => ARGCOUNT_LIST,
    },
    template_pre_process => {
      ARGCOUNT => ARGCOUNT_LIST,
    },
    template_interpolate => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_post_chomp => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_eval_perl => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_start_tag => {
      ARGCOUNT => ARGCOUNT_ONE,
    },
    template_end_tag => {
      ARGCOUNT => ARGCOUNT_ONE,
    },
    template_tag_style => {
      ARGCOUNT => ARGCOUNT_ONE,
    },
    template_pre_chomp => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_trim => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_anycase => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_delimiter => {
      ARGCOUNT => ARGCOUNT_ONE,
    },
    template_absolute => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_relative => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_default => {
      ARGCOUNT => ARGCOUNT_ONE,
    },
    template_block => {
      ARGCOUNT => ARGCOUNT_HASH,
    },
    template_auto_reset => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_recursion => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_pre_define => {
      ARGCOUNT => ARGCOUNT_HASH,
    },
    template_post_process => {
      ARGCOUNT => ARGCOUNT_LIST,
    },
    template_error => {
      ARGCOUNT => ARGCOUNT_LIST,
    },
    template_debug => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_cache_size => {
      ARGCOUNT => ARGCOUNT_ONE,
      VALIDATE => q"^\d+$",
    },
    template_compile_ext => {
      ARGCOUNT => ARGCOUNT_ONE,
    },
    template_compile_dir => {
      ARGCOUNT => ARGCOUNT_ONE,
      ACTION => \&_include_file,
    },
    template_plugin => {
      ARGCOUNT => ARGCOUNT_HASH,
    },
    template_plugin_base => {
      ARGCOUNT => ARGCOUNT_LIST,
    },
    template_load_perl => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_filter => {
      ARGCOUNT => ARGCOUNT_HASH,
    },
    template_v1dollar => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
    template_load_template => {
      ARGCOUNT => ARGCOUNT_LIST,
    },
    template_load_plugin => {
      ARGCOUNT => ARGCOUNT_LIST,
    },
    template_load_filter => {
      ARGCOUNT => ARGCOUNT_LIST,
    },
    template_tolerant => {
      ARGCOUNT => ARGCOUNT_NONE,
    },
  );

  1;
}

sub file_to_path {
  my($self, $prefix, $path) = @_;

  return $self ->{_lookup_cache} -> {$path}
      if $self ->{_lookup_cache} -> {$path};

  my $roots = $self->{_template_include_path};

  if(UNIVERSAL::isa($roots, "ARRAY")) {
      foreach my $r (@{$roots}) {
          my $f = $r->[1] ."/". $prefix  . $path;
          return $self ->{_lookup_cache} -> {$path} = $f if -f $f or -d _;
      }
  } else {
      return $self ->{_lookup_cache} -> {$path} = 
             $roots ."/". $prefix . "/" . $path 
          if -f ($roots ."/". $prefix . "/" . $path) or -d _;
  }
}

sub handle_request {
  my($self, $u, $r) = @_;

  my $ttconfig = $self -> ttconfig;

  return SERVER_ERROR unless $ttconfig;

# we need to deal with pathinfo for dhandler-like operation
  my $params = {
    u => $u,
    r => $r,
  };

  $params -> {lh} = $u -> lh
    if $u -> config -> global_internationalization;

  my $to = Template -> new(%$ttconfig, OUTPUT => $r);

  $r -> content_type('text/html');
  $r -> send_http_header;

  local(*FH);
  open FH, "<" . $r -> filename or return $self->fail($r, SERVER_ERROR, $!);

  unless($to -> process(\*FH, $params)) {
    close FH;
    return $self->fail($r, SERVER_ERROR, $to -> error);
  }

  close FH;

  return OK;
}

sub fail {
  my($self, $r, $status, $message) = @_;

  $r -> log_reason($message, $r -> filename);
  return $status;
}

###
### Configuration support routines
###

sub set_ttconfig { $_[0] ->{ttconfig} = $_[1] }

sub ttconfig { $_[0] -> {ttconfig} }

sub config {
  my($class, $c, $param) = @_;
  $class = ref $class || $class;

  my $self = bless { } => $class;

  my %items = qw(
  template_start_tag    START_TAG
  template_end_tag      END_TAG
  template_tag_style    TAG_STYLE
  template_pre_chomp    PRE_CHOMP
  template_post_chomp   POST_CHOMP
  template_trim         TRIM
  template_interpolate  INTERPOLATE
  template_anycase      ANYCASE
  template_delimiter    DELIMITER
  template_absolute     ABSOLUTE
  template_relative     RELATIVE
  template_default      DEFAULT
  template_block        BLOCKS
  template_auto_reset   AUTO_RESET
  template_recursion    RECURSION
  template_pre_define   PRE_DEFINE
  template_eval_perl    EVAL_PERL
  template_pre_process  PRE_PROCESS
  template_post_process POST_PROCESS
  template_process      PROCESS
  template_error        ERROR
  template_debug        DEBUG
  template_cache_size   CACHE_SIZE
  template_compile_ext  COMPILE_EXT
  template_compile_dir  COMPILE_DIR
  template_plugin       PLUGINS
  template_plugin_base  PLUGIN_BASE
  template_load_perl    LOAD_PERL
  template_filter       FILTERS
  template_v1dollar     V1DOLLAR
  template_load_template LOAD_TEMPLATES
  template_load_plugin  LOAD_PLUGINS
  template_load_filter  LOAD_FILTERS
  template_tolerant     TOLERANT
  );

  my $s = $param -> server();
  my $hostname = ($c -> global_hostname || [$s -> server_hostname]) -> [0];

  my $config = { };

  my @roots = @{$c -> template_include_path || [ Apache -> server_root_relative("local") ]};

  if(defined $c -> global_framework) {
    push @roots, $Uttu::Config::PREFIX . "/functionsets/" . $c -> global_framework . "/";
    my $p = $INC{'Uttu/Framework/' . $c -> global_framework . ".pm"};
    $p =~ s{lib/Uttu/Framework/.*$}{};
    $p ||= $Uttu::Config::PREFIX . "/framework/" . $c -> global_framework;
    push @roots, $p;
  }

  $config -> {INCLUDE_PATH} = 
      join($c -> template_delimiter || ":", @roots);

  foreach my $i (keys %items) {
    $config -> {$items{$i}} = $c -> get($i) if $c -> get($i);
  }

  $self -> set_ttconfig($config);

  return $self;
}

1;

__END__

=head1 NAME

Uttu::Handler::template

=head1 SYNOPSIS

 [global]
   content_handler = template
 
 [template]


=head1 DESCRIPTION

By setting the global content_handler configuration variable to template,
L<Template|Template> will be called to parse the web pages and create the
content.

=head1 GLOBALS

The Template content handler makes the following global variables available.

=over 4

=item u

This is the C<Uttu> object responsible for the current request.

=item lh

If C<internationalization> is enabled, then this is defined and is the
L<Locale::Maketext|Locale::Maketext> object providing translation services
into the preferred language of the client.

=item r

The Apache::Request object.

=back

=head1 CONFIGURATION

These variables are used to configure the
L<Template|Template> object.  The variable names should be preceeded with
C<template_> or placed in a [template] section.

=over 4

=item absolute

A flag indicating whether or not to allow absolute file names.

The default is false.

=item anycase

Whether or not to allow directives in lower case.

The default is false, requiring directives to be in all UPPER case.

=item auto_reset

A flag enabling BLOCK definitions to persist across templates.  Note that
we current construct a new Template object for each request.

The default is false.

=item block

  block NAME = CODE

Pre-define a template block with the name C<NAME>.

=item cache_size

Maximum number of compiled templates to cache in memory.

The default is C<undef> -- cache all templates.

=item compile_dir

Root of directory in which compiled template files should be written.  This
may be a relative path which will be taken as relative to the server root.

The default is C<undef> -- do not compile.

=item compile_ext

The filename extension for compiled template files.

Default is C<undef> -- do not compile.

=item debug

A flag indicating whether or not to raise an error when an undefined variable is accessed.

The default is false.

=item default

The default template to use when another is not found.

=item delimiter

The delimiter separating paths in C<INCLUDE_PATH>.  This does not affect
how C<include_path> is used in the Uttu configuration file.

The default is `:'.

=item end_tag

This is the token that indicates the end of directives.

The default is C<%]>.

=item error

Mapping of error types to templates.

=item eval_perl

A flag indicating whether or not PERL/RAWPERL blocks should be processed.

The default is false.

=item filter

Map a filter name to a filter subroutine or factory.

=item include_path

A list of directories in which to search for templates.  If this is not
defined, then C<$server_root/local> is added.

If a framework is defined, then the installation directories of the
framework and function sets are added.

=item interpolate

Whether or not to interpolate variables embedded as C<$this> or C<${this}>.

The default is false.

=item load_filter

Load the specified filter provider.

=item load_perl

A flag to indicate whether regular Perl modules should be loaded if a named
plugin can't be found.

The default is false.

=item load_plugin

Load the specifide plugin provider.

=item load_template

Load the specifide template provider.

=item plugin

  plugin PLUGIN My::Package

Map plugin names to Perl packages.

=item plugin_base

One or more base classes under which plugins may be found.

=item post_chomp

A flag indicating whether or not to remove whitespace after directives.

The default is false.

=item post_process

Name of templates to process after the main template.

=item pre_chomp

A flag indicating whether or not to remove whitespace before directives.

The default is false.

=item pre_define

  pre_define key = value

A mapping of variables to values to pre-define in the stash.

=item pre_process

Name of templates to process before the main template.

=item recursion

A flag indicating whether or not to allow recursion into templates.

The default is false.

=item relative

A flag indicating whether or not to allow relative filenames.

The default is false.

=item start_tag

This is the token that indicates the beginning of directives.

The default is C<[%>.

=item tag_style

Sets C<start_tag> amd C<end_tag> according to a pre-defined style.

The default is `template' giving the default values for C<start_tag> and C<end_tag>.

=item tolerant

A flag indicating whether or not providers should tolerate errors as declinations.

The default is false.

=item trim

Whether or not to remove leading and trailing whitespace from template output.

The default is false.

=item v1dollar

A flag indicating whether or not to enable version 1.* handling of leading `$' on variables.

The default is false -- `$' indicates interpolation.

=back 4

=head1 SEE ALSO

L<Template>.

=head1 AUTHOR

James G. Smith <jsmith@cpan.org>

The descriptions of the Mason configuration variables are based on the
Template documentation.

=head1 COPYRIGHT

Copyright (C) 2002 Texas A&M University.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
