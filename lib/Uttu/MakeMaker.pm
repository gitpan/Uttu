package Uttu::MakeMaker;

use ExtUtils::MakeMaker ();
use Uttu::Config;
use Exporter;
use File::Find ();
use File::Copy ();
use File::Spec ();
use File::Path ();
use Data::Dumper;
use Carp;

use vars qw: $VERSION $REVISION @ISA @options :;

$VERSION = 0.01;

$REVISION = sprintf("%d.%d", q$Id: MakeMaker.pm,v 1.3 2002/03/20 17:53:34 jgsmith Exp $ =~ m{(\d+).(\d+)});


# ExtUtils::MakeMaker >= 5.49_01 (might) require the following
eval {
  require ExtUtils::MM;
} if $ExtUtils::MakeMaker::VERSION >= 5.49_01;

# insert ourselves into the inheritence chain
# @MM::ISA is setup by ExtUtils::MakeMaker (or ExtUtils::MM for later
#   MakeMakers)
# if the following doesn't work, then the Makefile won't get generated
# properly - however, MakeMaker is in the process of refactoring and will
# probably end up similar to Module::Build - probably should investigate
# using Module::Build (as it becomes stable)
# We'll just have to track MakeMaker for now

@ISA = @MM::ISA;
@MM::ISA = __PACKAGE__;

@options = qw:
    FCTN
    FCTN_DIR
    FCTNDIRS
    FRAMEWORK
    PREREQ_FRAMEWORK
    PREREQ_FCTN
             :;

# this may change in future versions of MakeMaker - good as of v5.4301
# (perl 5.005_02) and v5.4901 (post perl 5.6.1)
# worst case is spurious warnings:
#    '$mmkey' is not a known MakeMaker parameter name.
@ExtUtils::MakeMaker::Recognized_Att_Keys{@options} = (1) x @options;

sub import {
  ExtUtils::MakeMaker -> export_to_level(1, @_);
}

sub export_to_level {
  my($class, $level) = splice(@_, 0, 2);

  ExtUtils::MakeMaker -> export_to_level($level+1, @_);
}

sub new {
  my($class, $self) = @_;

  $self = { } unless defined $self;

  my %config;

  foreach my $k (@options) {
    $config{$k} = $ENV{$k};
  }
 
  my @replacement_args;

  # now get stuff from command line to override environment
  foreach (@ARGV) {
    if (/^(.+?)=(.+)/ && exists $config{$1}) {
      $config{$1} = $2;
    } else {
      push(@replacement_args, $_);
    }
  }
   
  # replace with any args we didn't need
  @ARGV = @replacement_args;

  if(defined($config{PREREQ_FRAMEWORK})) {
    $config{PREREQ_FRAMEWORK} = [ (split(/\s+/, $config{PREREQ_FRAMEWORK}, 2), 0)[0..1] ];
  }

  if(defined($config{FCTNDIRS})) {
    $config{FCTNDIRS} = [ (split(/\s+/, $config{FCTNDIRS}, 2), 0)[0..1] ];
  }

  foreach my $k (@options) {
    $self->{$k} = $config{$k} || $self->{$k};
  }

  # do we want to allow frameworks to inherit from other frameworks?  kinda
  # weird in a way :/ (considering all the different files that go into
  # making a framework.)  Not for now.

  if($self->{PREREQ_FRAMEWORK}) { # we have a function set
    my $framework = "Uttu::Framework::$$self{PREREQ_FRAMEWORK}[0]";

    $self->{PREREQ_PM}->{$framework} = $self->{PREREQ_FRAMEWORK}[1];

    $self->{PREFIX} ||= File::Spec->catfile($Uttu::Config::PREFIX, "functionsets", $framework);
    $self->{LIB} ||= File::Spec -> catfile($self->{PREFIX}, "lib");

    push @INC, $self->{LIB};
    push @INC, File::Spec -> catfile($Uttu::Config::PREFIX, "framework", $framework, "lib");
    push @INC, File::Spec -> catfile($Uttu::Config::PREFIX, "functionsets", $framework, "lib");

    if($self->{PREREQ_FCTN}) {
      foreach my $p (keys %{$self->{PREREQ_FCTN}||{}}) {
        $self->{PREREQ_PM}->{"${framework}::$p"} = $self->{PREREQ_FCTN} -> {$p};
      }
    }
  } else { # we have a framework
    my $framework = $self->{FRAMEWORK} || $self->{NAME} || caller;

    if($framework =~ m{^Uttu::Framework::[^:]+$}) {
      $framework =~ s{^.*::}{};

      $self->{PREFIX} ||= File::Spec -> catfile($Uttu::Config::PREFIX, "framework", $framework);
      $self->{LIB} ||= File::Spec -> catfile($self->{PREFIX}, "lib");
      $self->{FRAMEWORK} ||= $framework;

    } else { # we really have a function set

      $framework =~ s{^(Uttu::Framework::(.+?))::.*}{$1};
      $self -> {FRAMEWORK} = $2;
      $self->{PREREQ_FRAMEWORK} = [ $framework => 0 ];
      $self->{PREREQ_PM}->{$framework} = 0;

      $self->{PREFIX} ||= File::Spec -> catfile($Uttu::Config::PREFIX, "functionsets", $framework);
      $self->{LIB} ||= File::Spec -> catfile($self->{PREFIX}, "lib");

      push @INC, $self -> {LIB};
      push @INC, File::Spec -> catfile($Uttu::Config::PREFIX, "framework", $framework, "lib");
      push @INC, File::Spec -> catfile($Uttu::Config::PREFIX, "functionsets", $framework, "lib");

      if($self->{PREREQ_FCTN}) {
	foreach my $p (keys %{$self->{PREREQ_FCTN}||{}}) {
	  $self->{PREREQ_PM}->{"${framework}::$p"} = $self->{PREREQ_FCTN} -> {$p};
	}
      }
    }
  }

  foreach my $k (@options) {
    delete $self->{$k} unless defined $self->{$k};
  }

  $self -> {depend} -> {pm_to_blib} .= " uttu_postamble";
  $self -> {depend} -> {test_}      .= " uttu_test";

  push @{$self -> {PMLIBDIRS} ||= []}, qw: lib l10n sets :;

  return $class -> SUPER::new($self);
}

