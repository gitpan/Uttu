package Uttu::Handler::mason;

#
# comments in this file assume you have read the documentation (Uttu.pod)
#

use Apache::Constants qw: SERVER_ERROR :;
use AppConfig qw- :argcount EXPAND_NONE -;
use Data::Dumper;
use HTML::Mason;
use HTML::Mason::ApacheHandler;
use strict;
use warnings;

use vars qw{ $REVISION };

$REVISION = sprintf("%d.%d", q$Id: mason.pm,v 1.8 2003/04/16 19:44:36 jgsmith Exp $ =~ m{(\d+).(\d+)});


###
### [mason] config variables
###

{
my $doing_config = 0;

sub _setting_path {
    my($self, $variable, $value) = @_;
    return 1 if $doing_config;
    $doing_config = 1;
    $self -> set($variable, Uttu::Tools::server_root_relative($value));
        #unless $value =~ m{^/};
    $doing_config = 0;
    return 1;
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
    mason_allow_global => {
        ARGCOUNT => ARGCOUNT_LIST,
        EXPAND => EXPAND_NONE,
    },
    mason_auto_send_headers => {
        ARGCOUNT => ARGCOUNT_NONE,
        DEFAULT => 1,
    },
    mason_autohandler_name => {
        DEFAULT => 'autohandler',
    },
    mason_code_cache_max_size => {
        VALIDATE => q"^[0-9_]+\s*[MmKkGg]?$",
        DEFAULT => 10*1024*1024,
        ACTION => \&_convert_bytes,
    },
    mason_comp_root => {
        ARGCOUNT => ARGCOUNT_LIST,
    },
    mason_data_cache_dir => {
        ACTION => \&_setting_path,
    },
    mason_data_dir => {
        ACTION => \&_setting_path,
    },
    mason_decline_dirs => {
        ARGCOUNT => ARGCOUNT_NONE,
        DEFAULT => 1,
    },
    mason_dhandler_name => {
        DEFAULT => 'dhandler',
    },
    mason_error_format => {
        DEFAULT => 'html',
    },
    mason_ignore_warnings_expr => {
        ARGCOUNT => ARGCOUNT_NONE,
    },
    mason_in_package => {
    },
    mason_max_recurse => {
        VALIDATE => q"^[0-9]+$",
        DEFAULT => 32,
    },
    mason_out_mode => {
        VALIDATE => q"^(batch|stream)$",
        DEFAULT => 'batch',
    },
    mason_postamble => {
        ARGCOUNT => ARGCOUNT_LIST,
    },
    mason_preamble => {
        ARGCOUNT => ARGCOUNT_LIST,
    },
    mason_preload => {
        ARGCOUNT => ARGCOUNT_LIST,
    },
    mason_static_file_root => {
        ACTION => \&_setting_path,
    },
    mason_status_title => {
    },
    mason_system_log_event => {
        ARGCOUNT => ARGCOUNT_LIST,
    },
    mason_system_log_file => {
        ACTION => \&_setting_path,
    },
    mason_system_log_separator => {
        DEFAULT => "\cA",
        ACTION => \&_expand_string,
    },
    mason_taint_check => {
        ARGCOUNT => ARGCOUNT_NONE,
    },
    mason_use_data_cache => {
        ARGCOUNT => ARGCOUNT_NONE,
    },
    mason_use_object_files => {
        ARGCOUNT => ARGCOUNT_NONE,
    },
    mason_use_reload_file => {
        ARGCOUNT => ARGCOUNT_NONE,
    },
    mason_use_strict => {
        ARGCOUNT => ARGCOUNT_NONE,
    },
    mason_use => {
        ARGCOUNT => ARGCOUNT_LIST,
    }
  );

  1;
}

sub file_to_path {
  my($self, $prefix, $orig_path, $path_info) = @_;

  my $path = $orig_path;
  $path = "/$path" unless $path =~ m{^/};

  my @paths = ($path);
  while($path) {
       $path =~ s{/.*?$}{};
       push @paths, $path;
  }

  my $function;
  my $roots = $self->ah->interp->comp_root;

  while(!$function && ($path = shift @paths)) {
      last if $function = $self ->{_lookup_cache} -> {$path};

      if(UNIVERSAL::isa($roots, "ARRAY")) {
          foreach my $r (@{$roots}) {
              my $f = $r->[1] ."/". ($r->[0] eq 'function_sets' ? "" : $prefix . "/") . $path;
              $function = $self ->{_lookup_cache} -> {$path} = $f if -f $f or -d _;
          }
      } else {
          $function = $self ->{_lookup_cache} -> {$path} = 
                 $roots ."/". $prefix . "/" . $path 
              if -f ($roots ."/". $prefix . "/" . $path) or -d _;
      }
  }

  #warn "Original path: $orig_path; $path_info\n";
  my $npath = $orig_path;
  $npath = "/$npath" unless $npath =~ m{^/};
  $npath =~ s{^\Q$path\E}{};
  $path_info = '' unless defined $path_info;
  $path_info = "/$npath/$path_info" if defined $npath;
  $path_info =~ s{/+}{/} if defined $path_info;
  #warn "New path: $path; $path_info\n";

  $function .= "dhandler" if $function =~ m{/^};

  return ($function, $path_info);
  
}

