package Uttu;

#$Id: Makefile.PL,v 1.5 2002/04/15 22:26:48 jgsmith Exp $

use ExtUtils::MakeMaker;

use Apache::ExtUtils qw: command_table :;
use Apache::src ();

eval {
  require Uttu::Config;
};

my %content_handlers = (
  HTML::Mason => 1.04,
  Template => 2.00,
);

my @available_chs = ( );

foreach my $ch (keys %content_handlers) {
  no strict;
  eval "require $ch;";
  next if $@;
  push @available_chs, $ch if ${"${ch}::VERSION"} >= $content_handlers{$ch};
}

unless(@available_chs) {
  warn "\nUnable to find a suitable content handler.  Please install at least\none of the following:\n\n";
  foreach my $ch (sort keys %content_handlers) {
    warn sprintf("  %-15s %-10s\n", $ch, $content_handlers{$ch});
  }
  warn "\n";
}

#
# list the known extra parameters for the command line
#
@Uttu::Keys = qw: 
		  UTTU_PREFIX 
		:;

# first load stuff from environment
foreach my $k (@Uttu::Keys) {
  $Uttu::Config{$k} = $ENV{$k};
}

my @replacement_args;

# now get stuff from command line to override environment
foreach (@ARGV) {
  if (/^(.+?)=(.+)/ && exists $Uttu::Config{$1}) {
    $Uttu::Config{$1} = $2;
  }
  else {
    push(@replacement_args, $_);
  }
}

# replace with any args we didn't need
@ARGV = @replacement_args;

###
### write makefile
###

my @directives = (
     { name         => 'UttuConf',
       errmsg       => 'name of UTTU configuration file',
       args_how     => 'RAW_ARGS',
       req_override => 'ACCESS_CONF',
     },
     { name         => 'UttuDefine',
       errmsg       => 'define a configuration scalar',
       args_how     => 'TAKE2',
       req_override => 'ACCESS_CONF',
     },
     { name         => 'UttuDefineList',
       errmsg       => 'define a configuration array',
       args_how     => 'ITERATE2',
       req_override => 'ACCESS_CONF',
     },
     { name         => 'UttuDefineMap',
       errmsg       => 'define a configuration mapping',
       args_how     => 'TAKE3',
       req_override => 'ACCESS_CONF',
     },
     { name         => 'Alias',
       errmsg       => 'stash Alias settings',
       args_how     => 'TAKE2',
       cmd_data     => '0',
       reg_override => 'OR_ALL',
     },
     { name         => 'AliasMatch',
       errmsg       => 'stash AliasMatch settings',
       args_how     => 'TAKE2',
       cmd_data     => '1',
       reg_override => 'OR_ALL',
     },
     { name         => 'SetHandler',
       errmsg       => 'stash SetHandler settings',
       args_how     => 'TAKE1',
       reg_override => 'OR_ALL',
     },
);

command_table(\@directives);

WriteMakefile(
  NAME         => __PACKAGE__,
  VERSION_FROM => 'lib/'.__PACKAGE__.'.pm',
  INC          => Apache::src->new->inc,
  AUTHOR       => 'James Smith <jgsmith@cpan.org>',
  ABSTRACT_FROM => 'lib/'.__PACKAGE__.'.pod',
  PREREQ_PM    => { 
		    AppConfig => 1.52,
		    Cache::Cache => 0.99,
		    DBIx::Abstract => 1.00,
		    Module::Require => 0.02,
		    mod_perl => 1.24,
		  },
  depend       => {
		    pm_to_blib => 'uttu_config',
		    dist => 'Changes',
		  },  
);

###
### extensions to MakeMaker
###

package MY;

# we want UTTU_PREFIX to be the default install location for frameworks and
# function sets - defaults to $self -> {prefix}/uttu

sub MY::constants {
  my $self = shift;

  my $uttu_prefix = $Uttu::Config{UTTU_PREFIX} || $Uttu::Config::PREFIX || $self -> {PREFIX}."/uttu";

  unless($Uttu::Config{UTTU_PREFIX}) {
    warn <<1HERE1;

To specify a default installation location for Uttu frameworks 
and function sets, specify UTTU_PREFIX:

  perl Makefile.PL UTTU_PREFIX=...

1HERE1

    if($Uttu::Config::PREFIX) {
      print "Using the previously configured value of [$uttu_prefix]\n\n";
    } else {
      print "Using a default value of [$uttu_prefix]\n\n";
    }
  }

  my @m = ($self -> SUPER::constants);

  push @m, <<1HERE1;

# --- constants for Uttu ---
UTTU_PREFIX = $uttu_prefix
1HERE1

  join('', @m);
}

sub MY::postamble {
  my $self = shift;

  my $code = <<1THERE1;
package Uttu::Config;

\\\$Uttu::Config::VERSION = '$$self{VERSION}';
\\\$Uttu::Config::PREFIX  = q{\$(UTTU_PREFIX)};

1;
1THERE1

  # \\\$ =>(via s{}{})=> \\\$\$ =>(via perl)=> \$$ =>(via make) => \$ =>(via perl)=> $
  $code =~ s{\\\$}{\\\$\$}g;

  # ' =>(via s{}{})=> '"'"' =>(via shell/make)=> '
  $code =~ s{'}{'"'"'}g;

  $code = join('\n', split(/\n/, $code));

  return <<1HERE1;
uttu_config :
\t\@echo "Creating Uttu::Config"
\t\@\$(MKPATH)  \$(INST_LIBDIR)/Uttu
\t\@\$(PERL) -e 'print qq{$code}' > \$(INST_LIBDIR)/Uttu/Config.pm

Changes : lib/Uttu/Changes.pod
\tpod2text lib/Uttu/Changes.pod > Changes

1HERE1
}