sub post_initialize {
  my $self = shift;

  if(exists $self -> {PREREQ_FRAMEWORK}) {
    $self -> post_initialize_FUNCTIONSET;
  } else {
    $self -> post_initialize_FRAMEWORK;
  }

  $self -> SUPER::post_initialize(@_);
}

sub post_initialize_FUNCTIONSET {
  my $self = shift;

  my $sep = File::Spec -> catfile("x","x");
  $sep =~ m{^x(.*)x$};
  $sep = $1;

  my $setdir = $self -> {FCTNDIRS} || [ qw{ . sets } ];
  my @sets = ( );

  # we want all directories which have a .pm file associated with them (if
  #    looking in '.')

  foreach my $d (@{$setdir || []}) {
    if($d eq '.') {
      File::Find::find 
        sub {  
          if(!m{$sep} && -d $_ && (-f "$_.pm" || -f "$_$sep$_.pm")) {
	    push @sets, $_;
          }
        }, $d;
    } else {
      File::Find::find
        sub {
          if(!m{$sep} && -d $_) {
            push @sets, $_;
          }
        }, $d;
    }
  }

  warn "Sets found in: " . join("; ", @sets) . "\n";

  # need to make "sets" configurable
  $self -> {INSTSETDIR} ||= File::Spec -> catfile($$self{PREFIX}, "sets");

  # we have .pm files to install in lib/ and other files for sets/

}

