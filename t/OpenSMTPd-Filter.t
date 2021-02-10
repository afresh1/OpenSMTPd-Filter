use Test2::V0 -target => 'OpenSMTPd::Filter',
	qw< ok is like mock hash field etc dies diag done_testing >;

diag "Testing $CLASS on perl $^V";

ok CLASS, "Loaded $CLASS";

ok my $filter = CLASS->new, "Created a new $CLASS instance";

is fileno $filter->{input},  fileno *STDIN,  "input defaults to STDIN";
is fileno $filter->{output}, fileno *STDOUT, "output defaults to STDOUT";

ok $filter->_handle_config('foo|bar|baz'), "Able to handle_config";
is $filter->{_config}, { foo => 'bar|baz' }, "Set config correctly";

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
}


done_testing;
