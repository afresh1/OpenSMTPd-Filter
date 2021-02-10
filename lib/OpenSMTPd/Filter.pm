package OpenSMTPd::Filter;
use utf8;      # so literals and identifiers can be in UTF-8
use v5.16;     # or later to get "unicode_strings" feature and "charnames"
use strict;    # quote strings, declare variables
use warnings;  # on by default
use warnings  qw(FATAL utf8);    # fatalize encoding glitches
use open      qw(:std :encoding(UTF-8)); # undeclared streams in UTF-8

use Carp;

# ABSTRACT: Easier filters for OpenSMTPd in perl
# VERSION

sub new {
	my ( $class, %params ) = @_;
	
	$params{input}  ||= \*STDIN;
	$params{output} ||= \*STDOUT;

	return bless {%params}, $class;
}

sub ready { ... }

sub _dispatch {
	my ($self, $line) = @_;
	$line //= 'undef'; # no unitialized warnings
	my ($type, $extra) = split /\|/, $line, 2;
	$type //= 'unsupported'; # no uninitialized warnings

	my $method = $self->can("_handle_$type");
	return $self->$method($extra) if $method;

	croak("Unsupported: $line");
}

sub _handle_config {
	my ($self, $config) = @_;

	my ($key, $value) = split /\|/, $config, 2;
	$self->{_config}->{$key} = $value;

	return 1;
}

1;
__END__

=head1 SYNOPSIS

    use OpenSMTPD::Filter;
    use OpenBSD::Pledge;

    pledge();

    my $filter = OpenSMTPd::Filter->new(%params);

    $filter->ready;  # Registers and starts listening for updates

=head1 DESCRIPTION

This module is a helper to make writing L<OpenSMTPd|https://opensmtpd.org>
filters in perl easier.

=head1 METHODS

=head2 new

    my $filter = OpenSMTPd::Filter->new(%params);

Instantiates a new filter ready to start handling events.

=head2 ready

    $filter->ready; # never returns until it hits eof

Starts processing events on STDIN.

=head

=head1 DEPENDENCIES

Perl 5.16 or higher.

=head1 SEE ALSO

L<smtpd-filters(7)|https://github.com/OpenSMTPD/OpenSMTPD/blob/master/usr.sbin/smtpd/smtpd-filters.7>

L<OpenBSD::Pledge|http://man.openbsd.org/OpenBSD::Pledge>