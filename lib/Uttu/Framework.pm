package Uttu::Framework;

use Module::Require qw: require_glob :;
use Uttu::Tools qw: call_other :;

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

=head1 AUTHOR

James G. Smith <jsmith@cpan.org>

=head1 COPYRIGHT

Copyright (C) 2002 Texas A&M University.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
