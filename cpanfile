requires 'parent', 0;
requires 'curry', 0;
requires 'Future', '>= 0.47';
requires 'Future::AsyncAwait', '>= 0.47';
requires 'Syntax::Keyword::Try', '>= 0.21';
requires 'IO::Async', 0;
requires 'Ryu::Async', '>= 0.019';
requires 'List::Util', '>= 1.55';
requires 'Log::Any', '>= 1.708';
requires 'URI', 0;
requires 'URI::redis', 0;
requires 'Class::Method::Modifiers', 0;
requires 'Math::Random::Secure', 0;
requires 'OpenTracing::Any', '>= 1.003';
requires 'Metrics::Any', 0;
requires 'Syntax::Keyword::Dynamically', '>= 0.06';

# Client-side caching
requires 'Cache::LRU', '>= 0.04';

# Cluster support
requires 'Digest::CRC', '>= 0.22';
requires 'List::BinarySearch::XS', '>= 0.09';

on 'test' => sub {
    requires 'Test::More', '>= 0.98';
    requires 'Test::Fatal', '>= 0.016';
    requires 'Test::HexString', 0;
    requires 'Test::Deep', 0;
    requires 'Test::MockModule', 0;
    requires 'Variable::Disposition', '>= 0.004';
};

on 'develop' => sub {
    requires 'Net::Async::HTTP';
    requires 'Template';
    requires 'HTML::TreeBuilder';
};
