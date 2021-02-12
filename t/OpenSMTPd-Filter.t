use Test2::V0 -target => 'OpenSMTPd::Filter',
	qw< ok is like mock hash field etc dies diag done_testing >;

use IO::File;

diag "Testing $CLASS on perl $^V";

ok CLASS, "Loaded $CLASS";

ok my $filter = CLASS->new, "Created a new $CLASS instance";

is fileno $filter->{input},  fileno *STDIN,  "input defaults to STDIN";
is fileno $filter->{output}, fileno *STDOUT, "output defaults to STDOUT";

ok $filter->_handle_config('foo|bar|baz'), "Able to handle_config";
is $filter->{_config}, { foo => 'bar|baz' }, "Set config correctly";

like dies { $filter->ready }, qr{\QInput stream is not ready},
    "Trying to go ready without ready from input stream is fatal";

{
	my $input = IO::File->new_tmpfile;
	$input->print("config|foo|bar\n");
	$input->print("config|foo|baz\n");
	$input->print("config|qux|quux\n");
	$input->print("config|ready\n");
	$input->print("config|ignored|value\n");
	$input->flush;
	$input->seek(0,0);

	my $f = CLASS->new( input => $input );

	is $f->{_config}, { foo => 'baz', qux => 'quux' },
	    "Config has expected values";
	ok $f->{_ready}, "Read config to ready";

	is $input->getline, "config|ignored|value\n",
		"Values after 'ready' are not read during init";

	$f->_init;

	is $f->{_config}, { foo => 'baz', qux => 'quux' },
	    "_init won't read config further after ready";

	$f->_dispatch("config|foo|bar");

	is $f->{_config}, { foo => 'bar', qux => 'quux' },
	    "But if we get a config value during processing we update it";
}

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

like dies { $filter->_dispatch }, qr{^Unsupported: undef at},
    "Fails to dispatch undef line";

like dies { $filter->_dispatch('') }, qr{^Unsupported:  at},
    "Fails to parse empty line";

like dies { $filter->_dispatch('unknown|protocol') },
    qr{^Unsupported: unknown|line at},
    "Fails to parse unknown line";

{
	my $mock = mock $CLASS => (
		track => 1,
		set => [
			_handle_subclass => sub {1},
		],
		override => [
			_handle_config   => sub {1},
			_handle_report   => sub {1},
		],
	);

	$filter->_dispatch('subclass|xxx');
	like $mock->call_tracking, [ {
	    sub_name => '_handle_subclass',
	    args     => [ $filter, 'xxx' ],
	} ], "Called _handle_subclass with expected args";
	$mock->clear_call_tracking;

	$filter->_dispatch('config|foo|bar');
	like $mock->call_tracking, [ {
	    sub_name => '_handle_config',
	    args     => [ $filter, 'foo|bar' ],
	} ], "Called _handle_config with expected args";
	$mock->clear_call_tracking;

	$filter->_dispatch('report|foo|bar');
	like $mock->call_tracking, [ {
	    sub_name => '_handle_report',
	    args     => [ $filter, 'foo|bar' ],
	} ], "Called _handle_report with expected args";
	$mock->clear_call_tracking;
}

done_testing;
