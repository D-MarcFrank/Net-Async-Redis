package Net::Async::Redis::Subscription::Message;

use strict;
use warnings;

our $VERSION = '2.002_001'; # TRIAL VERSION

=head1 NAME

Net::Async::Redis::Subscription::Message - represents a single message

=head1 DESCRIPTION

Instances are automatically generated by L<Net::Async::Redis>.

=cut

use Scalar::Util qw(weaken);

sub new {
    my ($class, %args) = @_;
    weaken($args{redis} // die 'Must be provided a Net::Async::Redis instance');
    weaken($args{subscription} // die 'Must be provided a Net::Async::Redis::Subscription instance');
    bless \%args, $class;
}

=head2 redis

Accessor for the L<Net::Async::Redis> connection.

=cut

sub redis { shift->{redis} }

=head2 subscription

Accessor for the owning L<Net::Async::Redis::Subscription>.

=cut

sub subscription { shift->{subscription} }

=head2 channel

Accessor for the channel name.

=cut

sub channel { shift->{channel} }

=head2 type

Type of this message - either C<pmessage> or C<message>.

=cut

sub type { shift->{type} }

=head2 payload

Message content (binary string).

=cut

sub payload { shift->{payload} }

sub DESTROY {
    my ($self) = @_;
    return if ${^GLOBAL_PHASE} eq 'DESTRUCT' or not my $ev = $self->{events};
    $ev->completion->done unless $ev->completion->is_ready;
}

1;

__END__

=head1 AUTHOR

Tom Molesworth <TEAM@cpan.org>

=head1 LICENSE

Copyright Tom Molesworth 2015-2020. Licensed under the same terms as Perl itself.

