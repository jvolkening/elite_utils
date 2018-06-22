package Thermo::Handler::MzML;

use strict;
use warnings;
use 5.012;

use parent 'Thermo::Handler::Converter';

sub suffix {return 'mzML'}

sub params { return
    [
        '--mzML',
        '--numpressAll',
        '--filter' => 'peakPicking true 1-',
    ];
}

1;
