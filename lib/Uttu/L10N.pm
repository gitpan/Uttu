package Uttu::L10N;

use vars qw{ @ISA $VERSION $has_locale_maketext };

$VERSION = '0.01';

eval {
  require Locale::Maketext;

  @ISA = qw(Locale::Maketext);

  $has_locale_maketext;
};

sub new {
  my $class = shift;
  $class = ref $class || $class;

  return bless { } => $class;
}

sub fallback_languages {
  my $self = shift;

  my $u = Uttu -> new;
  return @{$u->config->global_fallback_languages || []};
}

sub maketext {
  my $self = shift;
  return $self -> SUPER::maketext(@_) if $has_locale_maketext;
  return shift;
}

1;

__END__

=head1 NAME

Uttu::L10N - basic internationalization support

=head1 AUTHOR

James G. Smith <jsmith@cpan.org>

=head1 COPYRIGHT

Copyright (C) 2002 Texas A&M University.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
