#!/usr/bin/env perl 
use strict;
use warnings;

use IO::Async::Loop;
use Net::Async::HTTP;
use Path::Tiny;
use HTML::TreeBuilder;
use Template;
use List::UtilsBy qw(extract_by);

use Log::Any qw($log);
use Log::Any::Adapter qw(Stderr), log_level => 'trace';

my $loop = IO::Async::Loop->new;
$loop->add(
    my $ua = Net::Async::HTTP->new
);

my $data = do {
    my $path = path('commands.html');
    $path->exists ? $path->slurp_utf8 : do {
        my $resp = $ua->GET('https://redis.io/commands')->get;
        $path->spew_utf8(my $txt = $resp->decoded_content);
        $txt
    }
};
my $html = HTML::TreeBuilder->new(no_space_compacting => 1);
$html->parse($data);
$html->eof;
my %commands_by_group;
my @commands;
for my $cmd ($html->look_down(_tag => 'span', class => 'command')) {
    my ($txt) = $cmd->parent->attr('href') =~ m{/commands/([\w-]+)$} or die "failed on " . $cmd->as_text;
    $txt =~ tr/-/_/;
    my @children = $cmd->content_list;
    my $command = join('', extract_by { !ref($_) } @children);
    s/^\s+//, s/\s+$// for $command;

    my $group = $cmd->parent->parent->attr('data-group') or die 'no group for ' . $cmd->as_text;
    push @{$commands_by_group{$group}}, my $info = {
        group   => $group,
        method  => $txt,
        command => $command,
        args    => [ map { s/\h+$//r } map { s/^\h+//r } grep { /\S/ } split /\n/, join '', map { $_->as_text } $cmd->parent->look_down(_tag => 'span', class => 'args') ],
        summary => join("\n", map { $_->as_text } $cmd->parent->look_down(_tag => 'span', class => 'summary')),
    };
    $info->{summary} =~ s{\.$}{};
    $log->debugf("Adding command %s", $info);
}

for my $group (sort keys %commands_by_group) {
    $log->infof('%s', $group);
    for(@{$commands_by_group{$group}}) {
        $log->infof(' * %s - %s', $_->{method}, $_->{summary});
    }
}

my $tt = Template->new;
$tt->process(\q{[% -%]
package Net::Async::Redis::Commands;

use strict;
use warnings;

# VERSION

=head1 NAME

Net::Async::Redis::Commands - mixin that defines the Redis commands available

=head1 DESCRIPTION

This is autogenerated from the list of commands available in L<https://redis.io/commands>.

It is intended to be loaded by L<Net::Async::Redis> to provide methods
for each available Redis command.

=cut

[% FOR group IN commands.keys.sort -%]
=head1 METHODS - [% group.ucfirst %]

[%  FOR command IN commands.item(group) -%]
=head2 [% command.method %]

[% command.summary %].

[%   IF command.args.size -%]
=over 4

[%    FOREACH arg IN command.args -%]
=item * [% arg %]

[%    END -%]
=back

[%   END -%]
L<https://redis.io/commands/[% command.method.lower.replace('_', '-') %]>

=cut

sub [% command.method %] : method {
    my ($self, @args) = @_;
    $self->execute_command('[% command.command %]' => @args)
}

[%  END -%]
[% END -%]
1;

__END__

=head1 AUTHOR

Tom Molesworth <TEAM@cpan.org>

=head1 LICENSE

Copyright Tom Molesworth 2015-2017. Licensed under the same terms as Perl itself.

}, { commands => \%commands_by_group }) or die $tt->error;
    
