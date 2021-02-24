package OpenSMTPd::Filter;
use utf8;      # so literals and identifiers can be in UTF-8
use v5.16;     # or later to get "unicode_strings" feature and "charnames"
use strict;    # quote strings, declare variables
use warnings;  # on by default
use warnings  qw(FATAL utf8);    # fatalize encoding glitches
use open      qw(:std :encoding(UTF-8)); # undeclared streams in UTF-8

# This happens automatically, but to make pledge(2) happy
# it has to happen earlier than it would otherwise.
use IO::File;

use Carp;
use Time::HiRes qw< time >;

# ABSTRACT: Easier filters for OpenSMTPd in perl
# VERSION

my @report_fields = qw< version timestamp subsystem event session suffix >;
my %report_events = (
	'smtp-in' => {
		'link-connect'    => [qw< rdns fcrdns src dest >],
		'link-greeting'   => [qw< hostname >],
		'link-identify'   => [qw< method identity >],
		'link-tls'        => [qw< tls-string >],
		'link-disconnect' => [qw< >],
		'link-auth'       => [qw< username result >],
		'tx-reset'        => [qw< message-id >],
		'tx-begin'        => [qw< message-id >],
		'tx-mail'         => [qw< message-id result address >],
		'tx-rcpt'         => [qw< message-id result address>],
		'tx-envelope'     => [qw< message-id envelope-id >],
		'tx-data'         => [qw< message-id result >],
		'tx-commit'       => [qw< message-id message-size >],
		'tx-rollback'     => [qw< message-id >],
		'protocol-client' => [qw< command >],
		'protocol-server' => [qw< response >],
		'filter-report'   => [qw< filter-kind name message >],
		'filter-response' => [qw< phase response param>],
		'timeout'         => [qw< >],
	},
);

my @filter_fields = qw< version timestamp subsystem phase session opaque-token suffix >;
my %filter_events = (
	'smtp-in' => {
		'connect'   => [qw< rdns fcrdns src dest >],
		'helo'      => [qw< identity >],
		'ehlo'      => [qw< identity >],
		'starttls'  => [qw< tls-string >],
		'auth'      => [qw< auth >],
		'mail-from' => [qw< address >],
		'rcpt-to'   => [qw< address >],
		'data'      => [qw< >],
		'data-line' => [qw< line >],
		'commit'    => [qw< >],

		'data-lines' => sub { 'data-line' }, # special case
	},
);

my @filter_result_fields = qw< session opaque-token >;
my %filter_result_decisions = (
	#'dataline'   => [qw< line >], # special case
	'proceed'    => [qw< >],
	'junk'       => [qw< >],
	'reject'     => [qw< error >],
	'disconnect' => [qw< error >],
	'rewrite'    => [qw< parameter >],
	'report'     => [qw< parameter >],
);

sub new {
	my ( $class, %params ) = @_;

	$params{on}     ||= {};
	$params{input}  ||= \*STDIN;
	$params{output} ||= \*STDOUT;

	STDERR->autoflush;
	$params{output}->autoflush;

	# We expect to read and write bytes from the remote
	$_->binmode(':raw') for @params{qw< input output >};

	my $check_supported_events;
	$check_supported_events = sub {
		my ($c, $e, $ms) = @_;
		my $m = shift @{ $ms } || return;

		my @s = sort keys %{ $c || {} };
		if ( my @u = grep { !$e->{$_} } @s ) {
			my $s = @u == 1 ? '' : 's';
			croak("Unsupported $m$s @u");
		}

		$check_supported_events->( $c->{$_}, $e->{$_}, $ms ) for @s;
	};

	$check_supported_events->(
	    $params{on},
	    { report => \%report_events, filter => \%filter_events },
	    ["event type", "event subsystem", "event"]
	);

	my $self = bless \%params, $class;
	return $self->_init;
}

