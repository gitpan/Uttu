package Uttu;

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

#BEGIN {
#  delete @INC{grep m{Uttu/}, keys %INC};
#}

use AppConfig                   qw- :argcount :expand -;
use Apache::Constants           qw- :common DECLINE_CMD -;
use Cache::SizeAwareMemoryCache ();
use Carp;
use Digest::MD5                 ();
use DynaLoader                  ();
use File::Glob                  qw: bsd_glob :;
use File::Spec                  ();
use File::Spec::Unix            ();
use Uttu::Tools qw: define_cache define_db server_root_relative :;
use Uttu::Config;
use strict;
use warnings;

require 5.006;

use Data::Dumper;

use vars qw: %variables %configs :;

our $VERSION = "0.04";

{ no warnings;
our $REVISION = sprintf("%d.%d", q$Id: Uttu.pm,v 1.11 2002/08/06 19:23:25 jgsmith Exp $ =~ m{(\d+).(\d+)});
}

my $self_for_config;
my $config_for_define;
my $self_global;

# we want to be usable outside the mod_perl environment
BEGIN {
  if($ENV{MOD_PERL}) {
    no strict;

    eval {
        require Apache;
        require Apache::ModuleConfig;
    };

    eval { require mod_perl; };
    if ($mod_perl::VERSION >= 1.99) {
      warn "Uttu has not been tested with mod_perl 2.0 (or beta versions thereof)\n";
    }     

    require Apache::DBI;
    Apache::DBI -> import();
  }
}

if($ENV{MOD_PERL}) {
  if($mod_perl::VERSION < 1.99) {
    our @ISA = qw(DynaLoader);
    __PACKAGE__ -> bootstrap($VERSION);
  } else {
    # register with Apache::Hook :)
    Apache::Hook -> add(PerlTransHandler => \&handler);
    # we still need to register the commands...
  }
}

require DBI;
DBI -> import();

require DBIx::Abstract;

sub retrieve {
    my $class = shift;
    return $class if ref $class;

    my $r;
    my $self;
    eval {
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
                    return if grep {length($_) <= $luri && $uri =~ /^$_/} @a; #(@a, @as, @sh);
                    $self = $cs->{$roots[0]} if @roots;
    
                }
            }
        }
    };

    if($@ || !$r) {
        if($self_for_config) {
            $self = $self_for_config;
        } elsif($self_global) {
            $self = $self_global;
        }   
    }
    return $self;
}

sub make_default {
  my $self = shift;
  return unless ref $self;
  return ( ($self_global, $self_global = $self)[0] );
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
    my $file = server_root_relative($value);
    open my $fh, "<", $file or warn "Unable to read $file\n";
    my $p = <$fh>;
    close $fh;
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

      warn $@ if $@;

      return unless $ret;

      eval { $ret = $framework -> init(); };
      warn $@ if $@;

      return unless $ret;
      return if $@;

      eval { $ret = $framework -> init_config($config_for_define); };
      warn $@ if $@;

      return unless $ret;
      return if $@;
    }
    push @INC,  "$Uttu::Config::PREFIX/framework/$value/lib";
    return 1;
}

sub _compile_where {
    my($self, $variable, $value) = @_;
    return 1 unless UNIVERSAL::isa($value, 'CODE');
    $self -> set($variable, eval "sub { my \$u = shift; $value; };");
    return 1;
}

sub _validate_lib {
    my($variable, $value) = @_;

    my $l = server_root_relative($value);
    return unless -d $l;

    push @INC, $l;
    return 1;
}

sub _validate_where {
    my($variable, $value) = @_;

    eval "sub { my \$u = shift; $value; };";
    return 1 unless $@;
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
        $self -> file(server_root_relative($value));
        $Uttu::Config::curr_include_depth--;
    }
    $self -> set("global_max_include_depth", $Uttu::Config::max_include_depth);
}

sub _set_include_depth {
    my($self, $variable, $value) = @_;

    $Uttu::Config::max_include_depth = $value;
}
    

