package Uttu;

# $Id: Uttu.pm,v 1.7 2002/03/20 17:53:29 jgsmith Exp $

# AUTHOR
# 
# James G. Smith <jsmith@cpan.org>
# 
# COPYRIGHT
# 
# Copyright (C) 2002 Texas A&M University.  All Rights Reserved.
# 
# This module is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
# 

#
# comments in this file assume you have read the documentation (Uttu.pod)
#

use lib qw: /usr/local/apache/perl/module-require/lib :;
use Apache;
use Apache::Constants           qw- :common DECLINE_CMD -;
use Apache::ModuleConfig;
use AppConfig                   qw- :argcount :expand -;
use Cache::SizeAwareMemoryCache ();
use Carp;
use DynaLoader                  ();
use File::Glob                  qw: bsd_glob :;
use Uttu::Tools qw: define_cache define_db :;
use Uttu::Config;
use strict;
use warnings;

use vars qw: $VERSION %variables %configs :;

$VERSION = "0.01";

my $self_for_config;
my $config_for_define;

if($ENV{MOD_PERL}) {
  no strict;

  require Apache::DBI;
  Apache::DBI -> import();

  local(@ISA) = (@ISA, qw(DynaLoader));
  __PACKAGE__ -> bootstrap($VERSION);
}

require DBI;
DBI -> import();

# for server restarts...  can't figure out how else to keep the package in Perl
# let's experiment a bit, and hope we get better Apache::Status behavior
delete @INC{grep m{Uttu/}, keys %INC};

sub retrieve {
    my $class = shift;
    return $class if ref $class;

    my $r;
    my $self;
    if($r = Apache -> request) {
	$self = Apache::ModuleConfig -> get($r, $class);
	unless($self) { # try and look it up in %configs
	    my $sconfig = Apache::ModuleConfig->get($r -> server, __PACKAGE__);
            my $server = $r -> get_server_name;
            my $port   = $r -> get_server_port;
	    my $cs = $configs{"$server:$port"};
            if(defined $cs) {
                my $uri = $r -> uri;
                my $luri = length($uri);
                my @roots = sort { length($a) <=> length($b) } grep { length($_) <= $luri && $uri =~ m{^$_} } keys %$cs;
		return unless @roots;
                # if an Alias(Match)? or SetHandler config is between the root and the uri, we need to return undef
		my @a = grep {$roots[0] =~ /^$_/} (@{$sconfig -> {_alias}},
						   @{$sconfig -> {_aliasmatch}},
						   @{$sconfig -> {_sethandler}});
		#my @as= grep {$roots[0] =~ /^$_/} @{$sconfig -> {_aliasmatch}};
		#my @sh= grep {$roots[0] =~ /^$_/} @{$sconfig -> {_sethandler}};
		return if grep {length($_) <= $luri && $uri =~ /^$_/} @a; #(@a, @as, @sh);
                $self = $cs->{$roots[0]} if @roots;

            }
	}
    } elsif($self_for_config) {
	$self = $self_for_config;
    }
    return $self;
}

sub new {
    my $self = shift;
    my $class = ref $self || $self;

    carp "Using " . __PACKAGE__ . " -> new()";

    return bless { } => $class;
}

# used for config file stuff

sub define {
    my($self) = shift;
    my %ds = @_;

    if($config_for_define) {
        $config_for_define -> define(%ds);
    } else {
        @variables{keys %ds} = values %ds;
    }
}

###
### [global] config variables
###

sub _set_from_file {
    my($self, $variable, $value) = @_;
    my $file = Apache -> server_root_relative($value);
    local(*FH);
    open FH, "< $file" or warn "Unable to read $file\n";
    my $p = <FH>;
    close FH;
    return unless defined $p;
    chomp($p);
    $variable =~ s{_file$}{};
    $self -> set($variable, $p);
    return 1;
}