sub post_initialize_FRAMEWORK {
  my $self = shift;

  my $setdir = $self -> {FCTNDIRS} || [ 'sets' ];
  my $sep = File::Spec -> catfile("x","x");
  $sep =~ m{^x(.*)x$};
  $sep = $1;

  # need to make "sets" configurable
  $self -> {INSTSETDIR} ||= File::Spec -> catfile($$self{PREFIX}, "sets");

  foreach my $d (@{$setdir || []}) {
    File::Find::find sub { $self -> {SETS} -> {$File::Find::name} = $d unless -d $_ }, $d;
  }
  foreach my $s (keys %{$self -> {SETS}}) {
    my $d = $self -> {SETS} -> {$s};
    delete $self -> {SETS} -> {$s};
    next if $s =~ /\.pm$/;
    my $ss = $s;
    $ss =~ s{^$d$sep*}{};
    $self -> {SETS} -> {$s} = File::Spec -> catfile("\$(INSTSETDIR)", $ss);
    warn "(d = $d) $s => $ss\n";
  }

  my $supportdir = $self -> {SUPPORTDIR} || [ 'support' ];
  foreach my $d (@{$supportdir || []}) {
    File::Find::find sub { $self -> {SUPPORT} -> {$File::Find::name} = $d unless -d $_ }, $d;
  }
  foreach my $s (keys %{$self -> {SUPPORT}}) {
    my $d = $self -> {SUPPORT} -> {$s};
    delete $self -> {SUPPORT} -> {$s};
    my $ss = $s;
    $ss =~ s{^$d$sep*}{};
    $self -> {SUPPORT} -> {$s} = File::Spec -> catfile("\$(PREFIX)", $ss);
    warn "(d = $d) $s => $ss\n";
  }

  my $l10ns = File::Spec -> catfile("\$(INST_LIBDIR)", "l10n") . $sep;
  my $l10nd = File::Spec -> catfile("\$(INST_LIBDIR)", $$self{FRAMEWORK}, "L10N") . $sep;
  foreach my $k (grep m{^l10n$sep}, keys %{$self -> {PM}}) {
    $self -> {PM} -> {$k} =~ s{^$l10ns}{$l10nd};
  }
  if($self -> {PM} -> {$$self{FRAMEWORK}.".pm"}) {
    $self -> {PM} -> {$$self{FRAMEWORK}.".pm"} = File::Spec -> catfile("\$(INST_LIBDIR)", "$$self{FRAMEWORK}.pm");
  }
  foreach my $d (@{$setdir || []}) {
    foreach my $k (grep m{^$d$sep}, keys %{$self -> {PM}}) {
      if($k =~ m{^$d$sep.*?$sep(.*)\.pm$}) {
        $self -> {PM} -> {$k} = File::Spec -> catfile("\$(INST_LIBDIR)", $$self{FRAMEWORK}, "$1.pm");
      } else {
	delete $self -> {PM} -> {$k};
      }
    }
    delete @{$self -> {MAN3PODS} || {}}{grep m{^$d$sep}, keys %{$self -> {MAN3PODS}}};
  }

  # now to look for function set pages...
  # sets/xxx/page -> $prefix/framework/$framework/sets/xxx/page
  # sets/xxx/xxx.pm -> \$(INST_LIBDIR)/$$self{FRAMEWORK}/xxx.pm"
  warn Data::Dumper -> Dump([$self]). "\n";
}

sub clean {
  my($self, %attribs) = @_;

  # add files to $attribs{FILES} here
  $attribs{FILES}  = "" unless defined $attribs{FILES};

  $attribs{FILES} = join(" ", ($attribs{FILES} ? ($attribs{FILES}) : ()), qw: ./locale ./t/conf/uttu.conf ./t/conf/extra.conf.in :);

  return $self -> SUPER::clean(%attribs);
}

sub constants {
  my $self = shift;

  my @m = $self -> SUPER::constants(@_);

  # here is where we can add constants
  # like: FRAMEWORK = $framework
  push @m, <<1HERE1;

# --- constants for Uttu ---
FRAMEWORK = $$self{FRAMEWORK}
FCTN_DIR  = $$self{FCTN_DIR}

INSTSETDIR = $$self{INSTSETDIR}

1HERE1

  push @m, "SET_INST = " . join(" \\\n\t", %{$self -> {SETS}}) . "\n\n";

  push @m, "SUPPORT_INST = " . join(" \\\n\t", %{$self -> {SUPPORT}}) . "\n\n";

  join("", @m);
}


#
# need rules for gettext stuff, etc
#
# set/<funcset>/        -> set/<funcset>/
# lib/  <handled by ExtUtils stuff>
# conf/uri_map             -> should be in the form of map_uri <uri> <funcset>/<file>
# conf/uttu.conf.in           -> combined with navigation and path info => uttu.conf suitable for testing
# t/                           -> testing handled by ExtUtils

#sub c_o {
#  my $self = shift;
#
#  my @m = $self -> SUPER::c_o(@_);
#
#  push @m, <<1HERE1;
#1HERE1
#
#  join '', @m;
#}

# FCTN => hashref of set/<funcset>/ directories to be installed pointing to installed location
#         this overrides FCTNDIRS
# FCTNDIRS => array ref of directories which contain <funcset>s

# FCTN_FILTER => program similar to PM_FILTER

# PREREQ_FCTN
# PREREQ_FRAMEWORK

# hook onto `pm_to_blib:' for this