sub handle_request {
  my($self, $u, $r) = @_;

  return SERVER_ERROR unless $self -> ah;
  $self -> ah -> interp -> set_global(u => $u);
  $self -> ah -> interp -> set_global(lh => $u -> lh)
    if $u -> config -> global_internationalization;
  $self -> ah -> handle_request($r);
}

sub shandle_request {
    my($self, $u, $r) = @_;

    return '' unless $self -> ah;

    $self -> ah -> interp -> set_global(u => $u);
    $self -> ah -> interp -> set_global(lh => $u -> lh)
        if $u -> config -> global_internationalization;

    my $req = $self -> ah -> prepare_request($r);

    throw Apache::AxKit::Exception::IO(
        -text => $req
    ) unless ref($req);

    my $content;

    $req -> out_method(\$content);
    $req -> auto_send_headers(0);

    my $ret = $req->exec;

    return \$content;

#      my $mh = new HTML::Mason::ApacheHandler(
#        auto_send_headers => 0
#    );
}

###
### Configuration support routines
###

sub set_ah { $_[0] ->{ah} = $_[1] }

sub ah { $_[0] -> {ah} }

sub config {
   my($class, $c, $param) = @_;
   $class = ref $class || $class;

   my $self = bless { } => $class;

   my($s, $hostname);

   if($ENV{MOD_PERL}) {
     $s = $param -> server();
     if(@{$c -> global_hostname || []}) {
       $hostname = $c -> global_hostname -> [0];
     } else {
       $hostname = $s -> server_hostname;
     }
   }

  if(!$c -> mason_in_package) {
    if($ENV{MOD_PERL}) {
      # default package: Uttu::Sites::$server::$port::$location

      my $loc = $param -> path();

      $loc =~ s{/}{::}g;
      $loc =~ s{ }{_}g;

      my $h = $hostname;
      $h =~ s{\.}{_}g if $h;
      my $p = join("::", "Uttu::Sites", ($h || "localhost"), "Port_" . ($s -> port || 80) );
      $p .= $loc unless $loc eq '::';
      $p =~ s{::$}{};
    
      $c -> mason_in_package($p);
    } else {
      my $count if 0;
      $count ||= "M001";
      $c -> mason_in_package("Uttu::Sites::$count");
      $count++;
    }
  }

  if($c -> mason_use) {
    my @m = map { "use $_; " } @{$c -> mason_use || []};
    my $e = "package " . $c -> mason_in_package . "; " . join(" ", @m);

    eval $e;
    warn "$@\n" if $@;
  }


  $c -> mason_status_title("Uttu - " . ($hostname || 'localhost') . ":" 
                                    . ($c -> global_port || $s -> port || 80)
                                    . $param->path())
      unless !$ENV{MOD_PERL} || $c -> mason_status_title;

  my $comp_root = [ ];
  my %pathnames = ( );
  if($c -> mason_comp_root) {
    my $paths = [];
    my $can_get_by_without_a_name = scalar(@{$c -> mason_comp_root || []}) == 1;
    if($can_get_by_without_a_name && $c->mason_comp_root->[0] !~ /=/) {
      $comp_root = [ [ 'local', Uttu::Tools::server_root_relative($c->mason_comp_root->[0]) ] ];
      $pathnames{local} = ( );
    } else {
      foreach my $p (@{$c -> mason_comp_root || []}) {
        my($n, $d) = split(/\s*=>?\s*/, $p, 2);
        push @{$paths}, [ $n, Uttu::Tools::server_root_relative($d) ];
        $pathnames{$n} = ( );
      }
      $comp_root = $paths;
    }
  }
  if(defined $c -> global_framework) {
    push @{$comp_root}, 
       [ 'function_sets', $Uttu::Config::PREFIX . "/functionsets/" . $c -> global_framework . "/" ]
           unless exists $pathnames{function_sets};
    unless(exists $pathnames{framework}) {
      my $p = $INC{'Uttu/Framework/' . $c -> global_framework . ".pm"};
      $p =~ s{lib/Uttu/Framework/.*$}{};
      $p ||= $Uttu::Config::PREFIX . "/framework/" . $c -> global_framework;
      push @{$comp_root}, [ 'framework', $p ];
    }
  }

  # now check to make sure we have sufficient minimum settings
  my @missing;
  for my $r (qw: data_dir comp_root :) {
    push @missing, $r unless defined $c -> get("mason_$r");
  }

  if(@missing) {
    warn "The following configuration variables are missing from the"
       . " [mason] section:\n". join(", ", sort @missing). "\n";
    warn "Unable to complete configuration of HTML::Mason\n";
    die "\n";
  }

  eval {
    my %interp_options = (
      autohandler_name    => $c -> mason_autohandler_name,
      code_cache_max_size => $c -> mason_code_cache_max_size,
      dhandler_name       => $c -> mason_dhandler_name,
      max_recurse         => $c -> mason_max_recurse,
      preloads            => $c -> mason_preload || [],
      use_object_files    => $c -> mason_use_object_files,
    );

    $interp_options{data_dir}         = $c -> mason_data_dir if $c -> mason_data_dir;
    $interp_options{comp_root}        = $comp_root if $c -> mason_comp_root;
    $interp_options{data_cache_dir}   = $c -> mason_data_cache_dir if $c -> mason_data_cache_dir;
    $interp_options{static_file_root} = $c -> mason_static_file_root if $c -> mason_static_file_root;
    $interp_options{system_log_file}  = $c -> mason_system_log_file if $c -> mason_system_log_file;

    my %handler_options = (
      auto_send_headers   => $c -> mason_auto_send_headers,
      decline_dirs        => $c -> mason_decline_dirs,
      error_format        => $c -> mason_error_format,
    );


    $handler_options{apache_status_title} = $c->mason_status_title if $c->mason_status_title;
      
    my %parser_options = (
        allow_globals        => [ @{$c -> mason_allow_global}, qw($r $u) ],
        ignore_warnings_expr => $c -> mason_ignore_warnings_expr,
        in_package           => $c -> mason_in_package,
        use_strict           => $c -> mason_use_strict,
        postamble            => join(" ", @{$c -> mason_postamble || []}),
        preamble             => join(" ", @{$c -> mason_preamble  || []}),
    );

    # configure apache handler
    my $ah;
    if($HTML::Mason::VERSION >= 1.09) {
      $ah = new HTML::Mason::ApacheHandler(
        %handler_options,
        %interp_options,
        #parser                   => new HTML::Mason::Parser (
            %parser_options,
        #)
      );
    } else {
      $ah = new HTML::Mason::ApacheHandler(
        %handler_options,
        interp              => new HTML::Mason::Interp ( 
            %interp_options,
            use_autohandlers    => 1,
            use_data_cache      => $c -> mason_use_data_cache,
            use_dhandlers       => 1,
            out_mode            => $c -> mason_out_mode,
            system_log_events   => join("|", @{$c -> mason_system_log_event || []}),
            system_log_separator => $c -> mason_system_log_separator,
            use_reload_file     => $c -> mason_use_reload_file,
            parser                   => new HTML::Mason::Parser (
                %parser_options,
                taint_check          => $c -> mason_taint_check,
            )
        )
      );
    }
    $self -> set_ah($ah);
    if($ENV{MOD_PERL}) {
      chown (Apache->server->uid, Apache->server->gid, $ah -> interp -> files_written);
    }
  };
  if($@) {
    warn "Unable to create HTML::Mason interpretor: $@\n";
    die "\n";
  };
  return $self;
}

