package Uttu::L10N;

use vars qw{ @ISA $has_locale_maketext $REVISION };

$REVISION = sprintf("%d.%d", q$Id: L10N.pm,v 1.3 2002/04/15 22:27:00 jgsmith Exp $ =~ m{(\d+).(\d+)});

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

=head1 DESCRIPTION

Uttu has minimal support for internationalization.  The reason for this is
that there are already good ways to handle language choice without
rewritting it all in Perl again.

Uttu lets Apache handle the choice of which file to serve after it has
translated the URI to a filename.  This is subject to change since it
doesn't handle well the case of HTML::Mason with different component roots
where one component root has working files masking some of the files in a
more general or production component root.

Uttu uses L<Locale::Maketext|Locale::Maketext> as the basis for its
language translation services.

If internationalization is enabled, Uttu will search through several Perl
modules, using the first one it finds.  These are, in order of preference
and following the suggested C<@ISA> chain,

 Uttu::Framework::$framework::L10N::Local::$function_set,
 Uttu::Framework::$framework::L10N::$function_set,
 Uttu::Framework::$framework::L10N::Local,
 Uttu::Framework::$framework::L10N,
 Uttu::L10N.

=head1 SEE ALSO

L<Locale::Maketext>

=head1 AUTHOR

James G. Smith <jsmith@cpan.org>

=head1 COPYRIGHT

Copyright (C) 2002 Texas A&M University.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