sub postamble {
  my $self = shift;

  my @m = $self -> SUPER::postamble;

# need to create t/conf/uttu.conf

  eval { require Apache::Test; };

  my $has_apache_test = 1;

  if($@) {
    $has_apache_test = 0;
    warn "\nUnable to find Apache::Test.  Disabling automatic test creation.\n\n";
  }

  push @m, <<1HERE1;
uttu_postamble: uttu_conf extra_conf_in

uttu_conf : conf/uttu.conf.in conf/uri_map
\t$$self{NOECHO}\$(MKPATH) ./t/conf
\t$$self{NOECHO}\$(PERL) -I/usr/local/apache/perl/uttu/lib -MUttu::MakeMaker -e 'Uttu::MakeMaker->make_uttu_conf(q{\$(FRAMEWORK)},q{\$(FCTN_DIR)})' > ./t/conf/uttu.conf

extra_conf_in :
\t$$self{NOECHO}\$(MKPATH) ./conf
\t$$self{NOECHO}\$(PERL) -I/usr/local/apache/perl/uttu/lib -MUttu::MakeMaker -e 'Uttu::MakeMaker->make_extra_conf_in' > ./t/conf/extra.conf.in

1HERE1

  push @m, <<1HERE1;
install :: uttu_install

uttu_install :
\t$$self{NOECHO}\$(PERL) -I/usr/local/apache/perl/uttu/lib -MUttu::MakeMaker -e "Uttu::MakeMaker->install_files(qw{\$(SET_INST)})"
\t$$self{NOECHO}\$(PERL) -I/usr/local/apache/perl/uttu/lib -MUttu::MakeMaker -e "Uttu::MakeMaker->install_files(qw{\$(SUPPORT_INST)})"

1HERE1

  if($has_apache_test) {

    push @m, <<1HERE1;
uttu_test : t/TEST.PL t/00basic.t t/01urimap.t

t/TEST.PL :
\t$$self{NOECHO}\$(PERL) -I/usr/local/apache/perl/uttu/lib -MUttu::MakeMaker -e 'Uttu::MakeMaker->make_TEST(q{\$(FULLPERL)})' > ./t/TEST.PL

t/00basic.t : 
\t$$self{NOECHO}\$(PERL) -I/usr/local/apache/perl/uttu/lib -MUttu::MakeMaker -e 'Uttu::MakeMaker->make_t_basic(q{\$(FULLPERL)})' > ./t/00basic.t

t/01urimap.t :
\t$$self{NOECHO}\$(PERL) -I/usr/local/apache/perl/uttu/lib -MUttu::MakeMaker -e 'Uttu::MakeMaker->make_t_urimap(q{\$(FULLPERL)})' > ./t/01urimap.t

1HERE1

  } else {

    push @m, <<1HERE1;
uttu_test :

1HERE1
  }

  join('',@m);
}

###
### routines used in the Makefile
###

package Uttu::MakeMaker;

sub make_uttu_conf {
  my($class,$framework, $set) = @_;

  print <<1HERE1;
#
# This configuration file is autogenerated.  Any modifications will be
# lost.  Please make changes in ./conf/uttu.conf.in or ./conf/uri_map
#

[global]
  framework         $framework
  function_set_base $set

1HERE1

  if(-f "./conf/uri_map") {
    open my $fh, "<", "./conf/uri_map" or carp "Unable to open ./conf/uri_map: $!";
    print "#--- ./conf/uri_map\n";
    while(<$fh>) {
      chomp;
      print "$_\n" if /^\s*$/;
      print "$_\n"if /^\s*#/;
      my @bits = split(/\s+/, $_);
      print "map_uri $bits[0] = $bits[1]\n";
    }
    print while(<$fh>);
    print "\n";
    close $fh;
  }

  if(-f "./conf/uttu.conf.in") {
    open my $fh, "<", "./conf/uttu.conf.in" or carp "Unable to open ./conf/uttu.conf.in: $!";
    print "#--- ./conf/uttu.conf.in\n";
    print while(<$fh>);
    close $fh;
  }
}

sub make_extra_conf_in {
  my($class) = @_;

  print <<1HERE1
PerlModule Uttu
PerlTransHandler Uttu

<Location />
  UttuConf conf/uttu.conf
</Location>
1HERE1
}

sub make_TEST {
  my($class, $perl) = @_;

  my $use_warnings;
  $use_warnings = "use warnings FATAL => 'all';" if $] >= 5.006;

  print <<1HERE1;
#!$perl

use strict;
$use_warnings

use Apache::TestRunPerl();

Apache::TestRunPerl -> new -> run(\@ARGV);
1HERE1
}

sub make_t_basic {
  my($class, $perl) = @_;

  my $use_warnings;
  $use_warnings = "use warnings FATAL => 'all';" if $] >= 5.006;

  print <<1HERE1;
#!$perl

use strict;
$use_warnings

use Apache::Test;

plan tests => 4;