1;

__END__

=head1 NAME

Uttu::Handler::mason

=head1 SYNOPSIS

 [global]
   content_handler = mason
 
 [mason]
   data_dir /data/apache/uttu/mason_data
   comp_root my/components
   use_object_files
   use_strict

=head1 DESCRIPTION

By setting the global C<content_handler> configuration variable to
C<mason>, L<HTML::Mason|HTML::Mason> will be called to parse the web pages
and create the content.

=head1 GLOBALS

The HTML::Mason content handler makes the following global variables available.

=over 4

=item $u

This is the C<Uttu> object responsible for the current request.

=item $lh

If C<internationalization> is enabled, then this is define and is the
L<Locale::Maketext|Locale::Maketext> object providing translation services
into the preferred language of the client.

=back

=head1 CONFIGURATION

These variables are used to configure the
L<HTML::Mason::ApacheHandler|HTML::Mason::ApacheHandler> object.

=over 4

=item allow_global

List of variable names, complete with prefix ($@%), that you intend to use
as globals in components.  Normally, global variables are forbidden by
C<strict>, but any variable mentioned in this list is defined as a package
global in the C<$mason_in_package> package.

 allow_global $DBH
 allow_global %session

C<$r> and C<$u> are automatically added to this list.

=item auto_send_headers

