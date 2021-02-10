# NAME

OpenSMTPd::Filter - Easier filters for OpenSMTPd in perl

# VERSION

version v0.0.1

# SYNOPSIS

    use OpenSMTPD::Filter;
    use OpenBSD::Pledge;

    pledge();

    my $filter = OpenSMTPd::Filter->new(%params);

    $filter->ready;  # Registers and starts listening for updates

# DESCRIPTION

This module is a helper to make writing [OpenSMTPd](https://opensmtpd.org)
filters in perl easier.

# METHODS

## new

    my $filter = OpenSMTPd::Filter->new(%params);

Instantiates a new filter ready to start handling events.

## ready

    $filter->ready; # never returns until it hits eof

Starts processing events on STDIN.

# DEPENDENCIES

Perl 5.16 or higher.

# SEE ALSO

[smtpd-filters(7)](https://github.com/OpenSMTPD/OpenSMTPD/blob/master/usr.sbin/smtpd/smtpd-filters.7)

[OpenBSD::Pledge](http://man.openbsd.org/OpenBSD::Pledge)

# AUTHOR

Andrew Hewus Fresh <andrew@afresh1.com>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2021 by Andrew Hewus Fresh <andrew@afresh1.com>.

This is free software, licensed under:

    The MIT (X11) License

# POD ERRORS

Hey! **The above document had some coding errors, which are explained below:**

- Around line 65:

    Unknown directive: =head