ok require 5.005002;
ok require mod_perl;
ok \$mod_perl::VERSION >= 1.24;
ok require Uttu;
1HERE1
}

sub make_t_urimap {
  my($class, $perl) = @_;

  my $use_warnings;
  $use_warnings = "use warnings FATAL => 'all';" if $] >= 5.006;

  print <<1HERE1;
#!$perl

use strict;
$use_warnings;

use Apache::Test;
use Apache::TestRequest;

unless(open FH, "< ./conf/urimap") {
  plan tests => 1;
  ok 0;
  exit;
}

my \$n = 1;

while(<FH>) {
  next if /^\\s*\$/;
  next if /^\\s*#/;
  \$n++;
}

close FH;

open FH, "< ./conf/urimap";

plan tests => \$n;

ok 1;

while(<FH>) {
  chomp;
  next if /^\\s*\$/;
  next if /^\\s*#/;
  my \@bits = split(/\\s+/, \$_);
  # bits = qw: uri file status :;
  if(\$bits[2] && \$bits[2] ne 'OK') {
    ok do something else
  } else {
    ok GET \$bits[0];
  }
}

close FH;
1HERE1
}

sub install_files {
  my $self = shift;

  while(@_) {
    my($s, $d) = splice @_, 0, 2;
    File::Path::mkpath(File::Spec -> catdir((File::Spec -> splitpath($d))[0,1]));
    File::Copy::copy($s, $d) and print "Copying $s to $d\n" or warn "copy failed: $!\n";
  }
}

1;

__END__

=head1 NAME

Uttu::MakeMaker - create a framework or function set Makefile

=head1 SYNOPSIS

  use Uttu::MakeMaker;

  WriteMakefile( ATTRIBUTE => VALUE [, ...] );

which is really

  MM->new(\%att)->flush;

with a few default parameters set.

=head1 DESCRIPTION

Uttu::MakeMaker redirects ExtUtils::MakeMaker to install frameworks and
function sets under the Uttu framework or function set directories.  This
may be overridden by specifying the PREFIX and LIB arguments on the
commandline:

  perl Makefile.PL PREFIX=/some/path LIB=/some/path/to/lib

=head2 Configuration

Uttu::MakeMaker recognizes all the arguments for ExtUtils::MakeMaker.  In
addition, it uses the following arguments to modify default
ExtUtils::MakeMaker behavior.

=over 4

=item FRAMEWORK => $framework

This defines the framework being installed.  This should only be set if
installing a framework.

This defaults to the last component of the C<NAME> parameter or the last
component of the calling package.

=item PREREQ_FRAMEWORK => [ $framework => $version ]

This defines the framework required to use the function set being installed.
This should only be set if the Makefile.PL is for a function set.

This adds C<Uttu::Framework::$framework> to the C<PREREQ_PM> configuration
argument with the given version.

=item PREREQ_FCTN => { $function_set => $version }

This is a hash of function sets mapped to versions.  This has meaning only
if C<PREREQ_FRAMEWORK> is defined.  This should only be set if the
Makefile.PL is for a function set.

This adds C<Uttu::Framework::$framework::$frameset> to the C<PREREQ_PM>
configuration argument with the given version.

=item FCTN => { function_set => install_location }

This is a list of function sets and the directories to which they will be
installed.  This overrides C<FCTNDIRS> and C<FCTN_DIR>.

=item FCTN_DIR => $install_subdir

This is the directory under the prefix which holds the function set
documents.  This corresponds to the C<global_function_set_base>
configuration variable.

Function set documents are installed into C<$PREFIX/$FCTN_DIR/$set_name/>.

The default is C<set>.

=item FCTNDIRS => [ directory list ]

This is a list of directories in which function sets are located.  The
subdirectories of these directories are the names of the function sets.
Anything below those subdirectories are considered files for installation.

For example, if C<FCTNDIRS => [ sets ]>, then C<sets/Auth/*> would denote
all the documents (e.g., HTML::Mason components) for the C<Auth> function
set that are available for export to the web.

The default value for C<FCTNDIRS> is C<sets>.

=back 4

=head1 BUGS (a.k.a. TODO LIST)

=head2 Function Set support

Uttu::MakeMaker does not yet have complete support for function sets.
Please do not expect it to work.  The configuration items for function sets
are subject to change.

=head2 URI Map Installation

Installation of URI-to-filename maps is not yet supported.

=head1 AUTHOR

James Smith <jgsmith@cpan.org>

=head1 COPYRIGHT

Copyright (C) 2002 Texas A&M University.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
