package Thermo::Handler::GalaxyRun;

use strict;
use warnings;
use 5.012;

use Bio::Galaxy::API;
use File::Basename qw/basename/;

sub run {

    my ($class, %args) = @_;

    #$args{archive} //= 0;

    for (qw/config url/) {
        die "Parameter $_ must be defined\n"
            if (! defined $args{$_});
    }

    my $self = bless {} => $class;
    for (keys %{$args{config}}) {
        $self->{$_} = $args{config}->{$_};
    }
    $self->{url} = $args{url};

    return $self->run_wf;

}

sub run_wf {

    my ($self) = @_;

    die "Missing uploaded file ID to use for workflow input\n"
        if (! defined $self->{_mzml_file_id});
   
    my $ua = Bio::Galaxy::API->new(
        url          => $self->{url},
        check_secure => 1,
    ) or die "Failed to connect to Galaxy instance: $!\n";

    # find user
    my @want = grep {$_->{email} eq $self->{galaxy_user}} $ua->users;
    if (@want < 1) {
        die "No matching user found for $self->{galaxy_user}\n";
    }
    if (@want > 1) {
        die "Multiple matching users found for $self->{galaxy_user}\n";
    }
    my $user = $want[0];

    # reconnect as target user
    $ua = Bio::Galaxy::API->new(
        url          => $self->{url},
        check_secure => 1,
        api_key      => $user->key,
    ) or die "Failed to re-connect to Galaxy instance: $!\n";

    # find user's workflow
    @want = grep {$_->{name} eq $self->{workflow}} $ua->workflows;
    if (@want < 1) {
        die "No matching workflow found for Galaxy user $self->{workflow}\n";
    }
    if (@want > 1) {
        die "Multiple matching workflows found for Galaxy user $self->{workflow}\n";
    }
    my $wf = $want[0];

    # generate file map
    # workflow must have single input with ID 0
    my $ds_map = {
        0 => {
            src => 'ld',
            id  => $self->{_mzml_file_id}
        }
    };

    # run workflow (there are no configurable params)
    my $history_name = "$self->{workflow} on " . basename($self->{_mzml_file});
    my $res = $wf->run(
        history     => $history_name,
        ds_map      => $ds_map,
    );
    use Data::Dumper;
    say Dumper $res;
    #TODO: email results to user

    return 1;

}


1;
