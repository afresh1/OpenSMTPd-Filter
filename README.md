# NAME

OpenSMTPd::Filter - Easier filters for OpenSMTPd in perl

# VERSION

version v0.0.2

# SYNOPSIS

    use OpenSMTPD::Filter;
    use OpenBSD::Pledge;

    pledge();

    my $filter = OpenSMTPd::Filter->new(
        on => {
            report => \%report_callbacks,
            filter => \%filter_callbacks,
        },
    );

    $filter->ready;  # Registers and starts listening for updates

# DESCRIPTION

This module is a helper to make writing [OpenSMTPd](https://opensmtpd.org)
filters in perl easier.

# METHODS

## new

    my $filter = OpenSMTPd::Filter->new(
        input  => \*STDIN,  # the default
        output => \*STDOUT, # the default
        debug  => 0,        # the default,

        on => \%callbacks,
    );

Instantiates a new filter ready to start handling events.

- on

        my $filter = OpenSMTPd::Filter->new(
            ...,
            on => {
                report => { 'smtp-in' => {
                    'link-connect' => \&lookup_spf_async,
                } },
                filter => { 'smtp-in' => {
                    helo => \&check_spf,
                    ehlo => \&check_spf,
                } },
            },
        );

    A hashref of events to add callbacks for.
    The top level is the `stream` to listen on,
    either `report` or `filter`.
    The next level is the `subsystem` which must be `smtp-in`.
    Finally the `event` or `phase` to to handle.

    See ["REPORT AND FILTER STREAMS"](#report-and-filter-streams) for details on writing callbacks.

- input

    The filehandle used to receive messages from smtpd.
    Will be changed to `binmode(":raw")`.

    Defaults to `STDIN`.

- output

    The filehandle used to send messages to smtpd.
    Will be changed to `binmode(":raw")`.

    Defaults to `STDOUT`.

- debug

    Set to a true value to enable debugging.
    Primarily this means copying all lines
    from ["input"](#input) and ["output"](#output) to `STDERR`.

## ready

    $filter->ready;

Processes events on ["input"](#input) until it hits `eof`,
which should only happen when smtpd exits.

# REPORT AND FILTER STREAMS

    my $callback = sub {
        my ( $phase_or_event, $session, @extra ) = @_;
        ...;
    };

Each stream triggers events and each event callback adds to a session
state as well as a list of events that have been received in that
session.

Each callback is called with the report event or filter phase
that triggered the callback as the first argument and a session datastructure
as the second argument.
The subsystem can be found in `$session->{state}->{subsystem}`.
Some callbacks will get additional arguments as documented below.

The `$session` hashref may contain up to three keys:

    $session = {
        state    => \%state,
        events   => \@events,
        messages => \@messages,
    };

Nothing in this session hash is used by this module other than in
each message, the `data-line` arrayref is passed to the ["data-lines"](#data-lines)
filter and the `sent-dot` boolean is used to know whether to
continue sending [filter-dataline](https://metacpan.org/pod/filter-dataline) responses.
This means your filters can munge the contents or add additional
entries although care must be taken not to change the expected type
of an entry, but adding additional keys or changing values will not
cause issues.

- state

    This is the state filled in by the fields for each received event.
    Any `tx` events go into ["messages"](#messages) instead of this state.

    A state might loook like this, however it only contains the fields
    recieved at each point in the connection and will contain any fields
    set by a ["REPORT EVENT"](#report-event):

        my $state = {
            version   => '0.6',
            timestamp => '1613356167.075372',
            subsystem => 'smtp-in',
            event     => 'timeout',
            phase     => 'commit',
            session   => '3647ceea74a815de',

            rdns      => 'localhost',
            fcrdns    => 'pass',
            src       => '[::1]:37403',
            dest      => '[::1]:25',

            hostname  => 'mail.example.test',

            method    => 'HELO',
            identity  => 'mail.afresh1.test',

            command   => '.',
            response  => '250 2.0.0 5e170a6f Message accepted for delivery',

            message   => $session->{messages}->[-1],
        };

    See the rest of this section for which events fill in each field.

- events

    This is an arrayref of hashrefs of the fields for each recieved
    message, each hashref contains all fields supplied by that report
    event or filter phase.
    In addition, the event includes a `request` field indicating
    whether the event was a report or a filter.

        my $event = {
            request   => 'report',
            version   => '0.5',
            timestamp => '1576146008.006099',
            subsystem => 'smtp-in',
            event     => 'link-connect',
            session   => '7641df9771b4ed00',
            rdns      => 'mail.openbsd.org',
            fcrdns    => 'pass',
            src       => '199.185.178.25:33174',
            dest      => '45.77.67.80:25',
        };

- messages

    Message states collect the fields provided by each `tx-*`
    ["REPORT EVENT"](#report-event) for each `message-id` in a session.

        my $message' = {
            'message-id'  => '48f59d87',
            'envelope-id' => '48f59d87264c2287',
            'mail-from',  => 'andrew',
            'rcpt-to',    => ['afresh1'],
            'data-line'   => [
                'Received: from mail (localhost [::1])',
                '   by mail.example.test (OpenSMTPD) with SMTP id 48f59d87',
                '   for <afresh1@mail.afresh1.test>;',
                '   Sat, 27 Feb 2021 20:56:38 -0800 (PST)',
                'From: andrew',
                'To: afresh1',
                'Subject: Hai!',
                '',
                'Hello There',
                '.'
            ],
            'result'   => 'ok',
            'sent-dot' => 1,
        };

    The ["tx-from"](#tx-from) and ["tx-rcpt"](#tx-rcpt) events are handled specially and
    go into the `mail-from`, `rcpt-to`, and `result` fields.
    The `rcpt-to` ends up in an arrayref as the message can be destined
    for multiple recipients.
    If a ["data-lines"](#data-lines) filter exists,
    the `data-line` field is also an arrayref of each line that has been
    recieved so far, with the `CR` and `LF` removed.
    The `sent-dot` field is a boolen indicating whether this message
    has sent the `.` indicating it is complete.

## REPORT EVENT

    my $callback = sub {
        my ( $event, $session ) = @_;
        ...;
        return 'anything'; # ignored
    };

All report events will provide these fields:

- version
- timestamp
- subsystem
- event
- session
- suffix

Events for the subsystem below may include additional fields.

- smtp-in
    - link-connect
        - rdns
        - fcrdns
        - src
        - dest
    - link-greeting
        - hostname
    - link-identify
        - method
        - identity
    - link-tls
        - tls-string
    - link-disconnect
    - link-auth
        - username
        - result
    - protocol-client
        - command
    - protocol-server
        - response
    - filter-report
        - filter-kind
        - name
        - message
    - filter-response
        - phase
        - response
        - param
    - timeout

## MESSAGE REPORT EVENTS

    my $callback = sub {
        my ($event, $session) = @_
        my $message = $session->{state}->{message};
        ...;
    };

All filters that begin with `tx-` include a `message-id` field
and possibly other fields.
These events add to the last item in ["messages"](#messages),
which is also added as the `message` field in the `session` ["state"](#state).

- message-id

Message events for the `smtp-in` subsystem may include additional fields.

- tx-reset
- tx-begin
- tx-mail
    - result
    - mail-from

        The `address` field for a `tx-mail` event is recorded as the
        `mail-from` in the message.
- tx-rcpt
    - result
    - rcpt-to

        The `address` field for a `tx-rcpt` events are recorded in the
        `rcpt-to` arrayref in the message.
- tx-envelope
    - envelope-id
- tx-data
    - result
- tx-commit
    - message-size
- tx-rollback

## FILTER REQUEST

    my $callback = sub {
        my ( $phase, $session, @data_lines ) = @_;
        ...;
        return $response, @params;
    };

See ["FILTER RESPONSE"](#filter-response) for details about what can be returned.

The ["data-line"](#data-line) and ["data-lines"](#data-lines) callbacks are special in that
they also recieve the current `data-line` or all lines recieved.
They should also return a list of ["dataline"](#dataline) responses instead of the
normal decision response.

All filter events have these fields:

- version
- timestamp
- subsystem
- phase
- session
- opaque-token

Specific filter events for each subsystem may include additional
fields.

- smtp-in
    - connect
        - rdns
        - fcrdns
        - src
        - dest
    - helo
        - identity
    - ehlo
        - identity
    - starttls
        - tls-string
    - auth
        - auth
    - mail-from
        - address
    - rcpt-to
        - address
    - data
    - commit
- data-line

    The `data-line` and `data-lines` callbacks are special in that
    they return a list of ["dataline"](#dataline) responses and not a normal
    ["FILTER RESPONSE"](#filter-response).

    The returned lines are split on `\n` so you can return a single
    string that is the entire message and it will be split into individual
    ["dataline"](#dataline) responses.

    You can return any number of lines from an individual `data-line`
    callback until you recieve the single `.` indicating the end of
    the message.
    When you recieve the single `.` as the `line` you will need to
    finish processing the message and return any lines that are still
    pending.

    - line

- data-lines

    This is a wrapper around the ["data-line"](#data-line) callback
    to make it easier to process the entire message instead
    of dealing with it on a line-by-line basis and having to
    store it yourself.

    See the ["BUGS AND LIMITATIONS"](#bugs-and-limitations),
    although this seemed like a good idea,
    to better support `pledge` it might go away
    and leave implementing data-line storage to the filter author.

    - lines

        The final argument is an arrayref of all lines in the message.

### FILTER RESPONSE

The return value from a ["FILTER REQUEST"](#filter-request) callback determines what
will be done with the message.

- dataline

    This is the special response used by ["data-line"](#data-line) filters.
    There is special processing that if the returned line contains
    newlines it will be split into multiple responses.

    - line

- proceed

        my $callback = sub {
            ...;
            return 'proceed';
        };

    This is the normal response, it means the message will continue to
    additional filters and if all filters return `proceed` the message
    will be accepted.

- junk

        my $callback = sub {
            ...;
            return 'junk';
        };

    Like ["proceed"](#proceed) but will add an `X-Spam` header to the message.

- reject

        my $callback = sub {
            ...;
            return reject => "400 Not Sure";
        };

    You must provide a valid SMTP error message as the second argument
    to the return value including the status code, 5xx or 4xx.

    A 421 status will ["disconnect"](#disconnect) the client.

    - error

- disconnect

        my $callback = sub {
            ...;
            return disconnect => "550 Go Away";
        };

    As with ["reject"](#reject) the return from this callback must include a
    valid SMTP error message including the status code.
    However, like a  `421` ["reject"](#reject) status, all messages will
    disconnect the client.

    - error

- rewrite

        my $callback = sub {
            my ($phase, $session) = @_;
            ...;
            if ( $phase eq 'tx-rcpt' ) {
                 my $event = $session->{events}->[-1];
                 return rewrite => 'afresh1'
                     if $event->{address} eq 'andrew';
            }
            return 'proceed';
        };

    - parameter

- report

    Generates a ["filter-report"](#filter-report) event with the `parameter` as the
    message that will be reported.
    I'm not entirely sure where they get reported to,
    I assume maybe any later filters.

    I believe you would do something like this,
    and that you could generate any supported event,
    but I haven't had good luck with it.

        my $s = $_[1]->{state};
        printf $output "%s|"%010.06f"|%s|%s|%s|%s\n";
            'report', Time::HiRes::time,
            $s->{subsystem}, 'filter-response', $s->{session},
            $parameter
        );

    This is not a result response.

    - parameter

# BUGS AND LIMITATIONS

The received ["data-line"](#data-line) are stored in a list in memory
if a ["data-lines"](#data-lines) filter exists,
which could easily be very large if the message is sizable.
These should instead be stored in a temporary file.

There is currently no way to stop listening for specific report events,
this module should provide a way to specify which events it should
listen for and gather state from.

# DEPENDENCIES

Perl 5.16 or higher.

# SEE ALSO

[smtpd-filters(7)](https://github.com/openbsd/src/blob/master/usr.sbin/smtpd/smtpd-filters.7)

[OpenBSD::Pledge](http://man.openbsd.org/OpenBSD::Pledge)

[OpenBSD::Unveil](http://man.openbsd.org/OpenBSD::Unveil)

# AUTHOR

Andrew Hewus Fresh <andrew@afresh1.com>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2021 by Andrew Hewus Fresh <andrew@afresh1.com>.

This is free software, licensed under:

    The MIT (X11) License