Uttu -> define(
    define_db("global_db"),
    define_cache("global_uri_map"),
    global_db_uri_map_field_uri => {
        DEFAULT => 'uri',
    },
    global_db_uri_map_field_file => {
        DEFAULT => 'file',
    },
    global_db_uri_map_table => {
        DEFAULT => 'functions',
    },
    global_db_uri_map_where => {
        VALIDATE => \&_validate_where,
        ACTION => \&_compile_where,
    },
    global_internationalization => {
        ARGCOUNT => ARGCOUNT_NONE,
        ALIAS => 'global_i18n',
        DEFAULT => 1,
    },
    global_function_set_base => {
        DEFAULT => "sets",
    },
    global_index => {
        ARGCOUNT => ARGCOUNT_ONE,
        DEFAULT => 'index.html',
    },
    global_handle => {
        ARGCOUNT => ARGCOUNT_LIST,
        DEFAULT => '.html',
    },
    global_translate_uri => {
        ARGCOUNT => ARGCOUNT_LIST,
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
    global_server_root => {
        ARGCOUNT => ARGCOUNT_ONE,
        DEFAULT => File::Spec->rootdir(),
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

## __where and __where_hash are taken from DBIx::Abstract

sub _key_from_where {
  my($self, $where) = @_;

  my $key = $self -> __where($where);

  return Digest::MD5::md5_hex($key);
}

sub __where {
  my($self,$where,$int) = @_;
  my $result='';
  my @bind_params;
  $int ||= 0;

  die "Uttu WHERE parser iterated too deep, circular reference in where clause?\n"
    if $int > 20;

  if (UNIVERSAL::isa($where, 'ARRAY')) {
    foreach (@$where) {
      if (ref($_) eq 'HASH') {
        my($moreres,@morebind) = $self->__where_hash($_);
        $result .= "($moreres)" if $moreres;
        push(@bind_params,@morebind);
      } elsif (ref($_) eq 'ARRAY') {
        my($moreres,@morebind) = $self->__where($_,$int+1);
        $result .= "($moreres)" if $moreres;
        push(@bind_params,@morebind);
      } else {
        $result .= " $_ ";
      }
    }
  } elsif (UNIVERSAL::isa($where, 'HASH')) {
    my($moreres,@morebind) = $self->__where_hash($where);
    $result = $moreres;
    @bind_params = @morebind;
  } else {
    $result = $where;
  }
  if ($result) {
    if($int) {
      return $result, @bind_params;
    }
    return join($;, $result,@bind_params);
  } else {
    return '';
  }
}

sub __where_hash {
  my($self,$where) = @_;
  my $ret;
  my @bind_params;

  foreach (keys(%$where)) {
    if ($ret) { $ret .= ' AND ' }
    $ret .= "$_ ";
    if (ref($$where{$_}) eq 'ARRAY') {
      $ret .= $$where{$_}[0].' ';
      if (ref($$where{$_}[1]) eq 'SCALAR') {
        $ret .= ${$$where{$_}[1]};
      } else {
        $ret .= '?';
        push(@bind_params,$$where{$_}[1]);
      }
    } else {
      if (defined($$where{$_})) {
        $ret .= '=';
        if (ref($$where{$_}) eq 'SCALAR') {
          $ret .= ${$$where{$_}};
        } else {
          $ret .= '?';
          push(@bind_params,$$where{$_});
        }
      } else {
        $ret .= 'IS NULL';
      }
    }
  }
  if ($ret ne '()') {
    return $ret,@bind_params;
  } else {
    return '';
  }
}


sub _uri_to_comp {
  my($self, $c, $dbh, $uri) = @_;

  my $cache = $self -> query_cache("global_uri_map");
  return unless $cache;

  my $ret;
  my $key;
  my $where = $c -> global_db_uri_map_where || sub { };
  $where = $where -> ($self);

  if(defined $where and 
        (UNIVERSAL::isa($where, 'HASH') || 
         UNIVERSAL::isa($where, 'ARRAY'))) 
    {
    $where = [ {
      $c -> global_db_uri_map_field_uri => $uri,
    }, 'AND', $where ];
    $key = $self -> _key_from_where($where);
  } else {
    $where = {
      $c -> global_db_uri_map_field_uri => $uri,
    };
    $key = $uri;
  }

  unless(defined($ret = $cache->get($key))) {
    unless($ret = $c -> global_map_uri  -> {$uri}) {
      if($dbh and not $ret) {
        # look for it in the sitemap
        eval {
          my @info = $dbh -> select_one_to_array({
            fields => [ $c -> global_db_uri_map_field_file ],
            table  => [ $c -> global_db_uri_map_table ],
            where  => $where,
          });
          if(@info) {
            # we want to modify $key to reflect the $where
            $ret = $info[0] if @info;
          }
        };
      }
    }
    $cache->set($key, $ret || "");
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

  my $key;
  my $where = $c -> global_db_uri_map_where || sub { };
  $where = $where -> ($self);

  if(defined $where and
        (UNIVERSAL::isa($where, 'HASH') ||
         UNIVERSAL::isa($where, 'ARRAY')))
    {
    $where = [ {
      $c -> global_db_uri_map_field_file => $comp,
    }, 'AND', $where ];
    $key = $self -> _key_from_where($where);
  } else {
    $where = {
      $c -> global_db_uri_map_field_file => $comp,
    };
    $key = $comp;
  }

  my $dbh = $self -> query_dbh("global_db")
    or carp qq:Unable to connect to database:;


  unless(exists $comp_mapping -> {$comp}) {
    eval {
      $dbh -> select({
        fields => [ $c -> global_db_uri_map_field_uri ],
        table  => [ $c -> global_db_uri_map_table ],
        where  => $where,
      });
      if($dbh -> rows) {
        my $info;
        while($info = $dbh -> fetchrow_arrayref) {
          push @{$comp_mapping -> {$comp} ||= []}, $info->[0];
        }
        $dbh -> finish;
      }
    };
    warn "$@\n" if $@;
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

sub comp_to_rel_uri {
  my($self, $comp) = @_;

  my $r = Apache -> request;

  my $uri = $self -> comp_to_uri($comp);

  my $loc = $r -> uri;
  $loc =~ s{/[^/]+$}{};

  return File::Spec::Unix->abs2rel($uri, $loc);
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

  if($var eq '_host' && !@{$ret || []} ||
     $var eq '_option' && !keys %{$ret || {}} ||
     !$ret) {
    $ret = $c -> $pv;
  }

  return $ret;
}

sub query_dbh {
  my($self, $prefix, %options) = @_;

  # eventually, we want to support round-robin support for multiple
  # database definitions (not username/password or driver, just host/port)

  my $suffix = "";
  my $use_db_global_as_default = 1;
  $suffix = "_const" unless $options{'Write'};
  $use_db_global_as_default = 0 if $options{'NoDefault'};

  unless($self -> {_dbh_cache}->{"$prefix:$suffix"}) {
    $self -> {_dbh_cache}->{"$prefix:$suffix"} = {
      driver => ($self->_query_const_dbh_var($prefix, "_driver", $suffix) ||
                ($use_db_global_as_default ? $self->_query_const_dbh_var("global_db", "_driver", $suffix) : undef )),
      database => ($self->_query_const_dbh_var($prefix, "_database", $suffix) ||
                ($use_db_global_as_default ? $self->_query_const_dbh_var("global_db", "_database", $suffix) : undef )),
      host     => ($self->_query_const_dbh_var($prefix, "_host", $suffix) ||
                ($use_db_global_as_default ? $self->_query_const_dbh_var("global_db", "_host", $suffix) : undef )),
      username => ($self->_query_const_dbh_var($prefix, "_username", $suffix) ||
                ($use_db_global_as_default ? $self->_query_const_dbh_var("global_db", "_username", $suffix) : undef )),
      password => ($self->_query_const_dbh_var($prefix, "_password", $suffix) ||
                ($use_db_global_as_default ? $self->_query_const_dbh_var("global_db", "_password", $suffix) : undef )),
      options  => ($self->_query_const_dbh_var($prefix, "_option", $suffix) ||
                ($use_db_global_as_default ? $self->_query_const_dbh_var("global_db", "_option", $suffix) : undef )),
    };
    $self -> {_dbh_cache}->{"$prefix:$suffix"} -> {options} -> {PrintError} ||= 0;
    $self -> {_dbh_cache}->{"$prefix:$suffix"} -> {host} = 
      [ $self -> {_dbh_cache}->{"$prefix:$suffix"} -> {host} ]
        unless UNIVERSAL::isa($self -> {_dbh_cache}->{"$prefix:$suffix"} -> {host}, 'ARRAY');
  }


  eval {
    $self -> {_query_dbh_cache} -> {"$prefix:$suffix"} -> ensure_connection();
    return $self -> {_query_dbh_cache} -> {"$prefix:$suffix"};
  } if $self -> {_query_dbh_cache} -> {"$prefix:$suffix"};


  my $info = $self -> {_dbh_cache}->{"$prefix:$suffix"};
  my $current = $info -> {host} -> [0];
  my $dbh = DBIx::Abstract -> connect({
      dsn => join(":", "dbi", $info->{driver}, 
          ($info->{database} =~ /=/ ? "" : "database=") . $info->{database}, (defined($current) ? "host=".$current : ())),
      user => $info->{username}, 
      password => $info->{password},
    },
    { useCached => 1,
      loglevel => 6,
      logfile => "/tmp/uttu_sql_log",
      %{$info -> {options} || {}} 
    }
  );
  return $self -> {_query_dbh_cache} -> {"$prefix:$suffix"} = $dbh if defined $dbh;

  unshift @{$info->{host}}, $current;
  my $host = pop @{$info->{host}};
  unshift @{$info->{host}}, $host;
  while($host ne $current) {
    $dbh = DBIx::Abstract -> connect({
        dsn => join(":", "dbi", $info->{driver}, "database=" .$info->{database}, "host=$host"),
        user => $info->{username}, 
        password => $info->{password},
      },
      { useCached => 1,
        %{$info -> {options} || {}
      } }
    );
    
    return $self -> {_query_dbh_cache} -> {"$prefix:$suffix"} = $dbh if defined $dbh;
    unshift @{$info->{host}}, ($host = pop @{$info->{host}});
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
  # we really only want to do this if global_uri_sessions is >0 and
  # the length of the first part of the uri is the length of
  # global_uri_sessions
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

  return DECLINED unless $self;

  my $c = $self -> config;

  my $loc = $self -> {location};

  return SERVER_ERROR unless $self->{handler};

  my $filename;
  my $path_info;
  my $function;
  my $uri = $r -> uri;

  if($c -> global_uri_mapping) {
    $uri .= $c -> global_index if $uri =~ m{/$};
    $uri =~ s{^$loc}{};

    $path_info = "";
    ($function, $path_info) = $self -> uri_to_comp($uri);

    $self -> note("function", $function);

    return DECLINED unless $function;

    $filename = $self -> lookup_function($function);
    return DECLINED unless $function;
    $filename .= "/$path_info" if $path_info;
    $filename =~ s{//+}{/}g if $filename;
    $path_info = "";
  } else {
    $uri =~ s{^$loc}{};
    $function = $uri;
    $self -> note("function", $function);
    $filename = $r -> filename;
    $path_info = $r -> path_info;
  }

  my $ext = '';
  if($self -> {global_handle} || $self -> {global_translate_uri}) {
    $ext = $1 if $uri =~ m{(\..*?)$};
    return DECLINED unless exists $self -> {global_handle} -> {$ext} || 
                           exists $self -> {global_translate_uri} -> {$ext};
  } else {
    return DECLINED;
  }

  # send on its way
  if(defined $filename) {
      $r -> filename($filename);
      $r -> path_info($path_info);
      $r -> uri($loc . $uri);
  }

  if(exists $self -> {global_handle} -> {$ext}) {
    $r -> handler("perl-script");
    $r -> push_handlers(PerlHandler => \&content_handler);
  }
  return OK if $filename;
  return DECLINED;
}

sub content_handler ($$) {
  my($self, $r) = (__PACKAGE__ -> retrieve, Apache->request);

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
    #local(@INC) = @INC;
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

# used to read in the config file
sub config {
  my $self = shift;

  if(!@_) {
    return $config_for_define if $config_for_define and not ref $self;
    return $self -> retrieve -> {config} unless ref $self;
    return $self -> {config};
  }

  my $class = ref $self || $self;

  $self = bless { } => $class unless ref $self;

  local(@INC) = @INC;

  my @files;

  my $param = shift if $ENV{MOD_PERL};

  $self -> {config_file} = [ @_ ];

  @files = map { server_root_relative $_ } @_;

  $self -> {full_path_file} = [ @files ];

  my $c = AppConfig -> new({
    GLOBAL => {
        DEFAULT => undef,
        ARGCOUNT => ARGCOUNT_ONE,
        EXPAND => EXPAND_ALL | EXPAND_WARN,
      },
  });
  my @cfg_defines;

  foreach my $k (keys %{$self -> {_defines} || {}}) {
    push @cfg_defines, $k;
    if(UNIVERSAL::isa($self -> {_defines}->{$k}, 'ARRAY')) {
      push @cfg_defines, { ARGCOUNT => ARGCOUNT_LIST, EXPAND => EXPAND_ALL | EXPAND_WARN };
    } elsif(UNIVERSAL::isa($self -> {_defines}->{$k}, 'HASH')) {
      push @cfg_defines, { ARGCOUNT => ARGCOUNT_HASH, EXPAND => EXPAND_ALL | EXPAND_WARN };
    } else {
      push @cfg_defines, { ARGCOUNT => ARGCOUNT_ONE, EXPAND => EXPAND_ALL | EXPAND_WARN };
    }
  }


  eval {
    $c -> define(%variables, @cfg_defines);
    $config_for_define = $c;
    $self_for_config = $self;
    foreach my $k (keys %{$self -> {_defines} || {}}) {
      $c -> set($k, $self -> {_defines}->{$k});
    }
    $c -> file(@files);
    $config_for_define = undef;
    $self_for_config = undef;
    $self -> set_config($c);
  };
  warn "Errors reading configuration: $@\n" && die if $@;
  eval {
    push @INC, @{$c -> global_lib || []};
    $c = AppConfig -> new({
      GLOBAL => {
        DEFAULT => undef,
        ARGCOUNT => 1,
        EXPAND => EXPAND_ALL | EXPAND_WARN,
      },
    });
    $c -> define(%variables, @cfg_defines);
    $config_for_define = $c;
    $self_for_config = $self;
    foreach my $k (keys %{$self -> {_defines} || {}}) {
      $c -> set($k, $self -> {_defines}->{$k});
    }
    $c -> file(@files);
    $config_for_define = undef;
    $self_for_config = undef;
    $self -> set_config($c);
  } if $@;
  warn "Errors reading configuration: $@\n" && die if $@;

  # cache these in convenient hash form
  $self -> {global_handle} = { };
  @{$self -> {global_handle}}{@{$c -> global_handle || []}} = ( );
  $self -> {global_translate_uri} = { };
  @{$self -> {global_translate_uri}}{@{$c -> global_translate_uri || []}} = ( );

  #warn Data::Dumper -> Dump([$c]) . "\n";

  if($c -> global_content_handler) {
      my $handler_class = "Uttu::Handler::" . $c -> global_content_handler;

      $self_for_config = $self;
      $self -> {handler} = $handler_class -> config($c, $param);
      $self_for_config = undef;
  } else {
      warn "No content handler specified.\n";
  }

  if($c -> global_internationalization) {
    eval {
      require Locale::Maketext;
    };
    if($@) {
      $c -> global_internationalization(0);
    }
  }

  $self -> {config} = $c;

  $self -> make_default unless $self_global;

  return $self;
}

###
### Apache Configuration Directives
###

# we want to be able to list mutliple files on the command line
sub UttuConf ($$$;*) {
  my($cfg, $param, $file, $fh) = @_;

  my @files;

  # "..." or ...(no spaces)
  @files = grep { defined $_ } ($file =~ m{"((?:\\"|[^"]+)*)"|([^"\s]+)}g);

  my $c = $cfg -> config($param, @files) -> config;

  $c -> global_port($param -> server -> port || 80) unless $c -> global_port;
  $c -> global_hostname($param -> server -> server_hostname) unless @{$c -> global_hostname || []};

  my $p = $c->global_port;
  foreach my $h (@{$c -> global_hostname || []}) {
    $configs{"$h:$p"}->{$param->path()} = $cfg;
  }
  $cfg -> {location} = $param->path();
}

sub UttuDefine ($$$$) {
  my($cfg, $param, $var, $val) = @_;

  return unless ref $cfg;

  if(ref $cfg->{_defines}->{$var}) {
    warn "$var previously defined by UttuDefineList or UttuDefineMap.\n";
    die;
  }

  $cfg->{_defines}->{$var} = $val;
}

sub UttuDefineList ($$@;@) {
  my($cfg, $param, $var, $val) = @_;

  return unless ref $cfg;

  if(exists $cfg->{_defines}->{$var} && !UNIVERSAL::isa($cfg->{_defines}->{$var}, 'ARRAY')) {
    warn "$var previously defined by UttuDefine or UttuDefineMap.\n";
    die;
  }

  push @{$cfg -> {_defines} -> {$var} ||= []}, $val;
}

sub UttuDefineMap ($$$$$) {
  my($cfg, $param, $var, $key, $val) = @_;

  return unless ref $cfg;

  if(exists $cfg->{_defines}->{$var} && !UNIVERSAL::isa($cfg->{_defines}->{$var}, 'HASH')) {
    warn "$var previously defined by UttuDefine or UttuDefineList.\n";
    die;
  }

  $cfg -> {_defines} -> {$var} -> {$key} = $val;
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
  $self{_defines} = { };

  return bless \%self => $class;
}

sub SERVER_MERGE {
  my ($parent, $current) = @_;
  my %new = (%$parent, %$current);

  return bless \%new, ref($parent);
}

1;