sub _validate_framework {
    my($variable, $value) = @_;

    # we want to load several things:
    #   Uttu::Framework::$value
    #     and run Uttu::Framework::$value -> init()
    #     failure here means this is an invalid value

    my $framework = "Uttu::Framework::$value";

    { local(@INC) = @INC;
      push @INC, "$Uttu::Config::PREFIX/framework/$value/lib";

      my $ret = eval qq{require $framework;};

      return unless $ret;

      eval { $ret = $framework -> init(); };

      return unless $ret;
      return if $@;
    }
    push @INC,  "$Uttu::Config::PREFIX/framework/$value/lib";
    return 1;
}

sub _validate_lib {
    my($variable, $value) = @_;

    my $l = Apache -> server_root_relative($value);
    return unless -d $l;

    push @INC, $l;
    return 1;
}

sub _init_content_handler {
    my($variable, $value) = @_;

    eval qq{require Uttu::Handler::$value};
    warn "$@\n" if $@;
    return 0 if $@;

    my $ret;

    eval { $ret = "Uttu::Handler::$value" -> init(); };
    warn "$@\n" if $@;

    return $ret;
}

sub _allow_include_file {
    return $Uttu::Config::max_include_depth 
         > $Uttu::Config::curr_include_depth;
}

sub _include_file {
    my($self, $variable, $value) = @_;

    {
        local($Uttu::Config::max_include_depth);

        $Uttu::Config::curr_include_depth++;
        $self -> file(Apache -> server_root_relative($value));
        $Uttu::Config::curr_include_depth--;
    }
    $self -> set("global_max_include_depth", $Uttu::Config::max_include_depth);
}

sub _set_include_depth {
    my($self, $variable, $value) = @_;

    $Uttu::Config::max_include_depth = $value;
}
    

Uttu -> define(
    global_fallback_language => {
        ARGCOUNT => ARGCOUNT_LIST,
        DEFAULT => 'en',
    },
    define_db("global_db"),
    define_cache("global_uri_map"),
    global_db_uri_map_select_comp => {
        DEFAULT => "SELECT file FROM functions WHERE uri=?",
    },
    global_db_uri_map_select_uri => {
        DEFAULT => "SELECT uri FROM functions WHERE file=?",
    },
    global_internationalization => {
        ARGCOUNT => ARGCOUNT_NONE,
        ALIAS => 'global_i18n',
        DEFAULT => 1,
    },
    global_function_set_base => {
        DEFAULT => "sets",
    },
    global_handle => {
	ARGCOUNT => ARGCOUNT_LIST,
	DEFAULT => '.html',
    },
    global_map_uri => {
        ARGCOUNT => ARGCOUNT_HASH,
    },
    global_lib => {
        ARGCOUNT => ARGCOUNT_LIST,
	VALIDATE => \&_validate_lib,
    },
    global_internationalization => {
        ARGCOUNT => ARGCOUNT_NONE,
    },
    global_uri_mapping => {
        ARGCOUNT => ARGCOUNT_NONE,
    },
    global_framework => {
        VALIDATE => \&_validate_framework,
    },
    global_content_handler => {
        VALIDATE => \&_init_content_handler,
    },
    global_port => {
	VALIDATE => q"^\d+$",
    },
    global_hostname => {
	ARGCOUNT => ARGCOUNT_LIST,
    },
    # the following is experimental (i.e., for development) only
    global_include => {
        ARGCOUNT => ARGCOUNT_ONE,
        VALIDATE => \&_allow_include_file,
        ACTION => \&_include_file,
    },
    global_max_include_depth => {
        ARGCOUNT => ARGCOUNT_ONE,
        VALIDATE => q"^\d+$",
        ACTION => \&_set_include_depth,
    },
);

###
### end (config variables)
###

###
### public methods
###

sub config {
  return $config_for_define if $config_for_define and not ref $_[0];
  return $_[0] -> retrieve -> {config} unless ref $_[0];
  return $_[0] -> {config};
}

sub lh {
  return $_[0] -> retrieve -> {lh} unless ref $_[0];
  return $_[0] -> {lh};
}

