package Thermo::Handler::MzML;

use strict;
use warnings;
use 5.012;

use parent 'Thermo::Handler::Converter';

sub suffix {return 'mzML'}

sub params {

    my ($self) = @_;
   
    if ($self->{_fmt} eq 'mzml') {
        return [
            '--mzML',
            '--numpressAll',
            '--filter' => 'peakPicking true 1-',
        ];
    }
    if ($self->{_fmt} eq 'mzml_nc') {
        return [
            '--mzML',
            '--numpressAll',
        ];
    }
    die "Invalid mzml format specified";

}

1;
