requires 'parent', 0;
requires 'curry', 0;
requires 'Future', '>= 0.30';
requires 'IO::Async', 0;
requires 'Ryu::Async', '>= 0.006';
requires 'List::Util', '>= 1.29';

on 'test' => sub {
	requires 'Test::More', '>= 0.98';
};