sub location {
  return $_[0] -> retrieve -> {location} unless ref $_[0];
  return $_[0] -> {location};
}

sub register_component {
  my($self, $key, $priority, $comp) = @_;

  if($self_for_config) {
    $self_for_config -> {components} -> {$key} -> {'/' . $config_for_define -> global_function_set_base .'/' .  $comp} = $priority;
    $self_for_config -> {compcount}++;
  } else {
    $self = $self -> retrieve unless ref $self;
    $self -> {tcomponents} -> {$key} ||= +{ %{$self -> {components}->{$key}} };
    $self -> {tcomponents} -> {$key} -> {'/' . $config_for_define -> global_function_set_base .'/' .  $comp} = $priority;
  }
}

sub clear_components {
  my $self = shift;
  my $key = shift;

  $self -> {tcomponents} -> {$key} = { };
}

sub query_components {
  my $self = shift;
  my $key = shift;

  $self = $self -> retrieve;
  my $h;
  if(defined $self -> {tcomponents} -> {$key}) {
      $h =  $self -> {tcomponents} -> {$key};
  } else {
      $h =  $self -> {components} -> {$key} || {};
  }
  return[ sort { $h->{$a} <=> $h->{$b} }
	      keys %{$h} 
	];
}

#
# back to the public methods
#

sub _uri_to_comp {
  my($self, $c, $dbh, $uri) = @_;

  my $cache = $self -> query_cache("global_uri_map");
  return unless $cache;

  my $ret;
  unless(defined($ret = $cache->get($uri))) {
    unless($ret = $c -> global_map_uri  -> {$uri}) {
      if($dbh and not $ret) {
        # look for it in the sitemap
        eval {
            # do we need to escape such things as `%' ?
            my $sth = $dbh -> prepare_cached($c -> global_db_uri_map_select_comp);
            $sth -> execute($uri) 
                or die;
 
	    my $info = $sth -> fetchrow_arrayref;
            $ret = $info->[0] if $info;
	    $sth -> finish;
        };
      }
    }
    $cache->set($uri, $ret || "");
  }
  return $ret;
}

sub uri_to_comp {
  my($self, $uri) = @_;
  my($function, $path_info);
  my $c = $self -> config;
  my $dbh;

  eval {
    $dbh = $self -> query_dbh("global_db");
    $function = $self -> _uri_to_comp($c, $dbh, $uri);
    unless($function) {
      my @bits = split("/", $uri);
      my $u = "";
      $path_info = join("/", @bits);
      while(@bits) {
        $u .= "/" . shift @bits;
	my $f = $self -> _uri_to_comp($c, $dbh, $u);
	if($f) {
            $function = $f;
            $path_info = join("/", @bits);
        }
      }
    }
  };
  return ( $function, $path_info );
}

sub _score {
  my($u, $m) = @_;

  my $l = length($u);
  $l = length($m) if(length($m) < $l);

  my $i;
  for($i = 0; $i < $l; $i++) {
    return $i if substr($m, $i, 0) ne substr($u, $i, 0);
  }

  return $l;
}

sub _uniq (@) {
  my $p = "";

  grep { $p ne $_ ? ($p = $_, 1) : 0 } @_;
}

