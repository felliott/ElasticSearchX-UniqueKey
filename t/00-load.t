#!perl

use Test::More 0.96;
use Test::Exception;
use Test::Deep;
use ElasticSearch 0.55;
use ElasticSearch::TestServer;

BEGIN {
    use_ok('ElasticSearchX::UniqueKey') || print "Bail out!";
}

diag "";
diag(
    "Testing ElasticSearchX::UniqueKey $ElasticSearchX::UniqueKey::VERSION, Perl $], $^X"
);

our $es = eval {
    ElasticSearch::TestServer->new(
        instances   => 1,
        transport   => 'http',
        trace_calls => 'log'
    );
};

if ($es) {
    run_test_suite();
    note "Shutting down servers";
    $es->_shutdown_servers;
}
else {
    diag $_ for split /\n/, $@;
}
done_testing;

sub run_test_suite {
    isa_ok my $uniq = ElasticSearchX::UniqueKey->new( es => $es, ),
        'ElasticSearchX::UniqueKey';

    # Setup
    ok $uniq->bootstrap, 'Bootstrap';
    ok $es->index_exists( index => 'unique_key' );
    ok $es->mapping( index => 'unique_key', type => '_default_' )
        ->{_default_}, 'Has default mapping';

    is $es->index_settings( index => 'unique_key' )
        ->{unique_key}{settings}{'index.number_of_shards'}, 1,
        'Index has default settings';

    ok !$uniq->bootstrap, 'Second bootstrap OK';

    # Single tests

    ok !$uniq->exists( 'foo', 'abc' ), "foo/abc doesn't exist";
    ok $uniq->create( 'foo', 'abc' ), 'Create foo/abc';
    ok $uniq->exists( 'foo', 'abc' ), 'foo/abc exists';
    ok !$uniq->create( 'foo', 'abc' ), "Can't create foo/abc";
    ok $uniq->delete( 'foo', 'abc' ), 'Deleted foo/abc';
    ok !$uniq->exists( 'foo', 'abc' ), "foo/abc doesn't exist";
    ok !$uniq->delete( 'foo', 'abc' ), "Didn't delete foo/abc";
    ok $uniq->create( 'foo', 'abc' ), 'Create foo/abc';
    ok $uniq->update( 'foo', 'abc', 'def' ), "Updated abc -> def";
    ok !$uniq->exists( 'foo', 'abc' ), "foo/abc doesn't exist";
    ok $uniq->exists( 'foo', 'def' ), "foo/def exists";
    ok $uniq->create( 'foo', 'bar' ), 'Create foo/bar';
    ok !$uniq->update( 'foo', 'bar', 'def' ), "Didn't update bar -> def";
    ok $uniq->exists( 'foo', 'bar' ), "foo/bar exists";

    ok $uniq->update( 'foo', 'baz', 'xyz' ),
        "Updated non-existent baz -> xyz";

    ok $uniq->exists( 'foo', 'xyz' ), "foo/xyz exists";

    ok $uniq->update( 'foo', 'xyz', 'xyz' ), 'Updated to same value';
    ok $uniq->exists( 'foo', 'xyz' ), "foo/xyz exists";

    # Multi tests

    $uniq->delete_index;
    $uniq->bootstrap;

    cmp_deeply { $uniq->multi_create( foo => 1, bar => 2 ) }, {},
        'Create multi';
    cmp_deeply { $uniq->multi_exists( foo => 1, bar => 2 ) }, {},
        'Both created';

    cmp_deeply { $uniq->multi_create( foo => 1, bar => 3 ) }, { foo => 1 },
        'Create multi conflict';
    ok !$uniq->exists( bar => 3 ), 'Bar not created';

    cmp_deeply
        + {
        $uniq->multi_update( { foo => 1, bar => 2 }, { foo => 2, bar => 2 } )
        }, {}, 'Update multi';
    cmp_deeply { $uniq->multi_exists( foo => 1, bar => 2 ) }, { foo => 1 },
        'Old removed';
    cmp_deeply { $uniq->multi_exists( foo => 2 ) }, {}, 'New added';

    cmp_deeply
        + {
        $uniq->multi_update( { foo => 1, bar => 2 }, { foo => 2, bar => 3 } )
        }, { foo => 2 }, 'Update multi conflict';
    cmp_deeply { $uniq->multi_exists( foo => 2, bar => 3 ) }, { bar => 3 },
        'Update failed';
    cmp_deeply { $uniq->multi_exists( foo => 1, bar => 2 ) }, { foo => 1 },
        'Old exists';

    cmp_deeply { $uniq->multi_update( { foo => 2 }, { foo => 2, bar => 3 } ) }
    , {}, 'Update mixed';
    cmp_deeply { $uniq->multi_exists( foo => 2, bar => 3 ) }, {},
        'Mixed update';

    ok $uniq->multi_delete( foo => 2, bar => 3 ), 'Delete multi';
    cmp_deeply { $uniq->multi_exists( foo => 2, bar => 3 ) },
        { foo => 2, bar => 3 }, 'Multi deleted';

    # Custom setup

    ok $es->mapping( index => 'unique_key' )->{unique_key}{foo},
        'Has type foo';
    ok $uniq->delete_type('foo'), 'Delete type';
    ok !$es->mapping( index => 'unique_key' )->{unique_key}{foo},
        'Type deleted';
    ok $uniq->delete_index, 'Delete index';
    ok !$es->index_exists( index => 'unique_key' ), 'Index deleted';

    throws_ok sub { ElasticSearchX::UniqueKey->new },
        qr/Missing required param es/, 'No es';
    ok $uniq = ElasticSearchX::UniqueKey->new( es => $es, index => 'bar' ),
        'Custom index';
    is $uniq->index, 'bar', 'Custom index set';
    ok $uniq->bootstrap( number_of_shards => 2 ), 'Boostrapped custom index';
    ok $es->index_exists( index => 'bar' ), 'Custom index exists';
    is $es->index_settings( index => 'bar' )
        ->{bar}{settings}{'index.number_of_shards'}, 2,
        'Index has custom settings';

}