If this is true, Mason will send the headers before sending any content.
Otherwise, the framework will need to send the headers before the content.
This may be useful if cookies are not being sent properly from within the
framework, for example.

The default is true.

=item autohandler_name

File name used for autohandlers.

The default is C<autohandler>.

=item code_cache_max_size

This specifies, in bytes, the maximum size of the in-memory cache used by
the HTML::Mason interpreter.

The following are all equivalent, capitalization is not significant.

 code_cache_max_size 2147483648
 code_cache_max_size    2097152 k
 code_cache_max_size       2048 M
 code_cache_max_size          2 G

Each Uttu configuration has its own HTML::Mason objects with their own code
cache.  The result, for example, is that two configurations, each with 10M
cache, will have a combined cache of 20M with no sharing between them.

The default is 10M.

=item comp_root

This is the Mason component root.  All components are under this path.

Uttu supports multiple component roots.  If more than one is specified, they
must be named.

 comp_root site

but

 comp_root modules => /usr/local/share/uttu/$global_framework
 comp_root local   => site

The component roots will be searched in the order given.

If the component root is a relative path, it is assumed to be relative to
the server root.

If the component root is not named, it is given the name C<local> to
distinguish the files from the framework or installed function sets.

Two named component roots are expected if a framework is defined in the
[global] section: C<function_sets> and C<framework>.  If not defined
explicitly in the configuration file, they are added automatically.

The C<framework> component root is based on the location of the
C<Uttu::Framework::$framework> module, if in C<%INC> or on the default
installation path.  For example, if the framework module is in
C</usr/local/MofN/lib/Uttu/Framework/MofN.pm>, then the component root is
C</usr/local/MofN/>.  Otherwise, if the default installation path is
C</usr/local/uttu/>, then the component root is
C</usr/local/uttu/framework/MofN>.

The C<function_sets> component root is based on the default installation
path.  If this is C</usr/local/uttu/>, then the component root is
C</usr/local/uttu/functionsets/$framework/>.  Note that the
C<$global_function_set_base> setting is not used when looking for files in
the C<function_sets> component root.

At least one component root must be defined either explicitly in the
configuration file or by defining the framework in the [global] section.
Failure to do so will keep Apache from starting.

=item data_cache_dir

Specifies an absolute directory for data cache files.

The default is C<$mason_data_dir/cache>.

=item data_dir

This is the directory in which Mason keeps certain files (e.g., the C<obj>,
C<cache>, C<debug> directories).  This must be writable by the web server
after startup.

If the data directory is a relative path, it is assumed to be relative to
the server root.

If the interpreter writes any files during configuration, they are
C<chown>ed to the user and group Apache will become at request time.

This variable must be defined in the configuration file.  Failure to do so
will keep Apache from starting.

=item decline_dirs

If this is true, then Mason will not try to handle requests for
directories.  This must be false for a C<dhandler> to have an opportunity
at handling a directory request.

The default is true.

=item dhandler_name

File name used for dhandlers.

The default is C<dhandler>.

To use a dhandler, map the directory containing the dhandler to a uri
directory.  For example:

  map_uri /cm = my-cm/

This will map C</cm/(.*)> to C<my-cm/$1> where the dhandler is
C<my-cm/dhandler> (using the default dhandler name) if the uri is one that
is normally translated and handled by the content handler (the extension on
the uri must be one mentioned in a C<handle> configuration line).

=item error_format

This default is <html>.  This may be used to specify a different 
output format.  The function C<HTML::Mason::Exception::as_$error_format> 
is called and should return the formatted error report.

=item ignore_warnings_expr

This is a regular expression indicating which warnings to ignore when
compiling subroutines.  Any warning that is not ignored will prevent the
component from being compiled and executed.

 ignore_warnings_expr Global symbol.*requires explicit package

If not defined, all warnings are heeded; if C<.>, all warnings are ignored.

=item in_package

This indicates the name of the package in which components run.  This
allows different applications or different virtual hosts to run in
different namespaces.

