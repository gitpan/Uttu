package Uttu::Test;

use vars qw{ $REVISION };

$REVISION = sprintf("%d.%d", q$Id: $ =~ m{(\d+).(\d+)});

eval {
  require Apache::Test;
};

die <<1HERE1 if $@;
Apache::Test is required to use Uttu::Test.

Apache::Test is part of the Apache test development effort.
See http://httpd.apache.org/test/ for more information.

1HERE1

1;

__END__

=head1 NAME

Uttu::Test - framework for testing Uttu:: frameworks and funtion sets

=head1 SYNOPSIS

 use Uttu::Test;

=head1 DESCRIPTION

Uttu::Test manages the Apache::Test environment making it easier to write
test scripts for Uttu frameworks and function sets.