sub _init {
	my ($self) = @_;

	my $fh = $self->{input};
	my $blocking = $fh->blocking
	    // die "Unable to get blocking on input: $!";
	$fh->blocking(0) // die "Unable to set input to non-blocking: $!";

	my $timeout = 0.25;   # no idea how long we should actually wait
	my $now     = time;

	my %config;
	while ( not $self->{_ready} and ( time - $now ) < $timeout ) {
		my $line = $fh->getline // next;
		STDERR->print("< $line") if $self->{debug};
		chomp $line;
		$self->_dispatch($line);
		$now = time; # continue waiting, we got a line
	}

	$fh->blocking($blocking)
	    // die "Unable to reset blocking on input: $!";

	return $self;
}

sub ready {
	my ($self) = @_;
	croak("Input stream is not ready") unless $self->{_ready};

	my @reports = map { "report|smtp-in|$_" }
	    sort keys %{ $report_events{'smtp-in'} };

	my %filters;
	for my $subsystem (sort keys %{ $self->{on}->{filter}  }) {
		for ( keys %{ $self->{on}->{filter}->{$subsystem}  } ) {
			my $v = $filter_events{$subsystem}{$_};
			my $phase = ref $v eq 'CODE' ? $v->($_) : $_;
			$filters{"filter|$subsystem|$phase"} = 1;
		}
	}

	for (@reports, sort( keys %filters ), 'ready' ) {
		STDERR->say("> register|$_") if $self->{debug};
		$self->{output}->say("register|$_")
	}

	while ( defined( my $line = $self->{input}->getline ) ) {
		STDERR->print("< $line") if $self->{debug};
		chomp $line;
		$self->_dispatch($line);
	}
}

# The char "|" may only appear in the last field of a payload, in which
# case it should be considered a regular char and not a separator.  Other
# fields have strict formatting excluding the possibility of having a "|".
sub _dispatch {
	my ($self, $line) = @_;
	$line //= 'undef'; # no unitialized warnings
	my ($type, $extra) = split /\|/, $line, 2;
	$type //= 'unsupported'; # no uninitialized warnings

	my $method = $self->can("_handle_$type");
	return $self->$method($extra) if $method;

	croak("Unsupported: $line");
}


# general configuration information in the form of key-value lines
sub _handle_config {
	my ($self, $config) = @_;

	return $self->{_ready} = $config
	    if $config eq 'ready';

	my ($key, $value) = split /\|/, $config, 2;
	$self->{_config}->{$key} = $value;

	return $key, $value;
}


# Each report event is generated by smtpd(8) as a single line
#
# The format consists of a protocol prefix containing the stream, the
# protocol version, the timestamp, the subsystem, the event and the unique
# session identifier separated by "|":
#
# It is followed by a suffix containing the event-specific parameters, also
# separated by "|"

sub _handle_report {
	my ($self, $report) = @_;

	my %report;
	@report{@report_fields} = split /\|/, $report, @report_fields;

	my $event  = $report{event} // '';
	my $suffix = delete $report{suffix};

	my %params;
	my @fields = $self->_report_fields_for( @report{qw< subsystem event >});
	@params{ @fields } = split /\|/, $suffix, @fields
	    if @fields;

	my $session = $self->{_sessions}->{ $report{session} } ||= {};
	$session->{state}->{$_} = $report{$_} for keys %report;
	push @{ $session->{events} }, { %report, %params, request => 'report' };

	# If the session disconncted we can't do anything more with it
	delete $self->{_sessions}->{ $report{session} }
		if $event eq 'link-disconnect';

	if ( $event =~ /^tx-(.*)$/ ) {
		my $phase = $1;

		push @{ $session->{messages} },
		    $session->{state}->{message} = {}
		        if $phase eq 'begin';

		my $message = $session->{messages}->[-1];

		if ( $phase eq 'rcpt' or $phase eq 'mail' ) {
			push @{ $message->{$phase} }, $params{address};
			$message->{result} = $params{result};
		}
		else {
			$message->{$_} = $params{$_} for keys %params;
		}
	}
	else {
		$session->{state}->{$_} = $params{$_} for keys %params;
	}

	my $cb = $self->_cb_for( report => @report{qw< subsystem event >} );
	$cb->($event, $session) if $cb;

	return $session->{events}->[-1];
}

