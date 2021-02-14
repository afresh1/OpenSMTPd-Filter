use Test2::V0 -target => 'OpenSMTPd::Filter',
	qw< ok is like dies diag done_testing >;

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

done_testing;
