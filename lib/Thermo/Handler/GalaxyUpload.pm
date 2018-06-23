package Thermo::Handler::GalaxyUpload;

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

    return $self->upload;

}

sub upload {

    my ($self) = @_;

    #my $output_file = "$self->{_output_path}/$self->{file}";
   
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

    # find user's library
    @want = grep {$_->{name} eq $self->{galaxy_user}} $ua->libraries;
    if (@want < 1) {
        die "No matching library found for Galaxy user $self->{galaxy_user}\n";
    }
    if (@want > 1) {
        die "Multiple matching libraries found for Galaxy user $self->{galaxy_user}\n";
    }
    my $lib = $want[0];

    # normalize path structure
    my $path = "$self->{path}/" . basename($self->{_mzml_file});
    $path =~ s/[\\\/]+/\//g;
    say "uploading to Galaxy $path";

    my $d = $lib->add_file(
        file => $self->{_mzml_file},
        path => $path,
    ) or die "Error adding file: $!\n";
    
    return $d->id;

}


1;