sub _handle_filter {
	my ($self, $filter) = @_;

	my %filter;
	@filter{@filter_fields} = split /\|/, $filter, @filter_fields;

	my $suffix = delete $filter{suffix};

	# For use in error messages
	my $subsystem  = $filter{subsystem};
	my $phase      = $filter{phase};
        my $session_id = $filter{session};
	$_ = defined $_ ? "'$_'" : "undef" for $subsystem, $phase, $session_id;

	my %params;
	my @fields = $self->_filter_fields_for( @filter{qw< subsystem phase >});
	@params{ @fields } = split /\|/, $suffix, @fields
	    if defined $suffix and @fields;

	my $session = $self->{_sessions}->{ $filter{session} || '' }
	    or croak("Unknown session $session_id in filter $subsystem|$phase");
	push @{ $session->{events} }, { %filter, %params, request => 'filter' };

	return $self->_handle_filter_data_line( $params{line}, \%filter, $session )
            if $filter{subsystem} eq 'smtp-in'
	   and $filter{phase}     eq 'data-line';

	my $cb = $self->_cb_for( filter => @filter{qw< subsystem phase >} );
	my @ret;
	if ($cb) {
		@ret = $cb->($filter{phase}, $session);
	}
	else {
		carp("No handler for filter $subsystem|$phase, proceeding");
		@ret = 'proceed';
	}

	my $decisions = $filter_result_decisions{ $ret[0] };
	unless ( $decisions ) {
		carp "Unknown return from filter $subsystem|$phase: @ret";

		$ret[0]    = 'reject';
		$decisions = $filter_result_decisions{ $ret[0] };
	}
	# Pass something as the reason for the rejection
	push @ret, "550 Nope" if @ret == 1
	     and ( $decisions->[0] || '' )  eq 'error';

	carp(
	    sprintf "Incorrect params from filter %s|%s, expected %s got %s",
	        $subsystem, $phase,
	        join( ' ', map {"'$_'"} 'decision', @$decisions ),
	        join( ' ', map {"'$_'"} @ret ),
	) unless @ret == 1 + @{$decisions};

	my $response = join '|',
	    'filter-result',
	     @filter{qw< session opaque-token >},
	     @ret;

	STDERR->say("> $response") if $self->{debug};
	$self->{output}->say($response);

	return {%filter};
}

sub _handle_filter_data_line {
	my ( $self, $line, $filter, $session ) = @_;
	$line //= ''; # avoid uninit warnings

	my @lines;
	if ( my $cb = $self->_cb_for( filter => @{$filter}{qw< subsystem phase >} ) ) {
		@lines = $cb->($filter->{phase}, $line, $session);
	}

	my $message = $session->{messages}->[-1];
	push @{ $message->{'data-line'} }, $line;

	if ( $line eq '.' ) {
		my $cb = $self->_cb_for( filter => $filter->{subsystem}, 'data-lines' );
		push @lines, $cb->('data-lines', $message->{'data-line'}, $session) if $cb;

		# make sure we end the message;
		push @lines, $line;
	}

	for ( map { $_ ? split /\n/ : $_  } @lines ) {
		last if $message->{'sent-dot'};
		my $response =  join '|',
		    'filter-dataline',
		    @{$filter}{qw< session opaque-token >},
		    $_;
		STDERR->say("> $response") if $self->{debug};
		$self->{output}->say($response);
		$message->{'sent-dot'} = 1 if  $_ eq '.';
	}

	return $filter;
}



sub _report_fields_for {
	my ($self, $subsystem, $event) = @_;
	return $self->_fields_for('report', \%report_events, $subsystem, $event );
}

sub _filter_fields_for {
	my ($self, $subsystem, $phase) = @_;
	return $self->_fields_for('filter', \%filter_events, $subsystem, $phase );
}

sub _fields_for {
	my ($self, $type, $map, $subsystem, $item) = @_;

	if ( $subsystem and $item and my $items = $map->{$subsystem} ) {
		return @{ $items->{$item} } if $items->{$item};
	}

	$_ = defined $_ ? "'$_'" : "undef" for $subsystem, $item;
	croak("Unsupported $type $subsystem|$item");
}

sub _cb_for {
	my ($self, @lookup) = @_;

	my $cb = $self->{on};
	$cb = $cb->{$_} || {} for @lookup;

	return $cb if ref $cb eq 'CODE';

	return;
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