The default is C<Uttu::Sites::$server::Port_$port::$loc>, where C<$server>
is the virtual host or server hostname with C<_> replacing C<.>, C<$port>
is the port, and C<$loc> is the path to the root URI for this
configuration, with C<::> replacing C</> (for all by the initial C</>,
which is discarded).  This allows multiple configurations to have separate
namespaces without having to explicitely configure them.

For example, for a Uttu site rooted at C<http://my.server:8000/some/url/>,
the default package is C<Uttu::Sites::my_server::Port_8000::some::url>.

Changing this requires removal of all object files since this affects the
parser.

=item max_recurse

This is the maximum component stack depth the interpreter is allowed to
descend before signalling an error.  Note that this is
not impacted by the C<Uttu> content handler -- there are no `hidden'
components.

The default is 32.

=item out_mode

Specifies one of two ways to send output: C<batch> or C<stream>.  In batch
mode, Mason computes the entire page in a memory buffer before transmitting
it all at once.  In stream mode, Mason outputs data as soon as possible.
This does not affect any buffering being done by Perl or the operating
system.

The default is C<batch>.

=item postamble

This is code added automatically by Mason to the end of each component.
This can be useful when debugging, for example.  Code can be continued onto
another line by ending the line with the continuation character (\).
Multiple C<postamble>s are concatenated.

Changing this requires removal of all object files since this affects the
parser.

The following will duplicate the effect of the postamble in the article on
the Mason home page about graphing the component tree.

 postamble unless($m -> current_comp->title eq '/log') { \
               my $parent=$m->callers(1); \
               if(defined($parent)) { \
                   $m -> comp('/log',    me => $m->current_comp->title, \
                                     parent => $parent->title); \
               } \
           };

This is equivalent to

 postamble unless($m -> current_comp->title eq '/log') {
 postamble     my $parent=$m->callers(1);
 postamble     if(defined($parent)) {
 postamble         $m -> comp('/log',    me => $m->current_comp->title,
 postamble     }
 postamble };

=item preamble

This is code added automatically by Mason to the beginning of each
component.  Code can be continued onto another line by ending the line with
the continuation character (\).  Multiple C<preamble>s are concatenated.

Changing this requires removal of all object files since this affects the
parser.

=item preload

This is a list of components which are loaded when the Mason interpreter
initializes.  These may contain glob wild cards.

 preload /foo/index.html
 preload /bar/*.pl

=item static_file_root

Absolute path to prepend to relative filenames passed to C<$m-E<gt>file()>.
This does not require a trailing slash.  This is relative to the server
root if it is not itself an absolute path.

The default is C<$mason_comp_root>.

=item status_title

This is the title used in the L<Apache::Status|Apache::Status> pages.

Default is C<Uttu - $server:$port/$location>.

=item system_log_event

This is a list of events to record in the system log.
Current events (dependent on HTML::Mason):

 ALL     := REQUEST CACHE COMP_LOAD
 REQUEST := REQ_START REQ_END
 CACHE   := CACHE_READ CACHE_WRITE

The following configurations are equal:

 system_log_event REQUEST

and

 system_log_event REQ_START
 system_log_event REQ_END

The default is to log nothing.

=item system_log_file

=item system_log_separator

Separator to use between fields on a line in the system log.  Strings are
expanded, so control characters can be specified.

The default is ctrl-A (C<\cA>).

=item taint_check

Setting this flag allows Mason to work even when taint checking is on.  If
true, Mason will pass all component source and filenames through a dummy
regular expression match to untaint them.

The default is false.

=item use_data_cache

If this is set, then C<$m-E<gt>cache> and related commands are operational.

The default is true.

=item use_object_files

If this is set, then Mason creates object files to save the results of parsing components.

The default is true.

=item use_reload_file

If this is true, disables Mason's automatic timestamp checking on component
source files, relying instead on an explicitly updated reload file, kept in
C<$mason_data_dir/etc/reload.lst>.

The default is false.

=item use_strict

Indicates whether to C<use strict> in compiled subroutines.

The default is true.

=item use

A list of modules to load.  The syntax is identical to that of Perl
(without the trailing semicolon):

  use Error qw(:try)
  use Quantum::Superpositions qw(all any)

Symbols will be imported into the package specified by the C<in_package>
variable.

=back 4

=head1 SEE ALSO

L<HTML::Mason>.

=head1 AUTHOR

James G. Smith <jsmith@cpan.org>

The descriptions of the Mason configuration variables are based on the
HTML::Mason documentation.

=head1 COPYRIGHT

Copyright (C) 2002 Texas A&M University.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
