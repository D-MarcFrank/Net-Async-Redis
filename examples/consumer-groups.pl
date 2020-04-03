#!/usr/bin/env perl 
use strict;
use warnings;

# Details on the concepts and how the Redis commands work here can be found
# in https://redis.io/topics/streams-intro

use Net::Async::Redis;
use IO::Async::Loop;
use IO::Async::Timer::Periodic;

use Future::Utils qw(fmap_void fmap_concat repeat);

use Log::Any qw($log);
use Log::Any::Adapter qw(Stdout), log_level => 'info';

use Future::Utils qw(fmap0);

my $loop = IO::Async::Loop->new;

# We start with a primary connection (for initial set up and queuing new messages)
# plus several workers (for retrieving messages via XREADGROUP)
my $worker_count = 4;
my @conn = map {;
    $loop->add(
        my $redis = Net::Async::Redis->new
    );
    $redis;
} 0..$worker_count;

# This is used to shut down all the various moving parts when we want to quit.
my $active = 1;

# IDs that we expect to receive someday
my $pending = {};
# IDs that we have already processed, note that this can get very large if we
# increase the message limit
my $handled = {};

# Counts of jobs per worker (index 0 will always be zero, since no worker runs there)
my @jobs_processed_by_worker_index = (0) x $worker_count;

# How many messages we have seen
my $message_count = 0;

Future->wait_all(
    map $_->connect, @conn
)->then(sub {
    $log->debug("All instances connected, starting test");

    my ($primary) = @conn;
    $log->infof('Clearing out old streams');
    # Some of these steps may fail, so we use ->wait_all to ignore the status.
    # On the first run, the streams and groups are not expected to exist.
    Future->wait_all(
        $primary->xgroup(
            DESTROY => 'example_stream',
            'primary_group'
        )->on_ready(sub { $log->debugf('ready primary_group') }),
        $primary->xgroup(
            DESTROY => 'example_stream',
            'secondary_group',
        )->on_ready(sub { $log->debugf('ready secondary_group') }),
        $primary->del(
            'example_stream',
        )->on_ready(sub { $log->debugf('ready example_stream') }),
    )->then(sub {
        $log->infof('About to add some data to streams');
        my $start = Time::HiRes::time;
        # We'll continuously generate new messages likely averaging about 0.5ms
        # between each one, network roundtrip won't be included since it'll end
        # up pipelining multiple requests if we get a backlog.
        my $idx = 0;
        (
            repeat {
                # Don't try to add more to the queue if we think we have more than 1k
                # sat around waiting to be processed.
                my $blocked = (1000 < keys %$pending);
                Future->needs_any(
                    # We add in a 0.5s delay if we're blocked, otherwise 0..1ms delay
                    $loop->delay_future(after => (0.5 * $blocked) + (0.001 * rand)),

                    $blocked ? () : do {
                        my $id = (++$idx) . '-' . int(1_000_000 * rand);
                        # Note that we mark this as pending *before* we try sending it.
                        # Doing this in the ->on_done handler introduces a race condition:
                        # Redis might send the new item to a worker before we get the
                        # response back from the XADD command.
                        $pending->{$id} = 1;
                        $primary->xadd(
                            # * means 'just use an autogenerated ID', which is fine for our needs
                            example_stream => '*',
                            id => $id,
                        )->on_fail(sub {
                            # If something goes wrong, we should drop that item from our
                            # pending list...
                            delete $pending->{$id}
                        })
                         ->retain
                         ->without_cancel
                     }
                )
            } while => sub { $active }
        )->retain;

        $loop->add(
            IO::Async::Timer::Periodic->new(
                interval => 1,
                on_tick => sub {
                    my $elapsed = Time::HiRes::time - $start;
                    $active = 0 if $message_count > 30_000;
                    $log->infof("%d messages after %d seconds, %.2f/sec, pending %d, workers %s",
                        $message_count, $elapsed, $message_count / ($elapsed || 0),
                        0 + keys %$pending,
                        [ @jobs_processed_by_worker_index[1..$worker_count] ]
                    );
                }
            )->start
        );
        $log->infof('Set up 2 consumer groups');
        Future->needs_all(
            $primary->xgroup(
                CREATE => 'example_stream',
                primary_group => '0'
            ),
            $primary->xgroup(
                CREATE => 'example_stream',
                secondary_group => '0'
            ),
        )
    })->then(sub {
        $log->infof('Start workers');
        fmap_concat {
            my ($idx) = @_;
            my ($worker_id) = 'worker_' . $idx;
            my ($redis) = $conn[$idx];
            repeat {
                $redis->xreadgroup(
                    # Wait up to 2 seconds for a message
                    BLOCK       => 2000,
                    GROUP       => 'primary_group',
                    $worker_id,
                    COUNT       => 1,
                    STREAMS     => 'example_stream',
                    '>'
                )->then(sub {
                    my ($item) = @_;
                    # We'll receive undef if we had no message to process
                    return Future->done unless $item;

                    # Things are returned in a curiously-nested form, unpack that here
                    my ($stream, $items) = map @$_, @$item;
                    my ($id, $content) = map @$_, @$items;
                    my (%data) = @{$content || []};
                    $log->debugf('Data was %s for ID %s and data was %s', $stream, $id, \%data);

                    # Sanity check what we received
                    warn "already handled " . $data{id} if $handled->{$data{id}}++;
                    delete $pending->{$data{id}} or warn "deleting thing that should have existed - " . $data{id};

                    ++$jobs_processed_by_worker_index[$idx];
                    ++$message_count;
                    # Claim this message as processed
                    $redis->xack(
                        $stream => 'primary_group',
                        $id
                    )
                })->on_fail(sub { $log->errorf('failed future - %s', [ @_ ]) })
            } while => sub { $active }
        } foreach    => [1..$worker_count],
          concurrent => $worker_count
    })
})->get;

