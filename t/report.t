use Test2::V0 -target => 'OpenSMTPd::Filter',
	qw< ok is like dies done_testing >;

ok my $filter = CLASS->new, "Created a new $CLASS instance";

is $filter->_handle_report(
'0.5|1576146008.006099|smtp-in|link-connect|7641df9771b4ed00|mail.openbsd.org|pass|199.185.178.25:33174|45.77.67.80:25'
), {
    version   => '0.5',
    timestamp => '1576146008.006099',
    subsystem => 'smtp-in',
    event     => 'link-connect',
    session   => '7641df9771b4ed00',
    rdns      => 'mail.openbsd.org',
    fcrdns    => 'pass',
    src       => '199.185.178.25:33174',
    dest      => '45.77.67.80:25',
}, "Able to handle_report for a link-connect";

like dies { $filter->_handle_report('0.5|1576146008.006099') },
    qr{^\QUnsupported report from undef event undef at },
    "Undef report event throws exception";

like dies { $filter->_handle_report('0.5|1576146008.006099|xxx|yyy') },
    qr{^\QUnsupported report from 'xxx' event 'yyy' at },
    "Unsupported report type throws exception";

like dies { $filter->_handle_report('0.5|1576146008.006099|smtp-in|unknown') },
    qr{^\QUnsupported report from 'smtp-in' event 'unknown' at },
    "Unsupported report event throws exception";

done_testing;
