package Uttu::Framework;

use Module::Require qw: require_glob :;
use Uttu::Tools qw: call_other :;

use vars qw{ $REVISION };

$REVISION = sprintf("%d.%d", q$Id: Framework.pm,v 1.3 2002/04/08 06:30:16 jgsmith Exp $ =~ m{(\d+).(\d+)});

sub init {
  my $self = shift;
  my $class = $self || ref $self;

  return if $class eq __PACKAGE__;  # should be inherited only

  my $p = $class;
  $p =~ s{::}{/}g;

#  delete @INC{grep m{^$p/} keys %INC};

  require_glob qq{$class\::*};

  call_other(qr{^$p/}, "init");
  return 1;
}

sub init_config { 1; }

1;

__END__

=head1 NAME

Uttu::Framework - inheritable module providing basic framework support

=head1 SYNOPSIS

 package Uttu::Framework::Sample;

 use Uttu::Framework;

 use vars qw{ @ISA };

 @ISA = qw{ Uttu::Framework };

 1;

=head1 DESCRIPTION

This provides basic configuration support for frameworks.  All Perl modules
whose names begin with the name of the framework (i.e.,
Uttu::Framework::Sample::*) will be loaded during server configuration time
if the C<global_framework> configuration option is set to the name of the
framework (e.g., C<Sample> for the above framework).

=head1 METHODS

=over 4

=item init

 $framework -> init();

This defines any configuration variables available for the framework.  The
default method supplied by this module will search for any packages with
the name of the framework (e.g., Uttu::Framework::Uttu->init() will search
for Uttu::Framework::Uttu::*).

If this function returns a non-true value or throws an exception, the
framework is considered invalid.

=item init_config

 $framework -> init_config($app_config);

This may be defined to set reasonable defaults for configuration
variables.  This is called after C<init()>.  An example of a configuration
setting that might be set in this call is the C<global_content_handler>
since a framework usually has a pretty good idea if it needs HTML::Mason,
the Template Toolkit, or some other handler.

If this function returns a non-true value or throws an exception, the
framework is considered invalid.

=back

=head1 AUTHOR

James G. Smith <jsmith@cpan.org>

=head1 COPYRIGHT

Copyright (C) 2002 Texas A&M University.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
