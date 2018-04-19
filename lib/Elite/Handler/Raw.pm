package Elite::Handler::Raw;

use strict;
use warnings;
use 5.012;

use File::Copy qw/copy/;

sub run {

    my ($class, %args) = @_;

    $args{archive} //= 0;

    for (qw/config archive/) {
        die "Parameter $_ must be defined\n"
            if (! defined $args{$_});
    }

    my $self = bless {} => $class;
    for (keys %{$args{config}}) {
        $self->{$_} = $args{config}->{$_};
    }

    $self->transfer;
    $self->archive if ($self->{archive});

    return 1;

}

sub transfer {

    my ($self) = @_;

    my $output_file = "$self->{_output_path}/$self->{file}";
    
    if (-e $output_file) {
        die "Target $output_file exists and won't overwrite\n";
     }

     copy( $self->{_input_file} => $output_file )
        or die "Error copying to $output_file: $!\n";

    return 1;

}

sub archive {

    my ($self) = @_;

    #TODO: implement archiving to Glacier

    return 1;

}

1;
