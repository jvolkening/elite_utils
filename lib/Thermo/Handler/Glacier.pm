package Thermo::Handler::Glacier;

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use File::HomeDir;
use Net::Amazon::Glacier;

use constant MB => 1024**2;
use constant MAX_DESC_LEN => 1024;

sub run {

    my ($class, %args) = @_;

    for (qw/config/) {
        die "Parameter $_ must be defined\n"
            if (! defined $args{$_});
    }

    my $self = bless {} => $class;
    for (keys %{$args{config}}) {
        $self->{$_} = $args{config}->{$_};
    }

    return $self->archive;

}

sub archive {

    my ($self) = @_;

    my $home = File::HomeDir->my_home;

    # read in credentials and configuration values from standard locations
    my $cred = Config::Tiny->read("$home/.aws/credentials")
        or die "Error reading credentials file:", Config::Tiny->errstr;
    die "No appropriate key id found\n"
        if (! defined $cred->{rmsconvert}->{aws_access_key_id});
    die "No appropriate secret key found\n"
        if (! defined $cred->{rmsconvert}->{aws_secret_access_key});

    my $part_size   =  4 * MB;
    my $file_size   = -s $self->{_input_file};
    my @part_hashes = ();

    my $ua = Net::Amazon::Glacier->new(
        $self->{_aws_region},
        $cred->{rmsconvert}->{aws_access_key_id},
        $cred->{rmsconvert}->{aws_secret_access_key}
    );
    $self->{_ua} = $ua;

    my $desc = "$self->{path}$self->{file}";
    if (length($desc) > MAX_DESC_LEN) {
        $desc = substr $desc, -1024, 1024;
    }

    $self->{_upload_id} = $ua->multipart_upload_init(
        $self->{_vault_name},
        $part_size,
        $desc,
    );

    open my $fh_in, '<:raw', $self->{_input_file}
        or die "Error opening input file: $@\n";

    my $buffer;
    my $total_read = 0;
    my $n = 0;
    while (my $r = read $fh_in, $buffer, $part_size) {

        say "Uploading chunk $n to Glacier...";
    
        my $range_start = $total_read;
        $total_read += $r;
        if ($r != $part_size && $total_read != $file_size) {
            die "Read unexpected number of bytes ($r)";
        }

        my $tree = $ua->multipart_upload_upload_part(
            $self->{_vault_name},
            $self->{_upload_id},
            $part_size,
            $n,
            \$buffer,
        );

        push @part_hashes, $tree;
        ++$n;
    }

    my $ar_id = $ua->multipart_upload_complete(
        $self->{_vault_name},
        $self->{_upload_id},
        \@part_hashes,
        $file_size,
    );
    $self->{_upload_id} = undef;
    say "Galcier success";

    return $ar_id;

}


sub DESTROY {

    my ($self) = @_;

    return if (! defined $self->{_upload_id});

    $self->{_ua}->multipart_upload_abort(
        $self->{_vault_name},,
        $self->{_upload_id},
    );
    say "Aborted upload";

}

1;