sub comp_to_uri {
  my($self, $comp) = @_;

  my $c = $self -> config;
  $self -> {uri_mapping} = { %{$c -> global_map_uri || {}} }
      unless $self -> {uri_mapping};

  my $comp_mapping;

  unless(defined $self -> {comp_mapping}) {
    $self -> {comp_mapping} = { };
    $comp_mapping = $self -> {comp_mapping};
    my $uri_mapping = $self -> {uri_mapping};
    foreach my $u (keys %{$uri_mapping}) {
      push @{$comp_mapping -> {$uri_mapping->{$u}} ||= []}, $u;
    }
  } else {
    $comp_mapping = $self -> {comp_mapping};
  }

  unless(exists $comp_mapping -> {$comp}) {
    eval {
      my $dbh = $self -> query_dbh("global_db")
        or croak qq:Unable to connect to database:;
      my $sth = $dbh -> prepare_cached($c -> global_db_uri_map_select_uri);
      $sth -> execute($comp)
            or croak qq:Unable to find $comp:;

      my $info;
      while($info = $sth -> fetchrow_arrayref) {
	  push @{$comp_mapping -> {$comp} ||= []}, $info->[0];
      }
      $sth -> finish;
    };
  }

  my @uris = @{$comp_mapping -> {$comp} || []};
  return unless @uris;

  my $m = $self -> note("function");    # main component
  push @uris, $m;
  @uris = _uniq sort @uris;

  # now we want the one before and after $m
  my $i;
  for($i = 0; $i < @uris; $i++) {
    last if $uris[$i] eq $m;
  }

  my $base = $self -> location;
  $base =~ s{/$}{};

  return $base . $uris[1] if($i == 0);
  return $base . $uris[-2] if($i == $#uris);

  return $base . $uris[$i-1] if _score($uris[$i-1], $m) > _score($uris[$i+1], $m);
  return $base . $uris[$i+1];
}

sub note {
  my($self, $key) = splice(@_, 0, 2);
  if(@_) { #storing
    $self -> {notes} -> {$key} = $_[0];
  } else { #retrieving
    return $self -> {notes} -> {$key};
  }
}

sub _query_const_dbh_var {
  my($self, $prefix, $var, $suffix) = @_;

  my $ret;
  my $c = $self -> config;
  my $psv = "$prefix$suffix$var";
  my $pv = "$prefix$var";

  $ret = $c -> $psv if $suffix && $c -> $psv;

  if($var eq '_database' && !@{$ret || []} ||
     $var eq '_option' && !keys %{$ret || {}} ||
     !$ret) {
    $ret = $c -> $pv;
  }

  return $ret;
}

sub query_dbh {
  my($self, $prefix, %options) = @_;

  # eventually, we want to support round-robin support for multiple
  # database definitions (not username/password or driver, just database)

  my $suffix = "";
  $suffix = "_const" unless $options{'Write'};
  unless($self -> {_dbh_cache}->{"$prefix:$suffix"}) {
    $self -> {_dbh_cache}->{"$prefix:$suffix"} = {
      driver => $self->_query_const_dbh_var($prefix, "_driver", $suffix),
      database => $self->_query_const_dbh_var($prefix, "_database", $suffix),
      username => $self->_query_const_dbh_var($prefix, "_username", $suffix),
      password => $self->_query_const_dbh_var($prefix, "_password", $suffix),
      options  => $self->_query_const_dbh_var($prefix, "_option", $suffix),
    };
    $self -> {_dbh_cache}->{"$prefix:$suffix"} -> {options} -> {PrintError} ||= 0;
    $self -> {_dbh_cache}->{"$prefix:$suffix"} -> {database} = 
      [ $self -> {_dbh_cache}->{"$prefix:$suffix"} -> {database} ]
        unless UNIVERSAL::isa($self -> {_dbh_cache}->{"$prefix:$suffix"} -> {database}, 'ARRAY');
  }


  return $self -> {_query_dbh_cache} -> {"$prefix:$suffix"}
      if $self -> {_query_dbh_cache} -> {"$prefix:$suffix"};

  my $info = $self -> {_dbh_cache}->{"$prefix:$suffix"};
  my $current = $info -> {database} -> [0];
  my $dbh = DBI -> connect("dbi:" . $info->{driver} . ":$current", 
			   $info->{username}, $info->{password},
			   { %{$info -> {options} || {}} });
  return $self -> {_query_dbh_cache} -> {"$prefix:$suffix"} = $dbh if defined $dbh;

  my $db = pop @{$info->{database}};
  unshift @{$info->{database}}, $db;
  while($db ne $current) {
    $dbh = DBI -> connect("dbi:" . $info->{driver} . ":$db",
			  $info->{username}, $info->{password},
			  { %{$info -> {options} || {}} });
    return $self -> {_query_dbh_cache} -> {"$prefix:$suffix"} = $dbh if defined $dbh;
    $db = pop @{$info->{database}};
    unshift @{$info->{database}}, $db;
  }
  return;
}

sub query_cache {
  my($self, $prefix) = @_;

  my $c = $self -> config;

  my $cache_type = "Cache::SizeAwareMemoryCache";
  $cache_type = "Cache::SizeAwareSharedMemoryCache" if $c -> get($prefix."_sharedmemory");
  return $cache_type -> new( {
      namespace => $c -> get($prefix."_namespace") || join(':', $c -> global_framework, $prefix),
      default_expires_in => $c -> get($prefix."_expiration") || "never",
      auto_purge_interval => $c -> get($prefix."_auto_purge_interval")
			  || "never",
      max_size => $c -> get($prefix."_size_limit")
	       || $Cache::SizeAwareCache::NO_MAX_SIZE,
    } );
}

###
### methods for wizards or internal use (undocumented)
###

sub clear_notes {
  delete $_[0] -> {notes};
}

sub lookup_function {
  my($self, $path) = @_;

  return $self -> {handler} -> file_to_path($self -> config -> global_function_set_base, $path);
}

###
### Apache handler
###

sub handler ($$) {
  my($class, $r) = @_;

  my $self = $class -> retrieve;
  unless($self) {
    my $uri = $r -> uri;
    if($uri =~ m{^/([^/]+)(/.*)}) {
      my $sessionid = $1;
      $r -> uri($2);
      $self = $class -> retrieve;
      if($self && $self -> config -> global_uri_sessions) {
	$self -> note("sessionid") = $sessionid;
      } else {
	$r -> uri("/$sessionid" . $r -> uri());
	return DECLINED;
      }
    }
  }

  my $c = $self -> config;

  my $loc = $self -> {location};

  return SERVER_ERROR unless $self->{handler};

  my $filename;
  my $path_info;
  my $function;
  my $uri = $r -> uri;

  if($c -> global_uri_mapping) {
    $uri .= "index.html" if $uri =~ m{/$};
    $uri =~ s{^$loc}{};

    $path_info = "";
    ($function, $path_info) = $self -> uri_to_comp($uri);

    $self -> note("function", $function);

    return DECLINED unless $function;

    $filename = $self -> lookup_function($function);
    $filename .= "/$path_info" if $path_info;
    $filename =~ s{//+}{/}g;
    $path_info = "";
  } else {
    $uri =~ s{^$loc}{};
    $function = $uri;
    $self -> note("function") = $function;
    $filename = $r -> filename;
    $path_info = $r -> path_info;
  }

  if($self -> {global_handle}) {
    my $ext;
    $ext = $1 if $uri =~ m{(\..*?)$};
    return DECLINED unless exists $self -> {global_handle} -> {$ext};
  }

  # send on its way
  $r -> filename($filename);
  $r -> path_info($path_info);
  $r -> uri($loc . $uri);

  $r -> handler("perl-script");
  #$r -> push_handlers(PerlHandler => sub { $self -> content_handler($r) });
  $r -> push_handlers(PerlHandler => \&content_handler);
  return OK;
}

sub content_handler ($$) {
  my($self, $r) = (__PACKAGE__ -> retrieve, Apache->request);

  #$self = $self -> new unless ref $self;

  # then run the component
  my $ret = SERVER_ERROR;
  my $c = $self -> config;
  if($c -> global_internationalization) {
    # search for appropriate Locale::Maketext module
    my $fr = $c -> global_framework;
    last unless $fr;
    my $f = $self -> note("function");
    # extract the function set
    $f =~ s{/.*$}{};
    my $module;
    foreach my $m (
	"Uttu::Framework::$fr\::L10N::Local::$f", 
	"Uttu::Framework::$fr\::L10N::$f", 
	"Uttu::Framework::$fr\::L10N::Local", 
	"Uttu::Framework::$fr\::L10N") {
	    eval { require $m; };
	    next if $@;
	    $module = $m;
    }
    eval {
      $self -> {lh} = $module -> get_handle();
    } if $module;
    $self -> {lh} = Uttu::L10N -> new if $@ || !$self -> {lh};
  }

  eval {
    push @INC, @{$c -> global_lib || []};
    push @INC, "$Uttu::Config::PREFIX/framework/".$c->global_framework."/lib" if $c->global_framework;

    $ret = $self -> {handler} -> handle_request($self, $r);
  };
  $self -> clear_notes;
  delete $self -> {_query_dbh_cache};
  delete $self -> {lh};
  return $ret;
}

###
### Configuration support routines
###

sub set_config {
    my($self, $c) = @_;
    $self -> {config} = $c;
}

###
### Apache Configuration Directives
###

sub UttuConf ($$$) {
  my($cfg, $param, $file) = @_;

  local(@INC) = @INC;

  $cfg -> {config_file} = $file;

  $file = Apache -> server_root_relative($file) unless $file =~ m{^/};

  $cfg -> {full_path_file} = $file;

  my $c = AppConfig -> new({
    GLOBAL => {
        DEFAULT => undef,
        ARGCOUNT => ARGCOUNT_ONE,
        EXPAND => EXPAND_ALL | EXPAND_WARN,
      },
  });

  eval {
    $c -> define(%variables);
    $config_for_define = $c;
    $self_for_config = $cfg;
    $c -> file($file);
    $config_for_define = undef;
    $self_for_config = undef;
    $cfg -> set_config($c);
  };
  eval {
    push @INC, @{$c -> global_lib || []};
    $c = AppConfig -> new({
      GLOBAL => {
        DEFAULT => undef,
        ARGCOUNT => 1,
        EXPAND => EXPAND_ALL | EXPAND_WARN,
      },
    });
    $c -> define(%variables);
    $config_for_define = $c;
    $self_for_config = $cfg;
    $c -> file($file);
    $config_for_define = undef;
    $self_for_config = undef;
    $cfg -> set_config($c);
  } if $@;
  warn "Errors reading configuration from $file: $_[0]\n" && die if $@;

  $c -> global_port($param -> server -> port || 80) unless $c -> global_port;
  $c -> global_hostname($param -> server -> server_hostname) unless @{$c -> global_hostname || []};

  # cache these in convenient hash form
  $cfg -> {global_handle} = { };
  @{$cfg -> {global_handle}}{@{$c -> global_handle || []}} = ( );

  my $handler_class = "Uttu::Handler::" . $c -> global_content_handler;

  $cfg -> {handler} = $handler_class -> config($c, $param);

  if($c -> global_internationalization) {
    eval {
      require Locale::Maketext;
    };
    if($@) {
      $c -> global_internationalization(0);
    }
  }

  my $p = $c->global_port;
  foreach my $h (@{$c -> global_hostname || []}) {
    $configs{"$h:$p"}->{$param->path()} = $cfg;
  }
  $cfg -> {location} = $param->path();
}

sub Alias ($$$$) {
  my ($cfg, $param, $from, $to) = @_;

  if($param -> info) {
    push @{$cfg -> {_alias}}, qr/$from/
      unless grep /$from/, @{$cfg -> {_alias_match}};
  } else {
    push @{$cfg -> {_alias}}, $from
      unless grep /$from/, @{$cfg -> {_alias}};
  }

  return DECLINE_CMD;
}

sub SetHandler ($$$) {
  my ($cfg, $param, $arg) = @_;

  push @{$cfg -> {_sethandler}}, $param -> path() if $param -> path();

  return DECLINE_CMD;
}

sub SERVER_CREATE {
  my $class = shift;
  my %self = ();

  for my $entry (qw{_alias _alias_match _location _location_match _sethandler}) {
    $self{$entry} = [];
  }

  $self{_uttu} = { };

  return bless \%self => $class;
}

sub SERVER_MERGE {
  my ($parent, $current) = @_;
  my %new = (%$parent, %$current);

  return bless \%new, ref($parent);
}

1;
